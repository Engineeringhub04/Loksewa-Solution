// Exam answer detail ("My Answer Sheet").
// Mirrors app/exam-answer/[id].tsx. When reviewed and published: a gradient
// result card (score / full marks, Passed / Not Passed), the teacher's note
// section card, a "View Checked PDF" button with a download icon tile, and
// "View Submitted PDF". When reviewed but rejected (admin saved a
// rejectionReason): no result card — a Reason card carries the admin's
// reason + message instead. When pending: a premium preview card with a
// Pending Review badge and — inside the 1-hour edit window — an Edit /
// Re-upload button routing to /exam-answer/upload?editId=<id>.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pdf_download_dialog.dart';
import '../../widgets/request_info_row.dart';
import '../../widgets/request_section_card.dart';
import '../../widgets/syllabus_entrance.dart';

/// Save filename for a downloaded checked-answer PDF (v1.0.121),
/// derived from the exam set TITLE — never from the raw answer doc
/// id: that id contains a literal space and is extremely long, and
/// phone PDF viewers opening the file from the Downloads folder
/// choked on the name ("invalid format"). Sanitizing keeps ASCII
/// letters/digits, collapses every other run of characters into a
/// single '-', trims edge dashes, and caps the title part at 48
/// chars; a title with nothing keepable falls back to a fixed name.
String checkedAnswerFileName(String examSetTitle) {
  var sanitized = examSetTitle
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (sanitized.length > 48) {
    sanitized = sanitized.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  }
  return sanitized.isEmpty
      ? 'checked-answer-sheet.pdf'
      : 'checked-answer-$sanitized.pdf';
}

const int _answerEditWindowMs = 60 * 60 * 1000;

/// Time left in the 1-hour edit window (zero once it has expired).
Duration _editRemainingFor(Map<String, dynamic> a) {
  final created = DateTime.tryParse(a['createdAt']?.toString() ?? '');
  if (created == null) return Duration.zero;
  final elapsed = DateTime.now().difference(created);
  const window = Duration(milliseconds: _answerEditWindowMs);
  return elapsed >= window ? Duration.zero : window - elapsed;
}

/// One edit only (v1.0.120): a successful edit stamps `editUsedAt` on the
/// doc; once present, the edit allowance is spent even inside the window.
bool _editUsedFor(Map<String, dynamic> a) =>
    (a['editUsedAt']?.toString().trim().isNotEmpty ?? false);

