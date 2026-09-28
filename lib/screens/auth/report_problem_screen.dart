import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Report a Problem — mirrors app/settings/report-problem.tsx.
/// Category list, custom "other" text, description, optional screenshot.
/// Submission posts to the team's Google Form (relayed to Discord) — the POST
/// helper lives in the messaging service (next batch), so submit currently
/// validates and reports that it isn't connected yet. Screenshot picking needs
/// image_picker, which is not a dependency, so attach is stubbed honestly.
class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  static const _categories = [
    ('bug', 'Bug or error', 'Something crashes, freezes or will not open',
        Icons.bug_report_outlined, Colors.red),
    ('content', 'Content problem', 'Wrong answer, typo or outdated material',
        Icons.description_outlined, Color(0xFF0EA5E9)),
    ('payment', 'Payment or access',
        'Purchase not showing, billing or refund', Icons.credit_card_outlined, Colors.green),
    ('other', 'Something else', 'Anything that does not fit the options above',
        Icons.more_horiz, Color(0xFF8B5CF6)),
  ];

  String? _category;
  final _customCategory = TextEditingController();
  final _description = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _customCategory.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _isOther => _category == 'other';
  bool get _categoryReady =>
      _category != null &&
      (!_isOther || _customCategory.text.trim().isNotEmpty);
  bool get _canSubmit =>
      _categoryReady && _description.text.trim().isNotEmpty && !_submitting;

  // Google Form field ids from the form's "Get pre-filled link"
  // (mirrors AppConfig.messaging.googleForm in the Expo app).
  static const _formId = '1FAIpQLSc8fAOhc793cp8aMOAKymwtGYLT504S-yjBNixCSE8dgokGQQ';
  static const _entries = {
    'type': 'entry.592505579',
    'name': 'entry.1756370732',
    'email': 'entry.2059602454',
    'message': 'entry.633453203',
    'rating': 'entry.2878998',
    'questionReference': 'entry.168055861',
    'issueCategory': 'entry.1740941696',
    'appVersion': 'entry.1821448113',
    'platform': 'entry.458970457',
    'userId': 'entry.2072267690',
  };

  Future<void> _submitToGoogleForm(String category, String message) async {
    final user = AuthService.currentUser;
    final displayName = user?.displayName?.trim();
    final uid = user?.uid ?? 'guest';
    final userIdField =
        (displayName != null && displayName.isNotEmpty) ? '$displayName ($uid)' : uid;

    final fields = <String, String>{
      _entries['type']!: 'report',
      _entries['name']!: displayName ?? '',
      _entries['email']!: user?.email ?? '',
      _entries['message']!: message,
      _entries['issueCategory']!: 'app-problem / $category',
      _entries['appVersion']!: '1.0.0',
      _entries['platform']!: 'Android · Flutter',
      _entries['userId']!: userIdField,
    };
    final body = fields.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final res = await http.post(
      Uri.parse('https://docs.google.com/forms/d/e/$_formId/formResponse'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('GOOGLE_FORM_SUBMIT_FAILED_${res.statusCode}');
    }
  }

  Future<void> _createReportHistory(String category, String message) async {
    final user = AuthService.currentUser;
    if (user == null) return; // best-effort only
    final idToken = await AuthService.getValidIdToken();
    final id = _randomId();
    await FirestoreRest.setDocument('app_report_history/$id', {
      'reporterId': user.uid,
      'reporterName': user.displayName ?? 'Anonymous',
      'reporterEmail': user.email,
      'source': 'app',
      'targetType': 'app',
      'targetId': 'app-problem',
      'targetTitle': category,
      'targetPreview': null,
      'contextLabel': 'App · Report a Problem',
      'reason': category,
      'description': message,
      'status': 'pending',
      'adminMessage': null,
      'adminResponses': [],
      'createdAt': FirestoreRest.serverTimestamp(),
      'reviewedAt': null,
    }, idToken: idToken);
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _category == null) return;
    setState(() => _submitting = true);
    try {
      final category =
          _isOther ? _customCategory.text.trim() : _category!;
      final message = _description.text.trim();
      // No screenshot picker: image_picker is not a dependency (no new deps
      // allowed), so this always submits without one — matching the flow.
      await _submitToGoogleForm(category, message);
      // Best-effort: the report already reached support; a Firestore hiccup
      // must not turn a delivered report into a visible failure.
      try {
        await _createReportHistory(category, message);
      } catch (_) {}
      if (!mounted) return;
      showToast(context, 'Problem reported — thank you', ToastVariant.success);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Something went wrong', ToastVariant.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _attachScreenshot() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Screenshot upload is not available in this build yet.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Report a Problem'),
          Expanded(
            child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.navy,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Send us the details and we will look into it.',
                style: TextStyle(color: Color(0xFFD7E3FF), height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Category',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Pick the closest match',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _categories.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  _categoryRow(_categories[i]),
                ],
              ],
            ),
          ),
          if (_isOther) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customCategory,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Other',
                hintText: 'Describe it below',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Describe the problem',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Add any detail that helps us fix it faster',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLines: 5,
            minLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Describe the problem',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _attachScreenshot,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Attach Screenshot (optional)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _canSubmit ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(
      (String, String, String, IconData, Color) item) {
    final selected = _category == item.$1;
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: selected ? item.$5 : item.$5.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Icon(item.$4,
            size: 17,
            color: selected ? Colors.white : item.$5),
      ),
      title: Text(item.$2,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(item.$3,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? item.$5 : Colors.grey.shade400,
              width: 1.5),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.$5,
                  ),
                ),
              )
            : null,
      ),
      onTap: () => setState(() => _category = item.$1),
    );
  }
}
