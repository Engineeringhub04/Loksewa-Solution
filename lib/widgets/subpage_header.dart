import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/theme_service.dart';

/// Shared curved blue gradient header used across sub-pages.
/// Mirrors `SubpageHeader.tsx` from the Expo app: diagonal gradient
/// #2563EB → #1D4ED8 → #0B1F5B (top-left to bottom-right), 36×36 translucent
/// back button, centered 18px bold white title, and a working theme toggle
/// on the right with an optional `actions` slot to its left.
///
/// Top inset handling: the gradient container is full-bleed (it paints behind
/// the status bar) and a SafeArea inside it adds exactly one status-bar inset
/// before the 12px content padding — the same `insets.top + 12` as React.
/// Because SafeArea zeroes the padding it consumes for its descendants, this
/// stays correct whether or not the screen also wraps its body in SafeArea
/// (no double inset either way).
///
/// Bottom corners are SQUARE (no 26px radius). React's SubpageHeader rounds
/// them, which exposes the page background in the corner cutouts; the user
/// explicitly asked for a full-blue header with no light band, so the
/// corners are filled with the header's own blue.
///
/// No entry animation here on purpose — the page transition IS the animation.
class SubpageHeader extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBackPress;
  final List<Widget>? actions;
  final bool showThemeToggle;

  const SubpageHeader({
    super.key,
    required this.title,
    this.showBack = true,
    this.onBackPress,
    this.actions,
    this.showThemeToggle = true,
  });

  static const _gradientColors = [
    Color(0xFF2563EB),
    Color(0xFF1D4ED8),
    Color(0xFF0B1F5B),
  ];

  Widget _iconBox({Widget? child}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: const BoxDecoration(
        // Solid fallback painted under the gradient so the header can never
        // render colourless. Bottom corners are intentionally square: the
        // 26px radius React uses exposes the page background in the corner
        // cutouts (read as a white band), and full-blue was explicitly
        // requested.
        color: Color(0xFF1D4ED8),
        gradient: LinearGradient(
          colors: _gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (showBack)
                  GestureDetector(
                    onTap: onBackPress ?? () => context.pop(),
                    child: _iconBox(
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  _iconBox(),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actions != null) ...actions!,
                    // The empty balancing box only applies when the screen adds
                    // no actions of its own: with custom actions (e.g. the
                    // notifications mark-all pill, which replaces the whole
                    // right slot like Expo's rightSlot) a phantom box would
                    // render visibly at the far right.
                    if (showThemeToggle)
                      GestureDetector(
                        onTap: () => ThemeService.toggle(context),
                        child: _iconBox(
                          child: Icon(
                            isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else if (actions == null)
                      _iconBox(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