String _editCountdownTextFor(Duration remaining) {
  final m = remaining.inMinutes;
  final s = remaining.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class ExamAnswerScreen extends StatefulWidget {
  final String id;
  const ExamAnswerScreen({super.key, required this.id});

  @override
  State<ExamAnswerScreen> createState() => _ExamAnswerScreenState();
}

class _ExamAnswerScreenState extends State<ExamAnswerScreen> {
  // v1.0.120 render-first: this future used to include display-name
  // resolution, so NOTHING painted until the slowest lookup finished.
  // Now it completes with the raw doc the moment it arrives; the names
  // resolve in the background and patch in via [_patched] (the builder
  // below prefers it over the future's raw doc). The old whole-page
  // 1-second setState countdown timer is gone too — the edit countdown
  // ticks inside its own widget (_EditCountdownSection).
  late final Future<Map<String, dynamic>?> _future = _load();
  Map<String, dynamic>? _patched;

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    final doc = await FirestoreRest.getDocument(
        'app_exam_answers/${widget.id}',
        idToken: token);
    if (doc != null) _resolveNamesInBackground(doc);
    return doc;
  }

  /// Older submissions never saved the course/subcourse/section names
  /// (the set doc they were copied from only carries IDs) — resolve the
  /// blanks from the parent exam set and patch them into the visible doc
  /// so the header, pending card and info card show real names.
  /// Best-effort, display only; the page is already on screen.
  Future<void> _resolveNamesInBackground(Map<String, dynamic> doc) async {
    try {
      final names = await resolveAnswerDisplayNames(doc,
          nepali: AppLanguage.isNepali);
      if (!mounted) return;
      var changed = false;
      final merged = Map<String, dynamic>.from(doc);
      void fill(String key, String value) {
        if ((merged[key] ?? '').toString().trim().isEmpty &&
            value.isNotEmpty) {
          merged[key] = value;
          changed = true;
        }
      }

      fill('courseName', names.courseName);
      fill('subcourseName', names.subcourseName);
      fill('sectionName', names.sectionName);
      if (changed) setState(() => _patched = merged);
    } catch (_) {
      // Best-effort: stored names (or blanks) stand.
    }
  }

  /// The edit section stays visible (button + countdown) for pending answers
  /// with a valid upload timestamp; the button itself goes unclickable once
  /// the 1-hour window expires.
  bool _editSectionVisible(Map<String, dynamic> a) {
    if (a['status']?.toString() != 'pending') return false;
    return DateTime.tryParse(a['createdAt']?.toString() ?? '') != null;
  }

  /// "Download Checked PDF": real byte-counted download into the phone's
  /// Downloads folder (no share sheet). Progress shows in an AppModalShell
  /// popup; on completion the popup closes and a toast confirms. Empty URL
  /// keeps the graceful "no file attached" popup.
  void _downloadCheckedPdf(String url, String examSetTitle) {
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
        fileName: checkedAnswerFileName(examSetTitle),
        // onDone kept for the legacy path; onSaved reports WHERE the file
        // landed (v1.0.120): the toast may only claim "Downloads" when
        // the MediaStore save into the real public folder succeeded —
        // the private-dir fallback gets a neutral message.
        onDone: () => _onCheckedPdfSaved(ctx, outer, toDownloads: true),
        onSaved: (toDownloads) =>
            _onCheckedPdfSaved(ctx, outer, toDownloads: toDownloads),
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  void _onCheckedPdfSaved(BuildContext dialogCtx, BuildContext outer,
      {required bool toDownloads}) {
    Navigator.of(dialogCtx).pop();
    if (!mounted) return;
    showToast(
        outer,
        toDownloads
            ? AppLanguage.tr(
                'PDF saved to Downloads', 'PDF डाउनलोड्समा सेभ भयो')
            : AppLanguage.tr('PDF saved', 'PDF सेभ भयो'),
        ToastVariant.success);
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

  /// "View Checked PDF": the teacher's checked copy in the same in-app pdfx
  /// viewer as the submitted PDF.
  void _viewCheckedPdf(String url, String examTitle) {
    if (url.isEmpty) {
      _showPdfDialog(
          AppLanguage.tr('Checked PDF', 'जाँचिएको PDF'), '');
      return;
    }
    final title = examTitle.isNotEmpty
        ? examTitle
        : AppLanguage.tr('Checked PDF', 'जाँचिएको PDF');
    context.push(Uri(
      path:
          '/pdf/${Uri.encodeComponent('exam-answer-checked-${widget.id}')}',
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

  /// Back (the header button and system back share this): pop when a
  /// real stack exists below; when this page IS the whole stack (a
  /// landing that built no stack underneath), fall back to the flow's
  /// parent — My Submissions over the tabs shell — instead of letting
  /// the system close the app silently. That is the same stack the
  /// splash builds for notification taps (details -> list -> home) and
  /// the rule behind the checkout completion fix (checkout_screen.dart):
  /// a flow page is never left as the root route.
  void _handleBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
      context.push('/exam-answer/my-submissions');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    // Routes below this page can never change while it is mounted, so
    // this stays stable for the page's lifetime: the back veto is armed
    // ONLY when the page is the root; with a real stack below, back
    // behaves exactly as before.
    final isRoot = !context.canPop();
    return PopScope(
      canPop: !isRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isRoot) _handleBack();
      },
      child: Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('My Answer Sheet', 'मेरो उत्तरपुस्तिका'),
              onBackPress: _handleBack),
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
                final a = _patched ?? snap.data;
                if (a == null) {
                  return Center(
                      child: Text(
                          AppLanguage.tr(
                              'Answer not found.', 'उत्तर भेटिएन।'),
                          style: TextStyle(color: pal.textSecondary)));
                }
                final reviewed = a['status']?.toString() == 'reviewed';
                // Rejected at the grading desk: reviewed, but the admin
                // saved a rejection reason instead of a result (passed
                // stays null). The page shows a Reason card, never the
                // Passed/Not Passed result card.
                final rejected = reviewed &&
                    (a['rejectionReason']?.toString().trim().isNotEmpty ??
                        false);
                final checkedUrl =
                    a['checkedPdfUrl']?.toString() ?? '';
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
                            delayMs: 0,
                            child: rejected
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _rejectedCrown(a),
                                      const SizedBox(height: 16),
                                      _reasonCard(pal, a),
                                    ],
                                  )
                                : _resultCard(a)),
                        const SizedBox(height: 16),
                        if ((a['reviewNote']?.toString() ?? '').isNotEmpty) ...[
                          SyllabusEntrance(
                              delayMs: 80,
                              child: _noteCard(pal, a,
                                  tone: rejected
                                      ? pal.primary
                                      : (a['passed'] == true
                                          ? pal.success
                                          : pal.danger))),
                          const SizedBox(height: 16),
                        ],
                        if (checkedUrl.isNotEmpty) ...[
                          SyllabusEntrance(
                              delayMs: 140,
                              child: _checkedPdfRow(pal, a)),
                          const SizedBox(height: 8),
                        ],
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
                            child: _pendingCrown(pal, a)),
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
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: pal.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14)),
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
                          // Self-ticking (F6): the countdown rebuilds
                          // ONLY this section every second, not the page.
                          _EditCountdownSection(
                            answer: a,
                            pal: pal,
                            onEdit: () => context.push(
                                '/exam-answer/upload?editId=${widget.id}'),
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
    ),
    );
  }

  /// Premium status timeline: Submitted -> Under Review -> Result.
  /// Shows exactly where this answer stands, with timestamps.
  Widget _statusTimeline(ExpoPalette pal, Map<String, dynamic> a) {
    final reviewed = a['status']?.toString() == 'reviewed';
    final passed = a['passed'] == true;
    final rejected = reviewed &&
        (a['rejectionReason']?.toString().trim().isNotEmpty ?? false);
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
            : rejected
                // Rejected answers carry no score — date only.
                ? (fmt(a['reviewedAt']).isNotEmpty
                    ? fmt(a['reviewedAt'])
                    : AppLanguage.tr(
                        'Checked by our team.', 'हाम्रो टोलीले जाँच्यो।'))
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

  /// Rejected outcome — a "Reason" label over a premium section card whose
  /// title is the admin's rejection reason and whose body is the admin's
  /// message to the student (the reason itself when no message was saved).
  /// Replaces the result card entirely: a rejected answer has no score.
  Widget _reasonCard(ExpoPalette pal, Map<String, dynamic> a) {
    final reason = (a['rejectionReason']?.toString() ?? '').trim();
    final message = (a['adminMessage']?.toString() ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLanguage.tr('Reason', 'कारण'),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: pal.textPrimary)),
        const SizedBox(height: 8),
        RequestSectionCard(
          icon: Icons.report_problem_outlined,
          tone: pal.danger,
          title: reason,
          child: Text(message.isNotEmpty ? message : reason,
              style: TextStyle(
                  fontSize: 13, color: pal.textPrimary, height: 1.55)),
        ),
      ],
    );
  }

  /// Checked-PDF actions: a full-width filled "View Checked PDF" button plus
  /// a square download tile beside it (the byte-counted Downloads flow).
  /// Rendered only when the teacher actually attached a checked PDF.
  Widget _checkedPdfRow(ExpoPalette pal, Map<String, dynamic> a) {
    final url = a['checkedPdfUrl']?.toString() ?? '';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: pal.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.visibility),
              label: Text(AppLanguage.tr(
                  'View Checked PDF', 'जाँचिएको PDF हेर्नुहोस्')),
              onPressed: () => _viewCheckedPdf(
                  url, a['examSetTitle']?.toString() ?? ''),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Material(
              color: pal.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _downloadCheckedPdf(
                    url, a['examSetTitle']?.toString() ?? ''),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: pal.primary.withValues(alpha: 0.35),
                        width: 0.75),
                  ),
                  child: Icon(Icons.download_rounded,
                      size: 22, color: pal.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Teacher's note — premium section card (shared RequestSectionCard, like
  /// the subscription detail page): icon tile tinted with the outcome tone
  /// (pass green / fail red / rejected primary) and the note as body text.
  Widget _noteCard(ExpoPalette pal, Map<String, dynamic> a,
      {required Color tone}) {
    return RequestSectionCard(
      icon: Icons.chat_bubble_outline,
      tone: tone,
      title: AppLanguage.tr("Teacher's Note", 'शिक्षकको टिप्पणी'),
      child: Text(a['reviewNote'].toString(),
          style: TextStyle(
              fontSize: 13, color: pal.textPrimary, height: 1.55)),
    );
  }

  /// Rejected outcome crown (v1.0.120) — the same gradient hero the
  /// published result card gives Passed/Not Passed, so a rejection reads
  /// as a first-class outcome too: red gradient (the failed card's own
  /// red.shade700 → red.shade400 family — chosen over the shared
  /// request-crown hexes so it matches _resultCard exactly), warning
  /// tile, big "Rejected" word and the admin's reason as the subtitle.
  /// The Reason label + card below it carries the full message.
  Widget _rejectedCrown(Map<String, dynamic> a) {
    final reason = (a['rejectionReason']?.toString() ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Colors.red.shade700,
          Colors.red.shade400,
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
            child: const Icon(
              Icons.report_problem_outlined,
              size: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(AppLanguage.tr('Rejected', 'अस्वीकृत'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  /// Pending state crown (v1.0.120) — replaces the old flat section
  /// card with the same gradient-hero family as the result card: the
  /// shared request-crown 'pending' amber (0xFFB45309 → 0xFFD97706),
  /// hourglass tile, big "Pending Review" word, and the exam/course
  /// line as the subtitle. The breathing timeline above it is separate
  /// and unchanged.
  Widget _pendingCrown(ExpoPalette pal, Map<String, dynamic> a) {
    final title = ((a['examSetTitle'] ?? '').toString().isNotEmpty)
        ? a['examSetTitle'].toString()
        : '';
    final courseLine = [
      (a['courseName'] ?? '').toString(),
      (a['subcourseName'] ?? '').toString()
    ].where((s) => s.isNotEmpty).join(' · ');
    final subtitle = [title, courseLine]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFB45309), Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
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
            child: const Icon(
              Icons.hourglass_top_outlined,
              size: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(AppLanguage.tr('Pending Review', 'समीक्षा बाँकी'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  /// Submission info — Payment Summary pattern (subscription detail page):
  /// a RequestSectionCard of RequestInfoRows (icon + bold fixed-width label
  /// + regular-weight value, hairline dividers).
  Widget _metaCard(ExpoPalette pal, Map<String, dynamic> a) {
    final status = (a['status']?.toString() ?? '').trim();
    final statusLabel = status.isEmpty
        ? '—'
        : '${status[0].toUpperCase()}${status.substring(1)}';
    final hasMessage = (a['message']?.toString() ?? '').trim().isNotEmpty;
    return RequestSectionCard(
      icon: Icons.fact_check_outlined,
      tone: pal.primary,
      title: AppLanguage.tr('Submission Info', 'पेश गरिएको जानकारी'),
      child: Column(
        children: [
          RequestInfoRow(
            icon: Icons.person_outline,
            label: AppLanguage.tr('Student', 'विद्यार्थी'),
            value: Text((a['studentName']?.toString() ?? '').isNotEmpty
                ? a['studentName'].toString()
                : '—'),
          ),
          RequestInfoRow(
            icon: Icons.info_outline,
            label: AppLanguage.tr('Status', 'स्थिति'),
            value: Text(statusLabel),
          ),
          RequestInfoRow(
            icon: Icons.calendar_today_outlined,
            label: AppLanguage.tr('Submitted', 'पेश गरिएको'),
            value: Text(_fmtDate(a['createdAt'])),
            last: !hasMessage,
          ),
          if (hasMessage)
            RequestInfoRow(
              icon: Icons.chat_bubble_outline,
              label: AppLanguage.tr('Message', 'सन्देश'),
              stacked: true,
              last: true,
              value: Text(a['message'].toString()),
            ),
        ],
      ),
    );
  }

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

/// The pending state's edit affordance: button + caption. Owns its own
/// 1-second ticker so ONLY this section rebuilds as the countdown runs
/// (v1.0.120 F6 — the page used to setState wholesale every second).
///
/// One-edit rule (v1.0.120): the button is live only while time remains
/// AND the one allowed edit has not been used (`editUsedAt` stamp). A
/// spent edit shows the same greyed button as an expired window, with
/// the "already used" caption — regardless of any time left.
class _EditCountdownSection extends StatefulWidget {
  final Map<String, dynamic> answer;
  final ExpoPalette pal;
  final VoidCallback onEdit;

  const _EditCountdownSection({
    required this.answer,
    required this.pal,
    required this.onEdit,
  });

  @override
  State<_EditCountdownSection> createState() =>
      _EditCountdownSectionState();
}

class _EditCountdownSectionState extends State<_EditCountdownSection> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final a = widget.answer;
    final remaining = _editRemainingFor(a);
    final used = _editUsedFor(a);
    final active = remaining > Duration.zero && !used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SyllabusEntrance(
          delayMs: 200,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: active
                    ? AppColors.accent
                    : pal.textSecondary.withValues(alpha: 0.25),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.edit),
            label: Text(active
                ? AppLanguage.tr(
                    'Edit / Re-upload Answer · ${_editCountdownTextFor(remaining)}',
                    'उत्तर सम्पादन / पुनः अपलोड · ${_editCountdownTextFor(remaining)}')
                : AppLanguage.tr(
                    'Edit / Re-upload Answer',
                    'उत्तर सम्पादन / पुनः अपलोड')),
            onPressed: active ? widget.onEdit : null,
          ),
        ),
        SyllabusEntrance(
          delayMs: 260,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              used
                  ? AppLanguage.tr(
                      'You have already used your one edit for this submission.',
                      'तपाईंले यस उत्तरको एक पटकको सम्पादन प्रयोग गरिसक्नुभयो।')
                  : active
                      ? AppLanguage.tr(
                          'You can edit your submission for the next ${_editCountdownTextFor(remaining)}. You can edit only once.',
                          'तपाईंले अर्को ${_editCountdownTextFor(remaining)} सम्म आफ्नो उत्तर सम्पादन गर्न सक्नुहुन्छ। सम्पादन एक पटक मात्र गर्न सकिन्छ।')
                      : AppLanguage.tr(
                          'The 1-hour edit window has expired.',
                          '१ घण्टाको सम्पादन समय सकिएको छ।'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textSecondary, fontSize: 13),
            ),
          ),
        ),
      ],
    );
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
/// breathes continuously (see [_PulsingDot]).
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
    if (active) return _PulsingDot(tone: data.tone, icon: data.icon);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: data.tone.withValues(
            alpha: data.state == _StepState.locked ? 0.10 : 0.16),
        border: Border.all(
            color: data.tone.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Icon(data.icon, size: 17, color: data.tone),
    );
  }
}

/// The timeline's live-step dot: a continuously breathing glow — the halo
/// (shadow blur/spread/alpha) and a gentle 1.0↔1.12 scale pulse on a
/// ~1.4s repeat-reverse loop, so a pending answer always reads as "in
/// progress" instead of settling static after one pulse.
class _PulsingDot extends StatefulWidget {
  final Color tone;
  final IconData icon;

  const _PulsingDot({required this.tone, required this.icon});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Transform.scale(
          scale: 1 + 0.12 * t,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.16),
              border: Border.all(
                  color: tone.withValues(alpha: 0.45), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: tone.withValues(alpha: 0.35 + 0.25 * t),
                  blurRadius: 10 + 8 * t,
                  spreadRadius: 0.5 + 1.5 * t,
                ),
              ],
            ),
            child: Icon(widget.icon, size: 17, color: tone),
          ),
        );
      },
    );
  }
}
