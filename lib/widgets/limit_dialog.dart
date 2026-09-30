// Practice limit / generic app dialog card — FeedSpring-style redesign.
// White card in BOTH light and dark mode (the design is inherently light):
// blue gradient header fading down to white, centered icon tile, white
// tagline pill, navy title, grey body, stacked white Cancel + blue gradient
// CTA buttons. Used by subject_practice_screen.dart (_appDialog) and
// additional_topic_screen.dart (_limitDialog).
//
// NOTE: every Text in this dialog carries an explicit
// `decoration: TextDecoration.none` as a defensive guard.
import 'package:flutter/material.dart';

class LimitDialogCard extends StatelessWidget {
  final String tagline;
  final String title;
  final String message;
  final Widget? bodyExtra;
  final IconData icon;
  final String confirmLabel;
  final IconData? confirmIcon;
  final String? cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const LimitDialogCard({
    super.key,
    required this.tagline,
    required this.title,
    required this.message,
    this.bodyExtra,
    required this.icon,
    required this.confirmLabel,
    this.confirmIcon,
    this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  static const _blue = Color(0xFF2563EB);
  static const _blueDark = Color(0xFF1D4ED8);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);
  static const _logoOrange = Color(0xFFDE6E00);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gradient header — saturated blue at the very top,
                // fading down into white at the header's bottom edge.
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF1D4ED8),
                        Color(0xFF3B82F6),
                        Color(0xFF93C5FD),
                        Colors.white,
                      ],
                      stops: [0.0, 0.45, 0.75, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Subtle decorative white circles on the blue part.
                      Positioned(
                        top: -56,
                        right: -44,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                Colors.white.withValues(alpha: 0.14),
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
                            color:
                                Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      // Plain X close, top-right (no heavy background).
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onCancel,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.close,
                                size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                      // Centered column: icon tile, tagline pill, title.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            28, 34, 28, 14),
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(18),
                                color: _blue,
                                boxShadow: [
                                  BoxShadow(
                                    color: _blue.withValues(
                                        alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(icon,
                                  size: 28, color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                tagline,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: _logoOrange,
                                  decoration:
                                      TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _navy,
                                height: 1.3,
                                decoration: TextDecoration.none,
                              ),
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
                  padding:
                      const EdgeInsets.fromLTRB(20, 6, 20, 8),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: _grey,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (bodyExtra != null) ...[
                        const SizedBox(height: 10),
                        bodyExtra!,
                      ],
                    ],
                  ),
                ),
                // Buttons — stacked full-width on white.
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      // Cancel first — white, light slate border.
                      if (cancelLabel != null) ...[
                        Material(
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(22),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(22),
                            onTap: onCancel,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color:
                                        const Color(0xFFE2E8F0),
                                    width: 1.5),
                                borderRadius:
                                    BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: 0.06),
                                    blurRadius: 8,
                                    offset:
                                        const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                cancelLabel!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: _navy,
                                    decoration:
                                        TextDecoration.none),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // Confirm second — blue gradient CTA.
                      Material(
                        color: Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(22),
                          onTap: onConfirm,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 15),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                colors: [_blue, _blueDark],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _blue.withValues(
                                      alpha: 0.4),
                                  blurRadius: 12,
                                  offset:
                                      const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    if (confirmIcon !=
                                        null) ...[
                                      Icon(confirmIcon,
                                          size: 18,
                                          color: Colors.white),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: Text(
                                        confirmLabel,
                                        textAlign:
                                            TextAlign.center,
                                        style:
                                            const TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                                color:
                                                    Colors.white,
                                                decoration:
                                                    TextDecoration
                                                        .none),
                                      ),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  right: 12,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration:
                                        const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: const Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: _blueDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
