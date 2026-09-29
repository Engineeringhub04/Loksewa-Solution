import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mirrors `src/components/Preloading.tsx` — the app-wide loading state.
///
/// iPhone-style loading indicator: a small 12-spoke activity spinner
/// (spokes fade in sequence, ~1s per revolution) with the contextual label
/// underneath in a subtle weight. The spinner is intentionally neutral grey
/// like iOS — the "premium" feel comes from its minimalism, while the label
/// keeps telling the user *what* is loading.
///
/// Pass `tinted: false` on theme-coloured pages (spokes become theme grey);
/// the default `true` uses white spokes for dark leaderboard-style surfaces.
///
/// The public API (label / hint / tinted) is unchanged, so every call site
/// keeps working as before.
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // One revolution per second, like the iOS activity indicator.
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Neutral iOS-grey spokes; white on the dark tinted surfaces.
    final Color spokeBase = widget.tinted
        ? Colors.white
        : (isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B));
    final Color textDim = widget.tinted
        ? Colors.white70
        : (isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B));

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(
                  painter:
                      _SpokesPainter(progress: _c.value, color: spokeBase),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textDim),
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

/// iOS-style activity indicator: 12 rounded spokes; the head spoke is fully
/// opaque and the trail fades behind it, rotating once per second.
class _SpokesPainter extends CustomPainter {
  final double progress; // 0..1, one revolution
  final Color color;

  static const int _spokes = 12;

  const _SpokesPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final inner = outer * 0.55;
    final head = (progress * _spokes) % _spokes;

    for (var i = 0; i < _spokes; i++) {
      // 0 = head (newest), growing older around the dial.
      final age = (head - i) % _spokes;
      final alpha = 0.18 + 0.82 * (1 - age / _spokes);
      final a = -math.pi / 2 + i * 2 * math.pi / _spokes;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * inner,
        c + dir * outer,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SpokesPainter old) =>
      old.progress != progress || old.color != color;
}
