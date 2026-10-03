// DiscussionReportDialog — AppModalShell-based report modal for discussion
// posts/comments, mirroring ReportDialog's structure: single-select type
// chips (DiscussionReportType via discussionReportTypeLabel), a details
// field (100-char cap, no counter), Cancel + Submit.
//
// Submit flow: spinner ON the Submit button → DiscussionService.reportContent
// (reason "<TypeLabel>: <details>", type label in the current language) →
// success closes the modal and returns true; failure keeps the dialog open
// with an inline error and the spinner off. Never throws to the caller.
//
// [submitForTest] overrides the real service call in widget tests (static
// methods can't be stubbed).
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../services/discussion_service.dart';
import '../app_modal_shell.dart';

class DiscussionReportDialog {
  static const _orange = Color(0xFFDE6E00);
  static const _orangeDark = Color(0xFFB45300);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _maxDetails = 100;

  /// Returns true when the report was sent. Never throws.
  static Future<bool> show({
    required BuildContext context,
    required String targetType, // 'post' | 'comment'
    required String targetId,
    String? targetTitle,
    Future<void> Function(String type, String id, String reason)?
        submitForTest,
  }) {
    return AppModalShell.show<bool>(
      context: context,
      builder: (pageContext) => _DiscussionReportDialogBody(
        targetType: targetType,
        targetId: targetId,
        targetTitle: targetTitle,
        submitForTest: submitForTest,
      ),
    ).then((value) => value ?? false);
  }
}

class _DiscussionReportDialogBody extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String? targetTitle;
  final Future<void> Function(String type, String id, String reason)?
      submitForTest;

  const _DiscussionReportDialogBody({
    required this.targetType,
    required this.targetId,
    this.targetTitle,
    this.submitForTest,
  });

  @override
  State<_DiscussionReportDialogBody> createState() =>
      _DiscussionReportDialogBodyState();
}

class _DiscussionReportDialogBodyState
    extends State<_DiscussionReportDialogBody> {
  DiscussionReportType? _type;
  final _detailsController = TextEditingController();
  bool _sending = false;
  String? _error;
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

  /// 100-char cap with no visible counter: silently truncate.
  void _enforceDetailsLimit() {
    final text = _detailsController.text;
    if (text.length > DiscussionReportDialog._maxDetails) {
      _detailsController.value = _detailsController.value.copyWith(
        text: text.substring(0, DiscussionReportDialog._maxDetails),
        selection: const TextSelection.collapsed(
            offset: DiscussionReportDialog._maxDetails),
        composing: TextRange.empty,
      );
    }
  }

  String get _lang => AppLanguage.current.value;

  Future<void> _submit() async {
    if (_sending) return;
    if (_type == null) {
      setState(() => _error = AppLanguage.tr(
          'Please select a report type.', 'कृपया रिपोर्टको प्रकार छान्नुहोस्।'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final details = _detailsController.text.trim();
    final typeLabel = discussionReportTypeLabel(_type!, _lang);
    final reason = details.isEmpty ? typeLabel : '$typeLabel: $details';
    try {
      final submit = widget.submitForTest ??
          (String t, String id, String r) => DiscussionService.reportContent(
                t,
                id,
                r,
                title: widget.targetTitle,
              );
      await submit(widget.targetType, widget.targetId, reason);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = AppLanguage.tr('Something went wrong',
            'केही समस्या भयो');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetTitle = (widget.targetTitle ?? '').trim();
    return AppModalShell(
      maxWidth: 340,
      borderRadius: 30,
      contentMaxHeight: 359,
      scrollHint: true,
      scrollController: _scrollController,
      accent: DiscussionReportDialog._orange,
      accentMid: const Color(0xFFF59E0B),
      accentLight: const Color(0xFFFCD9A8),
      tagColor: DiscussionReportDialog._orange,
      tagLabel: AppLanguage.tr('REPORT', 'रिपोर्ट'),
      onClose: () => Navigator.of(context).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: DiscussionReportDialog._orange,
          boxShadow: [
            BoxShadow(
              color: DiscussionReportDialog._orange.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(Icons.flag_rounded, size: 28, color: Colors.white),
      ),
      title: Text(
        AppLanguage.tr('Report content', 'सामग्री रिपोर्ट गर्नुहोस्'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: DiscussionReportDialog._navy,
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (targetTitle.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: DiscussionReportDialog._border),
              ),
              child: Text(
                targetTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: DiscussionReportDialog._navy,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            AppLanguage.tr('Report type', 'रिपोर्टको प्रकार'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: DiscussionReportDialog._grey,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in DiscussionReportType.values)
                GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _type == t
                          ? DiscussionReportDialog._orange
                          : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _type == t
                            ? DiscussionReportDialog._orange
                            : DiscussionReportDialog._border,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      discussionReportTypeLabel(t, _lang),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _type == t
                            ? Colors.white
                            : DiscussionReportDialog._navy,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            AppLanguage.tr('Report information', 'रिपोर्ट जानकारी'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: DiscussionReportDialog._grey,
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
              color: DiscussionReportDialog._navy,
              decoration: TextDecoration.none,
            ),
            decoration: InputDecoration(
              hintText: AppLanguage.tr(
                  'Tell us what is wrong...', 'समस्या के हो बताउनुहोस्...'),
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
                borderSide: const BorderSide(
                    color: DiscussionReportDialog._border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: DiscussionReportDialog._border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: DiscussionReportDialog._orange, width: 1.5),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEF4444),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.of(context).pop(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: DiscussionReportDialog._border, width: 1.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: DiscussionReportDialog._navy,
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
                        DiscussionReportDialog._orange,
                        DiscussionReportDialog._orangeDark
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: DiscussionReportDialog._orange
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
                      : Text(
                          AppLanguage.tr('Submit report', 'रिपोर्ट पठाउनुहोस्'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
