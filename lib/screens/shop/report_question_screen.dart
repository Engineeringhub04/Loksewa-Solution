// Report a question / content issue.
// Mirrors app/report-question.tsx: a question-reference field, an issue-type
// dropdown (wrong-answer / typo / duplicate / unclear / other), a description
// field, and a submit that writes an app_report_history record (mirroring
// createReportHistory) with status 'pending'.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

const List<Map<String, String>> _reasons = [
  {'id': 'wrong-answer', 'label': 'Wrong answer'},
  {'id': 'typo', 'label': 'Typo / language error'},
  {'id': 'duplicate', 'label': 'Duplicate question'},
  {'id': 'unclear', 'label': 'Unclear question'},
  {'id': 'other', 'label': 'Other'},
];

class ReportQuestionScreen extends StatefulWidget {
  const ReportQuestionScreen({super.key});

  @override
  State<ReportQuestionScreen> createState() => _ReportQuestionScreenState();
}

class _ReportQuestionScreenState extends State<ReportQuestionScreen> {
  final _refCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _reason = 'wrong-answer';
  bool _submitting = false;

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_refCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please tell us which question this is about.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await AuthService.getValidIdToken();
      final user = AuthService.currentUser;
      final uid = user?.uid ?? '';
      final qp = GoRouterState.of(context).uri.queryParameters;
      final id = '${uid}_${DateTime.now().millisecondsSinceEpoch}';
      final reasonLabel = _reasons
          .firstWhere((r) => r['id'] == _reason)['label']!;
      await FirestoreRest.setDocument(
        'app_report_history/$id',
        {
          'reporterId': uid,
          'reporterName': user?.displayName ?? 'Anonymous',
          'reporterEmail': user?.email,
          'reporterPhoto': null,
          'reporterCourseId': null,
          'reporterSubcourseId': null,
          'source': qp['source'] ?? 'question',
          'targetType': qp['targetType'] ?? 'question',
          'targetId': qp['targetId'],
          'targetTitle': _refCtrl.text.trim(),
          'targetPreview': qp['targetPreview'],
          'contextLabel': qp['contextLabel'],
          'targetAuthorName': null,
          'targetAuthorPhoto': null,
          'reason': reasonLabel,
          'description': _descCtrl.text.trim(),
          'status': 'pending',
          'adminMessage': null,
          'adminResponses': [],
          'createdAt': DateTime.now().toIso8601String(),
          'reviewedAt': null,
        },
        idToken: token,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Report submitted. Thank you!')));
        context.pop();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a Question'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Found a mistake? Tell us which question and what is wrong — '
              'our team reviews every report.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                  labelText: 'Question reference *',
                  helperText:
                      'e.g. "Mock Test 3, Q12" or paste the question text',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _reason,
              decoration: const InputDecoration(
                  labelText: 'Issue type', border: OutlineInputBorder()),
              items: _reasons
                  .map((r) => DropdownMenuItem(
                      value: r['id'], child: Text(r['label']!)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _reason = v ?? 'wrong-answer'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  helperText: 'Explain what is wrong and what it should be.',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Report',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
