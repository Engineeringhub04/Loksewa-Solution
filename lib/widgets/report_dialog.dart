// ReportDialog — "report a question" dialog built on AppModalShell.
// Orange theme, compact iPhone-minimal. Contents:
// (1) fixed compact faded preview of the reported question — question
//     start only (~90 chars), first option only (~60 chars), then a
//     grey "......" line, so the card uses the same small space no
//     matter how long the question is
// (2) single-select issue-type chips
// (3) Details Message field (100-char cap, no counter shown)
// (4) Cancel + Submit.
//
// Submit pops the dialog (fade-out), then sends via ReportService's
// existing Google Form → Discord pipeline (destination unchanged) — which
// also best-effort writes the report history copy. Never throws to the UI.
//
// NOTE: no emojis anywhere; every Text carries an explicit
// `decoration: TextDecoration.none` guard.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';

class ReportDialog {
  static const _orange = Color(0xFFDE6E00);
  static const _orangeDark = Color(0xFFB45300);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);

  static const _issues = <String>[
    'Wrong answer',
    'Wrong question',
    'Typo',
    'Duplicate',
    'Unclear',
    'Other',
  ];

  static const _maxDetails = 100;

  /// Other streams call this exact signature.
  static Future<void> show({
    required BuildContext context,
    required String question,
    required List<String> options,
    String? questionId,
    String? subject,
    String? chapter,
    String? unit,
    required String mode,
  }) {
    return AppModalShell.show<void>(
      context: context,
      builder: (pageContext) => _ReportDialogBody(
        rootContext: context,
        question: question,
        options: options,
        questionId: questionId,
        subject: subject,
        chapter: chapter,
        unit: unit,
        mode: mode,
      ),
    );
  }
}

class _ReportDialogBody extends StatefulWidget {
  final BuildContext rootContext;
  final String question;
  final List<String> options;
  final String? questionId;
  final String? subject;
  final String? chapter;
  final String? unit;
  final String mode;

  const _ReportDialogBody({
    required this.rootContext,
    required this.question,
    required this.options,
    this.questionId,
    this.subject,
    this.chapter,
    this.unit,
    required this.mode,
  });

  @override
  State<_ReportDialogBody> createState() => _ReportDialogBodyState();
}

class _ReportDialogBodyState extends State<_ReportDialogBody> {
  String? _issue;
  final _detailsController = TextEditingController();
  bool _sending = false;

