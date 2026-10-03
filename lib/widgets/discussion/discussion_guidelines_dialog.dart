// DiscussionGuidelinesDialog — AppModalShell modal showing the community
// guidelines: title, body, bullet list. When [showSeedButton] is true
// (admin first-visit) the footer carries a "Save Guidelines" button whose
// loading → success handling is internal: spinner on the button, success
// closes the modal and returns true, failure keeps it open with an inline
// error. Never throws to the caller.
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../services/discussion_service.dart';
import '../app_modal_shell.dart';

class DiscussionGuidelinesDialog {
  static const _blue = Color(0xFF2563EB);
  static const _blueMid = Color(0xFF3B82F6);
  static const _blueLight = Color(0xFFBFDBFE);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);

  /// Returns true when guidelines were seeded (or false when the dialog
  /// was dismissed without seeding). Never throws.
  static Future<bool> show({
    required BuildContext context,
    required DiscussionGuidelines guidelines,
    bool showSeedButton = false,
    required Future<void> Function() onSeed,
  }) {
    return AppModalShell.show<bool>(
      context: context,
      builder: (pageContext) => _DiscussionGuidelinesDialogBody(
        guidelines: guidelines,
        showSeedButton: showSeedButton,
        onSeed: onSeed,
      ),
    ).then((value) => value ?? false);
  }
}

class _DiscussionGuidelinesDialogBody extends StatefulWidget {
  final DiscussionGuidelines guidelines;
  final bool showSeedButton;
  final Future<void> Function() onSeed;

  const _DiscussionGuidelinesDialogBody({
    required this.guidelines,
    required this.showSeedButton,
    required this.onSeed,
  });

  @override
  State<_DiscussionGuidelinesDialogBody> createState() =>
      _DiscussionGuidelinesDialogBodyState();
}

class _DiscussionGuidelinesDialogBodyState
    extends State<_DiscussionGuidelinesDialogBody> {
  bool _seeding = false;
  String? _error;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _seed() async {
    if (_seeding) return;
    setState(() {
      _seeding = true;
      _error = null;
    });
    try {
      await widget.onSeed();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _seeding = false;
        _error = AppLanguage.tr(
            'Something went wrong', 'केही समस्या भयो');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guidelines;
    return AppModalShell(
      maxWidth: 340,
      borderRadius: 30,
      contentMaxHeight: 359,
      scrollHint: true,
      scrollController: _scrollController,
      accent: DiscussionGuidelinesDialog._blue,
      accentMid: DiscussionGuidelinesDialog._blueMid,
      accentLight: DiscussionGuidelinesDialog._blueLight,
      tagColor: DiscussionGuidelinesDialog._blue,
      tagLabel: AppLanguage.tr('GUIDELINES', 'निर्देशिका'),
      onClose: () => Navigator.of(context).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: DiscussionGuidelinesDialog._blue,
          boxShadow: [
            BoxShadow(
              color: DiscussionGuidelinesDialog._blue.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child:
            const Icon(Icons.rule_rounded, size: 28, color: Colors.white),
      ),
      title: Text(
        g.title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: DiscussionGuidelinesDialog._navy,
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: DiscussionGuidelinesDialog._navy,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          for (final bullet in g.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: DiscussionGuidelinesDialog._blue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: DiscussionGuidelinesDialog._grey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 4),
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
      footer: widget.showSeedButton
          ? Row(
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
                              color: DiscussionGuidelinesDialog._border,
                              width: 1.5),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: DiscussionGuidelinesDialog._navy,
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
                      onTap: _seeding ? null : _seed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: const LinearGradient(
                            colors: [
                              DiscussionGuidelinesDialog._blue,
                              DiscussionGuidelinesDialog._blueMid
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: DiscussionGuidelinesDialog._blue
                                  .withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: _seeding
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                ),
                              )
                            : Text(
                                AppLanguage.tr('Save Guidelines',
                                    'नियमहरू सुरक्षित गर्नुहोस्'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    decoration: TextDecoration.none),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Material(
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
                        color: DiscussionGuidelinesDialog._border, width: 1.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    AppLanguage.tr('OK', 'ठिक छ'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: DiscussionGuidelinesDialog._navy,
                        decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
    );
  }
}
