// Upload / edit an answer sheet.
// Mirrors app/exam-answer/upload.tsx: full-name field, message field, a PDF
// attachment (<= 8MB) picked from the device and uploaded to Cloudinary the
// moment it's picked (raw/upload, exam-answers folder) so the preview below
// renders the real HTTPS URL — a guard against duplicate submissions per
// examSetId, a success screen that routes to the details, and an edit mode
// (?editId=<id>) that updates only pdfUrl + message.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import 'package:pdfx/pdfx.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';

class UploadAnswerScreen extends StatefulWidget {
  const UploadAnswerScreen({super.key});

  @override
  State<UploadAnswerScreen> createState() => _UploadAnswerScreenState();
}

class _UploadAnswerScreenState extends State<UploadAnswerScreen> {
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _editId;
  String? _examSetId;
  Map<String, dynamic>? _examSet;
  bool _done = false;
  String? _doneId;

  // Answer PDF — picked from the device, uploaded to Cloudinary the moment
  // it's picked (React parity), preview renders the picked bytes directly.
  String? _pickedName;
  int? _pickedSize;
  Uint8List? _pickedBytes;
  bool _picking = false;
  double _uploadProgress = 0;
  String? _previewUrl;
  PdfControllerPinch? _previewController;

  static const _maxPdfBytes = 8 * 1024 * 1024;

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _msgCtrl.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_picking || _submitting) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null) return; // user cancelled
    final bytes = file.bytes;
    if (bytes == null) {
      showToast(
          context,
          AppLanguage.tr(
              'Could not read that file.', 'त्यो फाइल पढ्न सकिएन।'),
          ToastVariant.error);
      return;
    }
    if (bytes.length > _maxPdfBytes) {
      showToast(
          context,
          AppLanguage.tr(
              'That PDF is larger than 8 MB. Please choose a smaller file.',
              'त्यो PDF 8 MB भन्दा ठूलो छ। सानो फाइल छान्नुहोस्।'),
          ToastVariant.error);
      return;
    }
    _previewController?.dispose();
    _previewController = null;
    setState(() {
      _pickedName = file.name;
      _pickedSize = bytes.length;
      _pickedBytes = bytes;
      _picking = true;
      _uploadProgress = 0;
      _previewUrl = null;
    });
    try {
      // Uploaded the moment it's picked (not deferred to Submit) so the
      // preview below renders a real HTTPS URL — same as React.
      final url = await CloudinaryUploader.uploadAnswerPdf(
        bytes,
        file.name,
        onProgress: (f) {
          if (mounted) setState(() => _uploadProgress = f);
        },
      );
      if (!mounted) return;
      setState(() {
        _previewUrl = url;
        _previewController =
            PdfControllerPinch(document: PdfDocument.openData(bytes));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickedName = null;
        _pickedSize = null;
        _pickedBytes = null;
      });
      showToast(
          context,
          AppLanguage.tr('Could not upload the PDF. Please try again.',
              'PDF अपलोड हुन सकेन। कृपया पुनः प्रयास गर्नुहोस्।'),
          ToastVariant.error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
        _msgCtrl.text = a?['message']?.toString() ?? '';
        _previewUrl = a?['pdfUrl']?.toString();
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
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Could not load this page.',
                'यो पेज लोड हुन सकेन।'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showToast(
          context,
          AppLanguage.tr('Please enter your full name.',
              'कृपया आफ्नो पूरा नाम लेख्नुहोस्।'),
          ToastVariant.error);
      return;
    }
    if (_previewUrl == null || _previewUrl!.isEmpty) {
      showToast(
          context,
          AppLanguage.tr('Please choose your answer-sheet PDF first.',
              'कृपया पहिले आफ्नो उत्तरपत्रको PDF छान्नुहोस्।'),
          ToastVariant.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await AuthService.getValidIdToken();
      final user = AuthService.currentUser;
      final uid = user?.uid ?? '';
      if (_editId != null && _editId!.isNotEmpty) {
        // Edit mode: update pdfUrl + message only (React: updateMyExamAnswer).
        await FirestoreRest.setDocument(
          'app_exam_answers/$_editId',
          {
            'studentName': _nameCtrl.text.trim(),
            'pdfUrl': _previewUrl,
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
            'pdfUrl': _previewUrl,
            'checkedPdfUrl': '',
            'status': 'pending',
            'score': 0,
            'fullMarks': 100,
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
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Could not submit. Please try again.',
                'पेश गर्न सकिएन। कृपया पुनः प्रयास गर्नुहोस्।'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDecoration(ExpoPalette pal, String label,
      {String? helper, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon:
          icon == null ? null : Icon(icon, size: 19, color: pal.primary),
      filled: true,
      fillColor: pal.surfaceAlt,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: pal.border, width: 0.75),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: pal.primary, width: 1.25),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final isEdit = _editId != null && _editId!.isNotEmpty;
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr(
                  isEdit ? 'Edit Answer Sheet' : 'Upload Answer Sheet',
                  isEdit
                      ? 'उत्तरपत्र सम्पादन गर्नुहोस्'
                      : 'उत्तरपत्र अपलोड गर्नुहोस्')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                  )
                : _done
                    ? _success(pal, isEdit)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_examSet != null)
                              SyllabusEntrance(
                                  delayMs: 0,
                                  child: _examBadge(pal, isEdit)),
                            SyllabusEntrance(
                              delayMs: _examSet != null ? 60 : 0,
                              child: _formCard(pal, isEdit),
                            ),
                            const SizedBox(height: 14),
                            SyllabusEntrance(
                              delayMs: _examSet != null ? 120 : 60,
                              child: _submitButton(pal, isEdit),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppLanguage.tr(
                                  isEdit
                                      ? 'Editing is only possible within 1 hour of your original submission.'
                                      : 'You can re-upload or edit this submission for 1 hour after submitting. Only one submission is allowed per paper.',
                                  isEdit
                                      ? 'सम्पादन मूल पेश गरेको १ घण्टाभित्र मात्र सम्भव छ।'
                                      : 'पेश गरेको १ घण्टाभित्र तपाईंले यो उत्तर पुनः अपलोड वा सम्पादन गर्न सक्नुहुन्छ। प्रति पेपर एउटा मात्र उत्तर पेश गर्न मिल्छ।'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: pal.textSecondary),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Exam title banner — icon + title on surfaceAlt, like React's examBadge.
  Widget _examBadge(ExpoPalette pal, bool isEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: pal.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.border, width: 0.75),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [pal.primary, const Color(0xFF1E40AF)],
                  ),
                ),
                child: const Icon(Icons.description_outlined,
                    size: 19, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr(
                          isEdit ? 'Edit for' : 'Upload for',
                          isEdit ? 'सम्पादन' : 'अपलोड'),
                      style: TextStyle(
                          fontSize: 11, color: pal.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _examSet!['title']?.toString() ??
                          AppLanguage.tr('Exam', 'परीक्षा'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: pal.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// The form in a single premium card.
  Widget _formCard(ExpoPalette pal, bool isEdit) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file_outlined,
                  size: 18, color: pal.primary),
              const SizedBox(width: 8),
              Text(
                AppLanguage.tr('Answer details', 'उत्तर विवरण'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: pal.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            decoration: _fieldDecoration(pal,
                AppLanguage.tr('Full name *', 'पूरा नाम *'),
                icon: Icons.person_outline),
          ),
          const SizedBox(height: 12),
          Text(
            AppLanguage.tr('Answer PDF *', 'उत्तर PDF *'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: pal.textPrimary),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _picking || _submitting ? null : _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: pal.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.border, width: 0.75),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_picking)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.attach_file_outlined,
                        size: 18, color: pal.primary),
                  const SizedBox(width: 8),
                  Text(
                    _picking
                        ? AppLanguage.tr('Uploading…', 'अपलोड हुँदै…')
                        : _pickedName != null
                            ? AppLanguage.tr(
                                'Change file', 'फाइल परिवर्तन गर्नुहोस्')
                            : AppLanguage.tr(
                                'Choose PDF', 'PDF छान्नुहोस्'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: pal.primary),
                  ),
                ],
              ),
            ),
          ),
          if (_pickedName != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 16, color: pal.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pickedName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: pal.textPrimary),
                    ),
                  ),
                  if (_pickedSize != null)
                    Text(
                      _formatBytes(_pickedSize!),
                      style: TextStyle(
                          fontSize: 11, color: pal.textSecondary),
                    ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                AppLanguage.tr(
                    'PDF only, up to 8 MB.', 'PDF मात्र, अधिकतम 8 MB।'),
                style:
                    TextStyle(fontSize: 11, color: pal.textSecondary),
              ),
            ),
          if (_picking) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 6,
                backgroundColor: pal.surfaceAlt,
                valueColor:
                    AlwaysStoppedAnimation<Color>(pal.primary),
              ),
            ),
          ],
          if (_previewController != null) ...[
            const SizedBox(height: 10),
            Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pal.border, width: 0.75),
              ),
              clipBehavior: Clip.antiAlias,
              child: PdfViewPinch(
                controller: _previewController!,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _msgCtrl,
            maxLines: 4,
            minLines: 3,
            decoration: _fieldDecoration(
                pal,
                AppLanguage.tr('Message for the teacher (optional)',
                    'शिक्षकका लागि सन्देश (वैकल्पिक)'),
                icon: Icons.message_outlined),
          ),
        ],
      ),
    );
  }

  /// Gradient submit button with a loading spinner on the button itself.
  Widget _submitButton(ExpoPalette pal, bool isEdit) {
    final label = AppLanguage.tr(isEdit ? 'Save Changes' : 'Submit',
        isEdit ? 'परिवर्तन बचत गर्नुहोस्' : 'पेश गर्नुहोस्');
    return GestureDetector(
      onTap: _submitting ? null : _submit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _submitting
                ? [pal.textDisabled, pal.textDisabled]
                : [pal.primary, const Color(0xFF1E40AF)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _submitting
              ? null
              : [
                  BoxShadow(
                    color: pal.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: _submitting
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 10),
                    Text(
                        AppLanguage.tr('Submitting...', 'पेश हुँदैछ...'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
        ),
      ),
    );
  }

  Widget _success(ExpoPalette pal, bool isEdit) {
    return SyllabusEntrance(
      delayMs: 60,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pal.success.withValues(alpha: 0.10),
                  border: Border.all(
                      color: pal.success.withValues(alpha: 0.30), width: 1),
                ),
                child: Icon(Icons.check_circle,
                    color: pal.success, size: 52),
              ),
              const SizedBox(height: 20),
              Text(
                  AppLanguage.tr(isEdit ? 'Updated successfully!' : 'Submitted successfully!',
                      isEdit
                          ? 'सफलतापूर्वक अद्यावधिक भयो!'
                          : 'सफलतापूर्वक पेश भयो!'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: pal.textPrimary)),
              const SizedBox(height: 10),
              Text(
                  AppLanguage.tr(
                      'Your answer sheet is now pending review.',
                      'तपाईंको उत्तरपत्र अहिले समीक्षाका लागि बाँकी छ।'),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 14, color: pal.textSecondary)),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => context.go('/exam-answer/$_doneId'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [pal.primary, const Color(0xFF1E40AF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: pal.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                      AppLanguage.tr('View Submission', 'उत्तर हेर्नुहोस्'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