  /// Drives the shell's scroll-hint (bottom fade + bouncing chevron) —
  /// the shell hides the hint once this reports scrolled-to-bottom.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _detailsController.addListener(_enforceDetailsLimit);
  }

  @override
  void dispose() {
    _detailsController.removeListener(_enforceDetailsLimit);
    _detailsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 100-char cap with no visible counter: truncate + warn toast only when
  /// the user actually exceeds the limit.
  void _enforceDetailsLimit() {
    final text = _detailsController.text;
    if (text.length > ReportDialog._maxDetails) {
      _detailsController.value = _detailsController.value.copyWith(
        text: text.substring(0, ReportDialog._maxDetails),
        selection:
            const TextSelection.collapsed(offset: ReportDialog._maxDetails),
        composing: TextRange.empty,
      );
      showToast(widget.rootContext,
          'Details message is limited to 100 characters.', ToastVariant.warning);
    }
  }

  /// Fixed compact preview: at most [maxChars] characters, then "......".
  String _preview(String text, int maxChars) {
    final t = text.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars)}......';
  }

  String _buildDescription(String details) {
    final buffer = StringBuffer()
      ..writeln('Question report')
      ..writeln('Mode: ${widget.mode}')
      ..writeln('Issue: $_issue')
      ..writeln()
      ..writeln('Question: ${widget.question}');
    if (widget.options.isNotEmpty) {
      buffer.writeln('Options:');
      for (var i = 0; i < widget.options.length; i++) {
        buffer.writeln('${String.fromCharCode(65 + i)}. ${widget.options[i]}');
      }
    }
    if (details.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Details: $details');
    }
    final refs = <String>[
      if (widget.questionId != null && widget.questionId!.isNotEmpty)
        'questionId=${widget.questionId}',
      if (widget.subject != null && widget.subject!.isNotEmpty)
        'subject=${widget.subject}',
      if (widget.chapter != null && widget.chapter!.isNotEmpty)
        'chapter=${widget.chapter}',
      if (widget.unit != null && widget.unit!.isNotEmpty)
        'unit=${widget.unit}',
    ];
    if (refs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Ref: ${refs.join(' · ')}');
    }
    return buffer.toString();
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_issue == null) {
      showToast(widget.rootContext,
          'Please select an issue type.', ToastVariant.warning);
      return;
    }
    final details = _detailsController.text.trim();
    final issue = _issue!;
    final description = _buildDescription(details);
    // Loading on the Submit button; the popup stays until the send
    // finishes — then it dismisses with a toast (standing popup-action
    // pattern). A failed send keeps the dialog open with an error toast.
    setState(() => _sending = true);
    try {
      await ReportService.submitProblemReport(
        category: 'question-report / $issue',
        description: description,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(widget.rootContext,
          'Report sent. Thank you for helping us improve.', ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast(widget.rootContext,
          'Could not send the report. Please try again.', ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      // Same card as the Daily Limit popup (maxWidth 340, radius 30, and
      // the same total height — measured 560 = header 201 + content 359).
      // The taller report content (preview, chips, details, buttons)
      // scrolls below the fixed header (icon + REPORT tag + title), with
      // a scroll hint (bottom fade + bouncing chevron) until the user
      // reaches the bottom.
      maxWidth: 340,
      borderRadius: 30,
      contentMaxHeight: 359,
      scrollHint: true,
      scrollController: _scrollController,
      tagLabel: 'REPORT',
      onClose: () => Navigator.of(context).pop(),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: ReportDialog._orange,
          boxShadow: [
            BoxShadow(
              color: ReportDialog._orange.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child:
            const Icon(Icons.flag_rounded, size: 28, color: Colors.white),
      ),
      title: const Text(
        'Report a problem',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: ReportDialog._navy,
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // (1) Fixed compact faded preview — question start + first
          //     option + grey "......" line; same small space always.
          Opacity(
            opacity: 0.85,
            child: Transform.scale(
              scale: 0.98,
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ReportDialog._border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _preview(widget.question, 90),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: ReportDialog._navy,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (widget.options.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'A. ${_preview(widget.options.first, 60)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: ReportDialog._grey,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      '......',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: ReportDialog._grey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // (2) Issue-type single-select chips.
          const Text(
            'ISSUE TYPE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: ReportDialog._grey,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final issue in ReportDialog._issues)
                GestureDetector(
                  onTap: () => setState(() => _issue = issue),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _issue == issue
                          ? ReportDialog._orange
                          : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _issue == issue
                            ? ReportDialog._orange
                            : ReportDialog._border,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      issue,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _issue == issue
                            ? Colors.white
                            : ReportDialog._navy,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // (3) Details message — no character counter shown.
          const Text(
            'DETAILS MESSAGE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: ReportDialog._grey,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsController,
            minLines: 3,
            maxLines: 4,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ReportDialog._navy,
              decoration: TextDecoration.none,
            ),
            decoration: InputDecoration(
              hintText: 'Describe the problem (optional)',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF94A3B8),
                decoration: TextDecoration.none,
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: ReportDialog._border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: ReportDialog._border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: ReportDialog._orange, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      // (4) Cancel + Submit.
      footer: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: ReportDialog._border, width: 1.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Text(
                    'Cancel',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: ReportDialog._navy,
                        decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _sending ? null : _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [
                        ReportDialog._orange,
                        ReportDialog._orangeDark
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ReportDialog._orange
                            .withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _sending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                        )
                      : const Text(
                          'Submit',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              decoration: TextDecoration.none),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
