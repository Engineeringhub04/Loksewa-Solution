// Profile → App Settings → Report Question.
//
// Mirrors app/report-question.tsx: three titled blocks (which question /
// what is wrong / describe the problem), a filled-step pill in the hero,
// offline blocking, and the submit path `submitQuestionReport` → Google Form
// (the copy support actually reads) + the private Firestore report-history
// copy, awaited together.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/syllabus_entrance.dart';

class _Issue {
  final String value;
  final String labelEn;
  final String labelNe;
  const _Issue(this.value, this.labelEn, this.labelNe);
}

const _issues = [
  _Issue('wrong-answer', 'Wrong answer marked correct',
      'गलत उत्तर सही देखाइएको'),
  _Issue('typo', 'Spelling or typo', 'हिज्जे वा टाइपिङ गल्ती'),
  _Issue('duplicate', 'Duplicate question', 'दोहोरो प्रश्न'),
  _Issue('unclear', 'Question is unclear', 'प्रश्न अस्पष्ट छ'),
  _Issue('other', 'Something else', 'अन्य कुरा'),
];

class ReportQuestionScreen extends StatefulWidget {
  const ReportQuestionScreen({super.key});

  @override
  State<ReportQuestionScreen> createState() => _ReportQuestionScreenState();
}

class _ReportQuestionScreenState extends State<ReportQuestionScreen> {
  final _refCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _issue;
  bool _sending = false;
  bool? _offline;
  bool _refParamRead = false;

  @override
  void initState() {
    super.initState();
    _checkOnline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The screen can be opened with ?questionRef=... pre-filled, exactly
    // like the Expo screen's `questionRef` search param.
    if (!_refParamRead) {
      _refParamRead = true;
      final qp = GoRouterState.of(context).uri.queryParameters;
      final prefill = (qp['questionRef'] ?? '').trim();
      if (prefill.isNotEmpty) _refCtrl.text = prefill;
    }
  }

