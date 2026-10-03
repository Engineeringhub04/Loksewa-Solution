// Exam answer detail ("My Answer Sheet").
// Mirrors app/exam-answer/[id].tsx. When reviewed: a gradient result card
// (score / full marks, Passed / Not Passed), the teacher's note card
// (theme surface + border, tinted icon badge — NOT a hard-coded light-blue
// card, so it stays readable in dark theme), "Download Checked PDF" and
// "View Submitted PDF" buttons. When pending: a muted preview card with a
// Pending Review badge and — inside the 1-hour edit window — an Edit /
// Re-upload button routing to /exam-answer/upload?editId=<id>.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pdf_download_dialog.dart';
import '../../widgets/syllabus_entrance.dart';

const int _answerEditWindowMs = 60 * 60 * 1000;

class ExamAnswerScreen extends StatefulWidget {
  final String id;
  const ExamAnswerScreen({super.key, required this.id});

  @override
  State<ExamAnswerScreen> createState() => _ExamAnswerScreenState();
}

class _ExamAnswerScreenState extends State<ExamAnswerScreen> {
  late final Future<Map<String, dynamic>?> _future = _load();
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Ticks the edit-window countdown on the re-upload button.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_exam_answers/${widget.id}',
        idToken: token);
  }

  /// The edit section stays visible (button + countdown) for pending answers
  /// with a valid upload timestamp; the button itself goes unclickable once
  /// the 1-hour window expires.
  bool _editSectionVisible(Map<String, dynamic> a) {
    if (a['status']?.toString() != 'pending') return false;
    return DateTime.tryParse(a['createdAt']?.toString() ?? '') != null;
  }

  Duration _editRemaining(Map<String, dynamic> a) {
    final created =
        DateTime.tryParse(a['createdAt']?.toString() ?? '');
    if (created == null) return Duration.zero;
    final elapsed = DateTime.now().difference(created);
    final window = Duration(milliseconds: _answerEditWindowMs);
    return elapsed >= window ? Duration.zero : window - elapsed;
  }

  String _editCountdownText(Duration remaining) {
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// "Download Checked PDF": real byte-counted download into the phone's
  /// Downloads folder (no share sheet). Progress shows in an AppModalShell
  /// popup; on completion the popup closes and a toast confirms. Empty URL
  /// keeps the graceful "no file attached" popup.
  void _downloadCheckedPdf(String url) {
    if (url.isEmpty) {
      _showPdfDialog(
          AppLanguage.tr('Checked PDF', 'जाँचिएको PDF'), '');
      return;
    }
    final outer = context;
    AppModalShell.show(
      context: context,
      builder: (ctx) => PdfDownloadDialog(
        url: url,
        fileName: 'checked-answer-${widget.id}.pdf',
        onDone: () {
          Navigator.of(ctx).pop();
          if (mounted) {
            showToast(
                outer,
                AppLanguage.tr(
                    'PDF saved to Downloads', 'PDF डाउनलोड्समा सेभ भयो'),
                ToastVariant.success);
          }
        },
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  /// "View Submitted PDF": opens the same in-app pdfx viewer the Syllabus
  /// page and Theory mode use (native rendering, temp-cache download) on a
  /// new full page — no more link-only popup.
  void _viewSubmittedPdf(String url, String examTitle) {
    if (url.isEmpty) {
      _showPdfDialog(
          AppLanguage.tr('Submitted PDF', 'पेश गरिएको PDF'), '');
      return;
    }
    final title = examTitle.isNotEmpty
        ? examTitle
        : AppLanguage.tr('Submitted PDF', 'पेश गरिएको PDF');
    context.push(Uri(
      path: '/pdf/${Uri.encodeComponent('exam-answer-${widget.id}')}',
      queryParameters: {'uri': url, 'title': title},
    ).toString());
  }

  void _showPdfDialog(String title, String url) {
    AppModalShell.show(
      context: context,
      builder: (ctx) => AppModalShell(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFDE6E00).withValues(alpha: 0.12),
          ),
          child: const Icon(Icons.picture_as_pdf_outlined,
              size: 28, color: Color(0xFFDE6E00)),
        ),
        tagLabel: AppLanguage.tr('Answer Sheet', 'उत्तरपुस्तिका'),
        title: Text(title),
        body: SelectableText(
          url.isEmpty
              ? AppLanguage.tr('No file attached.', 'कुनै फाइल संलग्न छैन।')
              : url,
          // The shell's body region is white in both themes.
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF0F172A),
              decoration: TextDecoration.none),
        ),
        footer: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguage.tr('Close', 'बन्द गर्नुहोस्')),
          ),
        ),
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('My Answer Sheet', 'मेरो उत्तरपुस्तिका')),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                  );
                }
                if (snap.hasError) {
                  return Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              AppLanguage.tr(
                                  'Could not load answer.\n${snap.error}',
                                  'उत्तर लोड हुन सकेन।\n${snap.error}'),
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: pal.textSecondary))));
                }
                final a = snap.data;
                if (a == null) {
                  return Center(
                      child: Text(
                          AppLanguage.tr(
                              'Answer not found.', 'उत्तर भेटिएन।'),
                          style: TextStyle(color: pal.textSecondary)));
                }
                final reviewed = a['status']?.toString() == 'reviewed';
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Text(a['examSetTitle']?.toString() ??
                          AppLanguage.tr('Exam', 'परीक्षा'),
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: pal.textPrimary)),
                      if ((a['sectionName']?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(a['sectionName'].toString(),
                              style:
                                  TextStyle(color: pal.textSecondary)),
                        ),
                      const SizedBox(height: 16),
                      // Premium status timeline: Submitted -> Under Review
                      // -> Result. Shows exactly where the answer stands.
                      SyllabusEntrance(
                          delayMs: 0,
                          child: _statusTimeline(pal, a)),
                      const SizedBox(height: 16),
                      if (reviewed) ...[
                        SyllabusEntrance(
                            delayMs: 0, child: _resultCard(a)),
                        const SizedBox(height: 16),
                        if ((a['reviewNote']?.toString() ?? '').isNotEmpty) ...[
                          SyllabusEntrance(
                              delayMs: 80,
                              child: _noteCard(pal, a,
                                  a['passed'] == true)),
                          const SizedBox(height: 16),
                        ],
                        SyllabusEntrance(
                          delayMs: 140,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: pal.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14)),
                            icon: const Icon(Icons.download),
                            label: Text(AppLanguage.tr(
                                'Download Checked PDF',
                                'जाँचिएको PDF डाउनलोड गर्नुहोस्')),
                            onPressed: () => _downloadCheckedPdf(
                                a['checkedPdfUrl']?.toString() ?? ''),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SyllabusEntrance(
                          delayMs: 200,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.visibility),
                            label: Text(AppLanguage.tr(
                                'View Submitted PDF',
                                'पेश गरिएको PDF हेर्नुहोस्')),
                            onPressed: () => _viewSubmittedPdf(
                                a['pdfUrl']?.toString() ?? '',
                                a['examSetTitle']?.toString() ?? ''),
                          ),
                        ),
                      ] else ...[
                        SyllabusEntrance(
                            delayMs: 0,
                            child: _pendingCard(pal, a)),
                        const SizedBox(height: 12),
                        SyllabusEntrance(
                          delayMs: 80,
                          child: Text(
                            AppLanguage.tr(
                                'Your answer PDF has been submitted to our team. Please wait a few days (up to 7 days) — the result will appear here once a teacher has checked it.',
                                'तपाईंको उत्तर PDF हाम्रो टोलीलाई पेश गरिएको छ। कृपया केही दिन (अधिकतम ७ दिन) पर्खनुहोस् — शिक्षकले जाँचेपछि नतिजा यहाँ देखिनेछ।'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: pal.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SyllabusEntrance(
                          delayMs: 140,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.visibility),
                            label: Text(AppLanguage.tr(
                                'View Submitted PDF',
                                'पेश गरिएको PDF हेर्नुहोस्')),
                            onPressed: () => _viewSubmittedPdf(
                                a['pdfUrl']?.toString() ?? '',
                                a['examSetTitle']?.toString() ?? ''),
                          ),
                        ),
                        if (_editSectionVisible(a)) ...[
                          const SizedBox(height: 8),
                          Builder(builder: (context) {
                            final remaining = _editRemaining(a);
                            final active = remaining > Duration.zero;
                            return SyllabusEntrance(
                              delayMs: 200,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: active
                                        ? AppColors.accent
                                        : pal.textSecondary
                                            .withValues(alpha: 0.25),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14)),
                                icon: const Icon(Icons.edit),
                                label: Text(active
                                    ? AppLanguage.tr(
                                        'Edit / Re-upload Answer · ${_editCountdownText(remaining)}',
                                        'उत्तर सम्पादन / पुनः अपलोड · ${_editCountdownText(remaining)}')
                                    : AppLanguage.tr(
                                        'Edit / Re-upload Answer',
                                        'उत्तर सम्पादन / पुनः अपलोड')),
                                onPressed: active
                                    ? () => context.push(
                                        '/exam-answer/upload?editId=${widget.id}')
                                    : null,
                              ),
                            );
                          }),
                          SyllabusEntrance(
                            delayMs: 260,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Builder(builder: (context) {
                                final remaining = _editRemaining(a);
                                final active =
                                    remaining > Duration.zero;
                                return Text(
                                  active
                                      ? AppLanguage.tr(
                                          'You can edit your submission for the next ${_editCountdownText(remaining)}.',
                                          'तपाईंले अर्को ${_editCountdownText(remaining)} सम्म आफ्नो उत्तर सम्पादन गर्न सक्नुहुन्छ।')
                                      : AppLanguage.tr(
                                          'The 1-hour edit window has expired.',
                                          '१ घण्टाको सम्पादन समय सकिएको छ।'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: pal.textSecondary,
                                      fontSize: 13),
                                );
                              }),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      SyllabusEntrance(
                          delayMs: 260, child: _metaCard(pal, a)),
                      const SizedBox(height: 16),
                      SyllabusEntrance(
                          delayMs: 320, child: _helpCard(pal)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Premium status timeline: Submitted -> Under Review -> Result.
  /// Shows exactly where this answer stands, with timestamps.
  Widget _statusTimeline(ExpoPalette pal, Map<String, dynamic> a) {
    final reviewed = a['status']?.toString() == 'reviewed';
    final passed = a['passed'] == true;
    final dark = Theme.of(context).brightness == Brightness.dark;

    String fmt(dynamic raw) {
      final s = raw?.toString() ?? '';
      if (s.isEmpty) return '';
      final d = DateTime.tryParse(s);
      if (d == null) return '';
      const en = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      const ne = [
        'जनवरी', 'फेब्रुअरी', 'मार्च', 'अप्रिल', 'मे', 'जुन',
        'जुलाई', 'अगस्ट', 'सेप्टेम्बर', 'अक्टोबर', 'नोभेम्बर', 'डिसेम्बर'
      ];
      var label = '${d.day} ${en[d.month - 1]} ${d.year}';
      if (AppLanguage.isNepali) {
        label = '${d.day} ${ne[d.month - 1]} ${d.year}'.replaceAllMapped(
            RegExp(r'[0-9]'),
            (m) => '०१२३४५६७८९'[int.parse(m.group(0)!)]);
      }
      return label;
    }

    final steps = [
      _AnswerTimelineStepData(
        icon: Icons.check_rounded,
        tone: pal.success,
        state: _StepState.done,
        title: AppLanguage.tr('Submitted', 'पेश भयो'),
        subtitle: fmt(a['createdAt']).isNotEmpty
            ? fmt(a['createdAt'])
            : AppLanguage.tr('Your answer reached us.', 'तपाईंको उत्तर आयो।'),
      ),
      _AnswerTimelineStepData(
        icon: reviewed ? Icons.check_rounded : Icons.hourglass_top_outlined,
        tone: reviewed ? pal.success : pal.warning,
        state: reviewed ? _StepState.done : _StepState.active,
        title: AppLanguage.tr('Under Review', 'समीक्षामा छ'),
        subtitle: reviewed
            ? AppLanguage.tr(
                'Checked by our team.', 'हाम्रो टोलीले जाँच्यो।')
            : AppLanguage.tr('Our teachers are checking your answer.',
                'हाम्रा शिक्षकहरू तपाईंको उत्तर जाँच्दै हुनुहुन्छ।'),
      ),
      _AnswerTimelineStepData(
        icon: !reviewed
            ? Icons.lock_outline
            : (passed ? Icons.emoji_events_outlined : Icons.cancel_outlined),
        tone: !reviewed
            ? pal.textDisabled
            : (passed ? pal.success : pal.danger),
        state: !reviewed ? _StepState.locked : _StepState.done,
        title: AppLanguage.tr('Result', 'नतिजा'),
        subtitle: !reviewed
            ? AppLanguage.tr(
                'Waiting for review.', 'समीक्षाको प्रतीक्षामा।')
            : (fmt(a['reviewedAt']).isNotEmpty
                ? '${_num(a['score'])}/${_num(a['fullMarks'])} · ${fmt(a['reviewedAt'])}'
                : '${_num(a['score'])}/${_num(a['fullMarks'])}'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [Colors.white, const Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: pal.primary.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: pal.primary.withValues(alpha: dark ? 0.18 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_outlined,
                  size: 17, color: pal.primary),
              const SizedBox(width: 8),
              Text(
                AppLanguage.tr('Answer Journey', 'उत्तर यात्रा'),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: pal.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            _AnswerTimelineStep(
              data: steps[i],
              isLast: i == steps.length - 1,
              pal: pal,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> a) {    final passed = a['passed'] == true;
    final score = a['score'];
    final full = a['fullMarks'];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          passed ? Colors.green.shade700 : Colors.red.shade700,
          passed ? Colors.green.shade500 : Colors.red.shade400,
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.22),
            ),
            child: Icon(
              passed
                  ? Icons.emoji_events_outlined
                  : Icons.workspace_premium_outlined,
              size: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(passed
              ? AppLanguage.tr('Passed', 'उत्तीर्ण')
              : AppLanguage.tr('Not Passed', 'अनुत्तीर्ण'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${_num(score)} / ${_num(full)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold),
          ),
          Text(AppLanguage.tr('Score', 'अङ्क'),
              style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  /// Teacher's note — theme surface + hairline border (mirrors the React
  /// noteCard), icon badge tinted with the pass/fail result color, primary
  /// heading and secondary body text. Never a hard-coded light-blue card.
  Widget _noteCard(
      ExpoPalette pal, Map<String, dynamic> a, bool passed) {
    final resultColor = passed ? pal.success : pal.danger;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.border, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: resultColor.withValues(alpha: 0.10),
                ),
                child: Icon(Icons.chat_bubble_outline,
                    size: 16, color: resultColor),
              ),
              const SizedBox(width: 8),
              Text(AppLanguage.tr("Teacher's Note", 'शिक्षकको टिप्पणी'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: pal.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(a['reviewNote'].toString(),
              style: TextStyle(
                  fontSize: 13, color: pal.textSecondary, height: 1.55)),
        ],
      ),
    );
  }

  /// Pending state — theme surface card with the exam title, course line
  /// and an amber Pending Review badge (mirrors the React mutedCard).
  Widget _pendingCard(ExpoPalette pal, Map<String, dynamic> a) {
    final courseLine = [
      (a['courseName'] ?? '').toString(),
      (a['subcourseName'] ?? '').toString()
    ].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.border, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              ((a['examSetTitle'] ?? '').toString().isNotEmpty)
                  ? a['examSetTitle'].toString()
                  : AppLanguage.tr('Theory Answer', 'थ्योरी उत्तर'),
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: pal.textPrimary)),
          if (courseLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(courseLine,
                style:
                    TextStyle(fontSize: 13, color: pal.textSecondary)),
          ],
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: pal.warning.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_outlined,
                    size: 14, color: pal.warning),
                const SizedBox(width: 6),
                Text(
                    AppLanguage.tr(
                        'Pending Review', 'समीक्षा बाँकी'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: pal.warning)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaCard(ExpoPalette pal, Map<String, dynamic> a) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.border, width: 0.75),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLanguage.tr('Submission info', 'पेश गरिएको जानकारी'),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: pal.textPrimary)),
            const SizedBox(height: 8),
            _kv(pal, AppLanguage.tr('Student', 'विद्यार्थी'),
                a['studentName']?.toString() ?? '—'),
            _kv(pal, AppLanguage.tr('Status', 'स्थिति'),
                a['status']?.toString() ?? '—'),
            _kv(pal, AppLanguage.tr('Submitted', 'पेश गरिएको'),
                _fmtDate(a['createdAt'])),
            if ((a['message']?.toString() ?? '').isNotEmpty)
              _kv(pal, AppLanguage.tr('Message', 'सन्देश'),
                  a['message'].toString()),
          ],
        ),
      );

  /// Help card (mirrors the React helpCard): contact-our-team line plus a
  /// Contact Us button.
  Widget _helpCard(ExpoPalette pal) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pal.border, width: 0.75),
        ),
        child: Column(
          children: [
            Text(
              AppLanguage.tr(
                  'If something here looks confusing or wrong, please contact our team.',
                  'यदि यहाँ केही अन्योल वा गलत देखियो भने, कृपया हाम्रो टोलीलाई सम्पर्क गर्नुहोस्।'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: pal.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline, size: 18),
              label: Text(AppLanguage.tr('Contact Us', 'सम्पर्क गर्नुहोस्')),
              onPressed: () => context.push('/contact-us'),
            ),
          ],
        ),
      );

  Widget _kv(ExpoPalette pal, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: pal.textSecondary)),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: pal.textPrimary))),
          ],
        ),
      );

  String _num(dynamic v) {
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  String _fmtDate(dynamic v) {
    final dt = v is DateTime ? v : DateTime.tryParse(v.toString());
    if (dt == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }
}

enum _StepState { done, active, locked }

class _AnswerTimelineStepData {
  final IconData icon;
  final Color tone;
  final _StepState state;
  final String title;
  final String subtitle;

  const _AnswerTimelineStepData({
    required this.icon,
    required this.tone,
    required this.state,
    required this.title,
    required this.subtitle,
  });
}

/// One row of the answer-journey timeline: glowing status dot on a vertical
/// rail with a connector, content card to the right. The active step's dot
/// breathes (finite, settles at rest).
class _AnswerTimelineStep extends StatelessWidget {
  final _AnswerTimelineStepData data;
  final bool isLast;
  final ExpoPalette pal;

  const _AnswerTimelineStep({
    required this.data,
    required this.isLast,
    required this.pal,
  });

  @override
  Widget build(BuildContext context) {
    final active = data.state == _StepState.active;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                _dot(active),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: data.state == _StepState.locked
                            ? pal.border
                            : data.tone.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                if (isLast) const SizedBox(height: 4),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? data.tone.withValues(alpha: 0.08)
                      : pal.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? data.tone.withValues(alpha: 0.35)
                        : pal.border,
                    width: 0.75,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data.title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: data.state == _StepState.locked
                                    ? pal.textDisabled
                                    : pal.textPrimary),
                          ),
                        ),
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: data.tone,
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: Text(
                              AppLanguage.tr('NOW', 'अहिले'),
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.subtitle,
                      style: TextStyle(
                          fontSize: 12.5, color: pal.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(bool active) {
    final dot = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: data.tone.withValues(
            alpha: data.state == _StepState.locked ? 0.10 : 0.16),
        border: Border.all(
            color: data.tone.withValues(alpha: 0.45), width: 1.5),
        boxShadow: active
            ? [
                BoxShadow(
                  color: data.tone.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(data.icon, size: 17, color: data.tone),
    );
    if (!active) return dot;
    // The live step breathes: one finite 1.6s pulse that settles at rest.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      builder: (context, t, child) {
        final s = 1 + 0.08 * (1 - t) * (t < 0.5 ? t * 2 : (1 - t) * 2);
        return Transform.scale(scale: s, child: child);
      },
      child: dot,
    );
  }
}
