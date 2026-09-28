import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
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

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report submission is not connected in this build yet.'),
      ),
    );
    context.pop();
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
              hintText: 'What happened? What did you expect?',
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
