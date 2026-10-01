// AppModalShell — reusable premium modal card extracted from LimitDialogCard.
// White card in BOTH light and dark mode (the design is inherently light):
// accent gradient header fading down to white, centered icon tile, white
// tagline pill, plain X close, rounded card, centered with a max width.
// Presentation via [AppModalShell.show] — fade + scale transitions:
// open = fade-in, close/pop = fade-out automatically.
//
// NOTE: every Text this shell renders carries an explicit
// `decoration: TextDecoration.none` as a defensive guard.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppModalShell extends StatelessWidget {
  /// Pre-built icon tile (e.g. a rounded square container with an icon).
  final Widget icon;

  /// Pill tagline text shown above the title (e.g. "Daily Limit").
  final String tagLabel;

  /// Title widget (caller owns the text style).
  final Widget title;

  /// Body content shown on white below the header.
  final Widget body;

  /// Footer (buttons row / stacked buttons).
  final Widget footer;

  /// Called when the plain X close is tapped. Null hides the X.
  final VoidCallback? onClose;

  /// Header gradient top color (default logo orange).
  final Color accent;

  /// Header gradient upper-mid color.
  final Color accentMid;

  /// Header gradient lower-mid color.
  final Color accentLight;

  /// Tagline pill text color.
  final Color tagColor;

  /// Card max width.
  final double maxWidth;

  /// Card corner radius.
  final double borderRadius;

  /// When set, the body + footer region is capped at this height and made
  /// internally scrollable, while the gradient header (icon, tag, title)
  /// stays fixed. Null (default) keeps the size-to-content behavior —
  /// existing callers like the daily-limit popup are unaffected.
  final double? contentMaxHeight;

  /// Opt-in scroll discoverability for a capped content region: a subtle
  /// bottom fade plus a gently bouncing down-chevron on open, hinting that
  /// more content lies below. The hint fades away once the user scrolls to
  /// the bottom. Requires [contentMaxHeight] and [scrollController]; false
  /// by default so existing callers are unaffected.
  final bool scrollHint;

  /// External scroll controller for the capped content region. When
  /// [scrollHint] is true this drives the bottom-reached detection.
  final ScrollController? scrollController;

  const AppModalShell({
    super.key,
    required this.icon,
    required this.tagLabel,
    required this.title,
    required this.body,
    required this.footer,
    this.onClose,
    this.accent = const Color(0xFFDE6E00),
    this.accentMid = const Color(0xFFF59E0B),
    this.accentLight = const Color(0xFFFCD9A8),
    this.tagColor = const Color(0xFFDE6E00),
    this.maxWidth = 420,
    this.borderRadius = 28,
    this.contentMaxHeight,
    this.scrollHint = false,
    this.scrollController,
  });

  /// Shows [builder]'s card as a modal: fade + scale in (200ms) and
  /// fade + scale out on pop (200ms) — same duration and same curve in
  /// both directions so open/close feel identical. Barrier tap dismisses.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (pageContext, _, __) {
        // showGeneralDialog (unlike showDialog) puts no Material above the
        // page, so raw InkWells inside modal content would throw "No Material
        // widget found". The transparency material keeps every popup's ink
        // effects working without changing any visuals.
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              padding: MediaQuery.of(pageContext).viewInsets,
              child: Center(
                // Matches the inline padding the daily-limit popup uses, so
                // cards presented via show() render at the same width.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: builder(pageContext),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        // One shared curve for both directions: the open fade-in and the
        // pop fade-out run the identical 200ms easing (this SDK's
        // showGeneralDialog has no reverseTransitionDuration, so both use
        // transitionDuration).
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Body + footer as one unit. When [contentMaxHeight] is set, this
    // region is capped and scrolls internally while the gradient header
    // (icon, tag, title) stays fixed — e.g. the report dialog, whose
    // content is taller than the daily-limit-sized card.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Body on white.
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: body,
        ),
        // Footer on white.
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: footer,
        ),
      ],
    );
    final Widget contentWidget;
    if (contentMaxHeight != null &&
        scrollHint &&
        scrollController != null) {
      contentWidget = _HintedScroll(
        maxHeight: contentMaxHeight!,
        controller: scrollController!,
        child: content,
      );
    } else if (contentMaxHeight != null) {
      contentWidget = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: contentMaxHeight!),
        child: SingleChildScrollView(
          controller: scrollController,
          child: content,
        ),
      );
    } else {
      contentWidget = content;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gradient header — saturated accent at the very top,
                // fading down into white at the header's bottom edge.
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accentMid, accentLight, Colors.white],
                      stops: const [0.0, 0.45, 0.75, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  // The header column is narrower than the full-width stack
                  // whenever the title is short, so the stack explicitly
                  // centers it — the default topStart alignment left-shifted
                  // short titles (the report dialog's header was ~15px off).
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // Subtle decorative white circles on the accent part
                      // (mirrored pair, so the header feels balanced).
                      Positioned(
                        top: -48,
                        right: -40,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -48,
                        left: -40,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      // Plain X close, top-right (no heavy background).
                      if (onClose != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClose,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close,
                                  size: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      // Centered column: icon tile, tagline pill, title.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 34, 28, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            icon,
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                tagLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: tagColor,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            DefaultTextStyle(
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                                height: 1.3,
                                decoration: TextDecoration.none,
                              ),
                              textAlign: TextAlign.center,
                              child: title,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Scrollable (or sized) body + footer below the fixed header.
                contentWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Capped scroll region with scroll-discoverability hints: a subtle bottom
/// fade plus a down-chevron that bounces gently a few times on open,
/// telling the user more content lies below. Both fade away once the user
/// scrolls to the bottom (or immediately, when nothing overflows).
///
/// The bounce is FINITE — one 1.5s tween that settles at rest — so widget
/// tests using pumpAndSettle are unaffected. The overlays are
/// pointer-transparent and sit in the footer's bottom padding, so they
/// never cover buttons.
class _HintedScroll extends StatefulWidget {
  final double maxHeight;
  final ScrollController controller;
  final Widget child;

  const _HintedScroll({
    required this.maxHeight,
    required this.controller,
    required this.child,
  });

  @override
  State<_HintedScroll> createState() => _HintedScrollState();
}

class _HintedScrollState extends State<_HintedScroll> {
  static const _orange = Color(0xFFDE6E00);
  bool _atBottom = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients || !mounted) return;
    final pos = widget.controller.position;
    final atBottom = pos.maxScrollExtent <= 0 ||
        pos.pixels >= pos.maxScrollExtent - 4;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: widget.controller,
            child: widget.child,
          ),
          // Bottom fade — the classic "content continues" cue.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _atBottom ? 0 : 1,
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Down chevron — 3 gentle decaying bounces on open, then rests.
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _atBottom ? 0 : 1,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1500),
                    builder: (context, t, child) {
                      // Decaying sine: 3 bounces that shrink to rest.
                      // At t=1 the offset is exactly 0 — the tween runs
                      // once and stops (no repeat, no loop).
                      final dy = math.sin(t * 3 * math.pi) * 5 * (1 - t);
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _orange.withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: _orange,
                      ),
                    ),
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