  Future<void> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(() =>
          _offline = results.every((r) => r == ConnectivityResult.none));
    } catch (_) {
      if (mounted) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _refCtrl.text.trim().isNotEmpty &&
      _issue != null &&
      _descCtrl.text.trim().isNotEmpty &&
      !_sending;

  int get _filled =>
      [
        _refCtrl.text.trim().isNotEmpty,
        _issue != null,
        _descCtrl.text.trim().isNotEmpty
      ].where((e) => e).length;

  Future<void> _submit() async {
    final issue = _issue;
    if (!_canSubmit || issue == null) return;
    setState(() => _sending = true);
    try {
      await ReportService.submitQuestionReport(
        questionRef: _refCtrl.text,
        issue: issue,
        description: _descCtrl.text,
      );
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Thanks! Your report has been sent.',
              'धन्यवाद! तपाईंको रिपोर्ट पठाइयो।'),
          ToastVariant.success);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      showToast(context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final offline = _offline == true;
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Report Question', 'प्रश्न रिपोर्ट')),
          Expanded(
            child: offline ? _offlineBody(pal) : _formBody(pal),
          ),
        ],
      ),
    );
  }

  Widget _hero(ExpoPalette pal) {
    final offline = _offline == true;
    final filled = _filled;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.primary, const Color(0xFF1E40AF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0x1A / 0xFF),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0x29 / 0xFF),
                ),
                child: const Icon(Icons.help_outline,
                    size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr(
                          'Report a problem', 'समस्या रिपोर्ट गर्नुहोस्'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLanguage.tr(
                          'Spotted a mistake in a question? Tell us and we will review it.',
                          'कुनै प्रश्नमा गल्ती भेट्नुभयो? हामीलाई भन्नुहोस्, हामी समीक्षा गर्नेछौं।'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0xCC / 0xFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Filled-step count — the one piece of feedback the old form never
          // gave: what is still missing before submit lights up.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: 0x1F / 0xFF),
            ),
            child: offline
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 12, color: Color(0xFFFCD34D)),
                      const SizedBox(width: 6),
                      Text(
                        AppLanguage.tr(
                            'You are offline. Check your connection and try again.',
                            'तपाईं अफलाइन हुनुहुन्छ। जडान जाँचेर फेरि प्रयास गर्नुहोस्।'),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFFCD34D)),
                      ),
                    ],
                  )
                : StatusPill(
                    label: '$filled/3',
                    color: filled == 3
                        ? const Color(0xFF6EE7B7)
                        : Colors.white,
                    icon: filled == 3
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBody(ExpoPalette pal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.warning.withValues(alpha: 0x14 / 0xFF),
              border: Border.all(
                color: pal.warning.withValues(alpha: 0x33 / 0xFF),
                width: 0.75,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 24, color: pal.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLanguage.tr(
                            'You are offline. Check your connection and try again.',
                            'तपाईं अफलाइन हुनुहुन्छ। जडान जाँचेर फेरि प्रयास गर्नुहोस्।'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: pal.warning),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLanguage.tr(
                            'This requires an internet connection',
                            'यसका लागि इन्टरनेट जडान आवश्यक छ'),
                        style: TextStyle(
                            fontSize: 12, color: pal.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              setState(() => _offline = null);
              _checkOnline();
            },
            child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास')),
          ),
        ],
      ),
    );
  }

  Widget _formBody(ExpoPalette pal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SyllabusEntrance(delayMs: 0, child: _hero(pal)),
          const SizedBox(height: 14),
          SyllabusEntrance(
            delayMs: 60,
            child: _SectionCard(
              pal: pal,
              icon: Icons.bookmark_outline,
              tone: pal.info,
              title: AppLanguage.tr('Which question?', 'कुन प्रश्न?'),
              child: TextField(
                controller: _refCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: AppLanguage.tr(
                      'e.g. "Mock Test 2, question 14" or the question text',
                      'जस्तै "मक टेस्ट २, प्रश्न १४" वा प्रश्नको बेहोरा'),
                  prefixIcon:
                      const Icon(Icons.bookmark_outline, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SyllabusEntrance(
            delayMs: 120,
            child: _SectionCard(
              pal: pal,
              icon: Icons.tune_outlined,
              tone: pal.warning,
              title: AppLanguage.tr('What is wrong?', 'के गलत छ?'),
              child: DropdownButtonFormField<String>(
                initialValue: _issue,
                hint: Text(AppLanguage.tr(
                    'Select an issue', 'समस्या छान्नुहोस्')),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _issues
                    .map((i) => DropdownMenuItem(
                          value: i.value,
                          child: Text(AppLanguage.tr(i.labelEn, i.labelNe)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _issue = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SyllabusEntrance(
            delayMs: 180,
            child: _SectionCard(
              pal: pal,
              icon: Icons.description_outlined,
              tone: pal.primary,
              title: AppLanguage.tr(
                  'Describe the problem', 'समस्या वर्णन गर्नुहोस्'),
              subtitle: AppLanguage.tr(
                  'The more detail you give, the faster we can fix it.',
                  'जति धेरै विवरण दिनुहुन्छ, त्यति चाँडो सुधार गर्न सक्छौं।'),
              child: TextField(
                controller: _descCtrl,
                minLines: 5,
                maxLines: 8,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: AppLanguage.tr(
                      'What should the correct explanation be?',
                      'सही व्याख्या के हुनुपर्थ्यो?'),
                  alignLabelWithHint: true,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SyllabusEntrance(
            delayMs: 240,
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: pal.primary,
                  disabledBackgroundColor:
                      pal.textDisabled.withValues(alpha: 0x66 / 0xFF),
                  foregroundColor: Colors.white,
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0xAA / 0xFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        AppLanguage.tr('Submit', 'पेश गर्नुहोस्'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled block — mirrors the Expo `SectionCard`: tone icon + title, the
/// input underneath drops its duplicate label.
class _SectionCard extends StatelessWidget {
  final ExpoPalette pal;
  final IconData icon;
  final Color tone;
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({
    required this.pal,
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border, width: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: tone.withValues(
                      alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF),
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: pal.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                            fontSize: 11, color: pal.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
