import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mirrors `src/components/Preloading.tsx` — the app-wide loading state.
///
/// A soft breathing disc with two thin counter-rotating arcs (26% of each
/// ring drawn, round caps), sitting IN the background rather than on a card,
/// plus a semibold label and an optional dimmer hint line.
///
/// Pass `tinted: false` on theme-coloured pages (accent becomes the theme
/// primary); the default `true` uses the fixed dark leaderboard palette.
class PreloadingWidget extends StatefulWidget {
  final String label;
  final String? hint;
  final bool tinted;

  const PreloadingWidget({
    super.key,
    required this.label,
    this.hint,
    this.tinted = true,
  });

  @override
  State<PreloadingWidget> createState() => _PreloadingWidgetState();
}

class _PreloadingWidgetState extends State<PreloadingWidget>
    with TickerProviderStateMixin {
  late final AnimationController _outer;
  late final AnimationController _inner;
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    // Linear easing: the loops restart at 0 every lap, so any ease would
    // stutter once per revolution.
    _outer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1150))
      ..repeat();
    // Own clock: slower and counter-rotating.
    _inner = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1750))
      ..repeat();
    _breathe = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _outer.dispose();
    _inner.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);

    // tinted=false → theme primary + themed text on the app background.
    final Color accent = widget.tinted
        ? const Color(0xFF22C55E)
        : primary;
    final Color text = widget.tinted
        ? Colors.white
        : (isDark
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF0F172A));
    final Color textDim = widget.tinted
        ? Colors.white70
        : (isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B));
    final Color haloBg = widget.tinted
        ? Colors.white.withValues(alpha: 0.07)
        : primary.withValues(alpha: 0.06);
    final Color haloBorder = widget.tinted
        ? Colors.white.withValues(alpha: 0.16)
        : primary.withValues(alpha: 0.16);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation:
                  Listenable.merge([_outer, _inner, _breathe]),
              builder: (context, _) {
                final b = _breathe.value; // 0..1..0
                return SizedBox(
                  width: 108,
                  height: 108,
                  child: CustomPaint(
                    painter: _RingsPainter(
                      accent: accent,
                      haloBg: haloBg,
                      haloBorder: haloBorder,
                      haloOpacity: 0.5 + b * 0.5,
                      haloScale: 0.96 + b * 0.06,
                      outerTurns: _outer.value,
                      innerTurns: _inner.value,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: text),
            ),
            if (widget.hint != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.hint!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final Color accent;
  final Color haloBg;
  final Color haloBorder;
  final double haloOpacity;
  final double haloScale;
  final double outerTurns;
  final double innerTurns;

  static const _stroke = 3.5;
  static const _arcFraction = 0.26;

  const _RingsPainter({
    required this.accent,
    required this.haloBg,
    required this.haloBorder,
    required this.haloOpacity,
    required this.haloScale,
    required this.outerTurns,
    required this.innerTurns,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    // Breathing halo disc.
    canvas.drawCircle(
      c,
      54 * haloScale,
      Paint()
        ..color = haloBg.withValues(
            alpha: haloBg.a * haloOpacity / 1.0),
    );
    canvas.drawCircle(
      c,
      54 * haloScale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = haloBorder.withValues(
            alpha: haloBorder.a * haloOpacity),
    );

    void ring(double diameter, double turns, double opacity) {
      final r = (diameter - _stroke) / 2;
      final rect = Rect.fromCircle(center: c, radius: r);
      // Start at the top (-90°) like the SVG circle.
      final start = -math.pi / 2 + turns * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        2 * math.pi * _arcFraction,
        false,
        Paint()
          ..color = accent.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    ring(66, outerTurns, 1.0);
    ring(44, -innerTurns, 0.45);
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.outerTurns != outerTurns ||
      old.innerTurns != innerTurns ||
      old.haloOpacity != haloOpacity;
}
