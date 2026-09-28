import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';

/// Admin grading screen for one theory answer submission. Mirrors
/// app/admin/exam-answer/[id].tsx. Collection: app_exam_answers.
///
/// Note: the Expo app embeds a PDF viewer and uploads the checked PDF to
/// Cloudinary — both need packages this screen may not import, so the
/// submitted PDF is shown as a copyable link and the checked copy is entered
/// as a URL. Grading (score / pass-fail / note) is fully functional.
class AdminExamAnswerScreen extends StatefulWidget {
  final String id;
  const AdminExamAnswerScreen({super.key, required this.id});

  @override
  State<AdminExamAnswerScreen> createState() => _AdminExamAnswerScreenState();
}

class _Denied implements Exception {}

class _AdminExamAnswerScreenState extends State<AdminExamAnswerScreen> {
  Future<Map<String, dynamic>?>? _future;
  final _score = TextEditingController();
  final _fullMarks = TextEditingController(text: '100');
  final _reviewNote = TextEditingController();
  final _checkedPdfUrl = TextEditingController();
  bool? _passed;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _score.dispose();
    _fullMarks.dispose();
    _reviewNote.dispose();
    _checkedPdfUrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    return FirestoreRest.getDocument('app_exam_answers/${widget.id}',
        idToken: token);
  }

  void _prefill(Map<String, dynamic> a) {
    if (_score.text.isEmpty && a['score'] != null) {
      _score.text = '${a['score']}';
    }
    if (_fullMarks.text == '100' && a['fullMarks'] != null) {
      _fullMarks.text = '${a['fullMarks']}';
    }
    if (_reviewNote.text.isEmpty && a['reviewNote'] is String) {
      _reviewNote.text = a['reviewNote'] as String;
    }
    if (_checkedPdfUrl.text.isEmpty && a['checkedPdfUrl'] is String) {
      _checkedPdfUrl.text = a['checkedPdfUrl'] as String;
    }
    if (_passed == null && a['status'] == 'reviewed' && a['passed'] is bool) {
      _passed = a['passed'] as bool;
    }
  }

  String _preset(bool pass, String name) {
    final who = name.isEmpty ? 'Student' : name;
    return pass
        ? '$who, well done — your answer has been reviewed and meets the required standard. Keep up the good work.'
        : '$who, your answer has been reviewed. A few areas need more work to meet the required standard — please check the marked points and try again next time.';
  }

  Future<void> _save() async {
    final score = double.tryParse(_score.text.trim());
    final fullMarks = double.tryParse(_fullMarks.text.trim());
    if (score == null || score < 0) {
      _snack('Please enter a valid score.');
      return;
    }
    if (fullMarks == null || fullMarks <= 0) {
      _snack('Please enter valid full marks.');
      return;
    }
    if (score > fullMarks) {
      _snack('Score cannot be greater than full marks.');
      return;
    }
    if (_passed == null) {
      _snack('Please choose Pass or Fail.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm update'),
        content: Text(
            'This will mark the submission as reviewed. Score: ${_score.text}/${_fullMarks.text}, Result: ${_passed! ? 'Pass' : 'Fail'}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Update')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getValidIdToken();
      final data = <String, dynamic>{
        'score': score,
        'fullMarks': fullMarks,
        'passed': _passed,
        'reviewNote': _reviewNote.text.trim(),
        'status': 'reviewed',
        'reviewedAt': FirestoreRest.serverTimestamp(),
      };
      final checked = _checkedPdfUrl.text.trim();
      if (checked.isNotEmpty) data['checkedPdfUrl'] = checked;
      await FirestoreRest.setDocument('app_exam_answers/${widget.id}', data,
          idToken: token, merge: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submission graded and updated.')));
        context.pop();
      }
    } catch (_) {
      _snack('Could not save the grade. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Answer Update'),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (snap.error is _Denied) {
              return const Center(child: Text('Access denied'));
            }
            return const Center(child: Text('Could not load this submission.'));
          }
          final a = snap.data;
          if (a == null) {
            return const Center(
                child: Text('Submission not found — it may have been removed.'));
          }
          _prefill(a);
          return _body(a);
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _body(Map<String, dynamic> a) {
    final studentName = '${a['studentName'] ?? ''}';
    final profileName = '${a['profileName'] ?? ''}';
    final displayName = profileName.isNotEmpty && profileName != studentName
        ? '$studentName ($profileName)'
        : (studentName.isNotEmpty ? studentName : profileName);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName.isEmpty ? 'Unnamed student' : displayName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    if (a['email'] != null)
                      Text('${a['email']}',
                          style: const TextStyle(color: Colors.grey)),
                    Text(
                      '${a['courseName'] ?? ''} · ${a['subcourseName'] ?? ''}',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    Text('${a['examSetTitle'] ?? 'Untitled paper'}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13)),
                    if ((a['message'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      const Text("Student's message",
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('${a['message']}',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _score,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Score',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _fullMarks,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Full Marks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Custom message to student',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() {
                      _passed = true;
                      _reviewNote.text = _preset(true, profileName.isNotEmpty ? profileName : studentName);
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _passed == true ? Colors.green : null,
                      foregroundColor: _passed == true ? Colors.white : null,
                    ),
                    child: const Text('Pass'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() {
                      _passed = false;
                      _reviewNote.text = _preset(false, profileName.isNotEmpty ? profileName : studentName);
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _passed == false ? Colors.red : null,
                      foregroundColor: _passed == false ? Colors.white : null,
                    ),
                    child: const Text('Fail'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewNote,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Submitted PDF',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _linkBox('${a['pdfUrl'] ?? ''}'),
            const SizedBox(height: 12),
            const Text('Checked PDF',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Paste the link to your checked/marked copy of the answer sheet. This is what the student will download.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            TextField(
              controller: _checkedPdfUrl,
              decoration: const InputDecoration(
                labelText: 'Checked PDF URL (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update'),
            ),
            const SizedBox(height: 24),
          ],
        ),
        if (_saving)
          Container(
            color: Colors.black45,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _linkBox(String url) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              _snack('Link copied.');
            },
          ),
        ],
      ),
    );
  }
}
