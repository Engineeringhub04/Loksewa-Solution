import 'package:flutter/material.dart';

/// The X (Twitter) brand mark — drawn with a [CustomPainter] so no extra
/// dependency is needed and the glyph is identical on every device.
///
/// Material's [Icons.close] looks like a close button, not the X logo: the
/// real mark is a single filled stroke-form "𝕏" glyph, so it is drawn as a
/// filled path on a 24x24 viewBox (X brand geometry).
///
/// [color] defaults to the ambient [IconTheme] color, exactly like [Icon].
class XLogoIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const XLogoIcon({
    super.key,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Colors.white;
    return CustomPaint(
      size: Size(size, size),
      painter: _XLogoPainter(color: effectiveColor),
    );
  }
}

class _XLogoPainter extends CustomPainter {
  final Color color;

  _XLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // 24x24 viewBox, X brand-mark geometry.
    final s = size.width / 24.0;
    final p = Path()
      ..moveTo(18.901 * s, 1.153 * s)
      ..lineTo(22.581 * s, 1.153 * s)
      ..lineTo(14.541 * s, 10.343 * s)
      ..lineTo(24 * s, 22.846 * s)
      ..lineTo(16.594 * s, 22.846 * s)
      ..lineTo(10.794 * s, 15.262 * s)
      ..lineTo(4.156 * s, 22.846 * s)
      ..lineTo(0.474 * s, 22.846 * s)
      ..lineTo(9.074 * s, 13.016 * s)
      ..lineTo(0, 1.154 * s)
      ..lineTo(7.594 * s, 1.154 * s)
      ..lineTo(12.837 * s, 8.086 * s)
      ..close()
      ..moveTo(17.61 * s, 20.644 * s)
      ..lineTo(19.649 * s, 20.644 * s)
      ..lineTo(6.486 * s, 3.24 * s)
      ..lineTo(4.298 * s, 3.24 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_XLogoPainter old) => old.color != color;
}
