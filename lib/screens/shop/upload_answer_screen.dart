// Upload / edit an answer sheet.
// Mirrors app/exam-answer/upload.tsx: full-name field, message field, a PDF
// attachment (<= 8MB), a guard against duplicate submissions per examSetId,
// a success screen that routes to the details, and an edit mode
// (?editId=<id>) that updates only pdfUrl + message.
// NOTE (Flutter): the Expo app uploads the PDF to Cloudinary and stores the
// URL. This build has no file-picker/upload plugin wired, so the PDF is
// supplied as a URL field; the Firestore write below is the same shape the
// Expo app produces after its upload step.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

class UploadAnswerScreen extends StatefulWidget {
  const UploadAnswerScreen({super.key});

  @override
  State<UploadAnswerScreen> createState() => _UploadAnswerScreenState();
}

class _UploadAnswerScreenState extends State<UploadAnswerScreen> {
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _pdfCtrl = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _editId;
  String? _examSetId;
  Map<String, dynamic>? _examSet;
  Map<String, dynamic>? _existing; // in edit mode
  bool _done = false;
  String? _doneId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _msgCtrl.dispose();
    _pdfCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final qp = GoRouterState.of(context).uri.queryParameters;
    _editId = qp['editId'];
    _examSetId = qp['examSetId'];
    try {
      final token = await AuthService.getValidIdToken();
      final user = AuthService.currentUser;
      _nameCtrl.text = user?.displayName ?? '';
      if (_editId != null && _editId!.isNotEmpty) {
        final a = await FirestoreRest.getDocument(
            'app_exam_answers/$_editId',
            idToken: token);
        _existing = a;
        _msgCtrl.text = a?['message']?.toString() ?? '';
        _pdfCtrl.text = a?['pdfUrl']?.toString() ?? '';
        _nameCtrl.text = a?['studentName']?.toString() ?? _nameCtrl.text;
      } else if (_examSetId != null && _examSetId!.isNotEmpty) {
        final results = await Future.wait([
          FirestoreRest.getDocument('app_exam_sets/$_examSetId',
              idToken: token),
          FirestoreRest.listDocuments('app_exam_answers',
              idToken: token, pageSize: 200),
        ]);
        _examSet = results[0] as Map<String, dynamic>?;
        final mine = (results[1] as List<Map<String, dynamic>>).where((d) =>
            d['uid']?.toString() == user?.uid &&
            d['examSetId']?.toString() == _examSetId);
        if (mine.isNotEmpty) {
          // Duplicate guard: route to the existing submission instead.
          final id = mine.first['id']?.toString() ?? '';
          if (mounted) context.go('/exam-answer/$id');
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Load failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your full name.')));
      return;
    }
    if (_pdfCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please paste your answer-sheet PDF URL (<= 8MB).')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await AuthService.getValidIdToken();
      final user = AuthService.currentUser;
      final uid = user?.uid ?? '';
      if (_editId != null && _editId!.isNotEmpty) {
        // Edit mode: update pdfUrl + message only.
        await FirestoreRest.setDocument(
          'app_exam_answers/$_editId',
          {
            'studentName': _nameCtrl.text.trim(),
            'pdfUrl': _pdfCtrl.text.trim(),
            'message': _msgCtrl.text.trim(),
            'updatedAt': DateTime.now().toIso8601String(),
          },
          merge: true,
          idToken: token,
        );
        setState(() {
          _done = true;
          _doneId = _editId;
        });
      } else {
        final id = '${uid}_${_examSetId}_${DateTime.now().millisecondsSinceEpoch}';
        await FirestoreRest.setDocument(
          'app_exam_answers/$id',
          {
            'uid': uid,
            'studentName': _nameCtrl.text.trim(),
            'profileName': user?.displayName,
            'photoURL': null,
            'email': user?.email,
            'courseId': _examSet?['courseId'],
            'courseName': _examSet?['courseName'],
            'subcourseId': _examSet?['subcourseId'],
            'subcourseName': _examSet?['subcourseName'],
            'examSetId': _examSetId,
            'examSetTitle': _examSet?['title'],
            'sectionName': _examSet?['sectionName'],
            'message': _msgCtrl.text.trim(),
            'pdfUrl': _pdfCtrl.text.trim(),
            'checkedPdfUrl': '',
            'status': 'pending',
            'score': 0,
            'fullMarks': _examSet?['fullMarks'] ?? 0,
            'passed': false,
            'reviewNote': '',
            'createdAt': DateTime.now().toIso8601String(),
            'reviewedAt': null,
          },
          idToken: token,
        );
        setState(() {
          _done = true;
          _doneId = id;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Submit failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _editId != null && _editId!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Answer Sheet' : 'Upload Answer Sheet'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _done
              ? _success()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_examSet != null)
                        Card(
                          color: AppColors.navy.withValues(alpha: 0.06),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                _examSet!['title']?.toString() ?? 'Exam',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Full name *',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pdfCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Answer-sheet PDF URL *',
                            helperText:
                                'Max 8MB. In the full app this uploads your PDF directly; here paste the file link.',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _msgCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            labelText: 'Message for the teacher (optional)',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16)),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(isEdit ? 'Save Changes' : 'Submit',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _success() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle,
                  color: Colors.green, size: 72),
              const SizedBox(height: 16),
              const Text('Submitted successfully!',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Your answer sheet is now pending review.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white),
                onPressed: () =>
                    context.go('/exam-answer/$_doneId'),
                child: const Text('View Submission'),
              ),
            ],
          ),
        ),
      );
}
