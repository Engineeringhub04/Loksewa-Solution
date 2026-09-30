// AppModalShell — reusable premium modal card extracted from LimitDialogCard.
// White card in BOTH light and dark mode (the design is inherently light):
// accent gradient header fading down to white, centered icon tile, white
// tagline pill, plain X close, rounded card, centered with a max width.
// Presentation via [AppModalShell.show] — fade + scale transitions:
// open = fade-in, close/pop = fade-out automatically.
//
// NOTE: every Text this shell renders carries an explicit
// `decoration: TextDecoration.none` as a defensive guard.
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
  });

  /// Shows [builder]'s card as a modal: fade + scale in (220ms, easeOutCubic),
  /// fade + scale out on pop (180ms, easeIn). Barrier tap dismisses.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (pageContext, _, __) {
        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            padding: MediaQuery.of(pageContext).viewInsets,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: builder(pageContext),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn,
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
                  child: Stack(
                    children: [
                      // Subtle decorative white circles on the accent part.
                      Positioned(
                        top: -56,
                        right: -44,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -30,
                        left: -52,
                        child: Container(
                          width: 104,
                          height: 104,
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
            ),
          ),
        ),
      ),
    );
  }
}
