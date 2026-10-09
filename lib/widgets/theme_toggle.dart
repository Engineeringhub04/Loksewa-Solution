import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated theme toggle — mirrors misc/ThemeToggleButton.tsx from the Expo
/// app: shows an icon and toggles with a full 360° spin + fade + scale
/// flourish (650ms). A full turn, not 180 — the moon glyph is not vertically
/// symmetric, so resting at 180° left it visibly upside-down.
///
/// Use this at EVERY theme-toggle location app-wide so the animation is
/// consistent (profile header, subpage headers, home header, notifications).
class ThemeToggle extends StatefulWidget {
  final double size;
  final bool isDark;
  final VoidCallback onToggle;

  /// Border radius override. Defaults to `size * 0.32` (the profile style).
  final double? borderRadius;

  /// When true (default) shows the icon for the CURRENT mode
  /// (sun in light, moon in dark). When false, shows the icon for the
  /// TARGET mode (moon in light, sun in dark) — preserves the legacy
  /// subpage/home/notifications look.
  final bool showCurrentMode;

  const ThemeToggle({
    super.key,
    required this.size,
    required this.isDark,
    required this.onToggle,
    this.borderRadius,
    this.showCurrentMode = true,
  });

  @override
  State<ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<ThemeToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _wasDark = false;

  @override
  void initState() {
    super.initState();
    _wasDark = widget.isDark;
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void didUpdateWidget(covariant ThemeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Don't animate on mount — only on an actual toggle.
    if (widget.isDark != _wasDark) {
      _wasDark = widget.isDark;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  IconData get _icon {
    if (widget.showCurrentMode) {
      return widget.isDark
          ? Icons.dark_mode_outlined
          : Icons.light_mode_outlined;
    }
    return widget.isDark
        ? Icons.light_mode_outlined
        : Icons.dark_mode_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? widget.size * 0.32;
    return Material(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final opacity = t < 0.38
                    ? 1 - (0.65 * t / 0.38)
                    : 0.35 + (0.65 * (t - 0.38) / 0.62);
                final scale = t < 0.38
                    ? 1 - (0.3 * t / 0.38)
                    : 0.7 + (0.3 * (t - 0.38) / 0.62);
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Transform.rotate(
                      angle: t * 2 * math.pi,
                      child: Icon(
                        _icon,
                        size: widget.size * 0.52,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
