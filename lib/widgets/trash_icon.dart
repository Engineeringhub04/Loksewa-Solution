import 'package:flutter/material.dart';

/// Modern trash outline icon — the same look as the approved delete-icon
/// mockup (Feather-style trash-2 outline). Drawn with a [CustomPainter] so
/// no extra dependency is needed and the glyph is identical on every device.
///
/// [color] defaults to the ambient [IconTheme] color, exactly like [Icon].
///
/// Replaces the old [Icons.delete_outline] everywhere it appears.
class TrashIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const TrashIcon({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Colors.white;
    return CustomPaint(
      size: Size(size, size),
      painter: _TrashPainter(color: effectiveColor, strokeWidth: strokeWidth),
    );
  }
}

class _TrashPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _TrashPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    // 24x24 viewBox, Feather trash-2 geometry.
    final s = size.width / 24.0;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Lid: M3 6 H21
    canvas.drawLine(Offset(3 * s, 6 * s), Offset(21 * s, 6 * s), p);

    // Body: M19 6 v14 a2 2 0 0 1 -2 2 H7 a2 2 0 0 1 -2 -2 V6
    final body = Path()
      ..moveTo(19 * s, 6 * s)
      ..lineTo(19 * s, 20 * s)
      ..arcToPoint(Offset(17 * s, 22 * s),
          radius: Radius.circular(2 * s), clockwise: true)
      ..lineTo(7 * s, 22 * s)
      ..arcToPoint(Offset(5 * s, 20 * s),
          radius: Radius.circular(2 * s), clockwise: true)
      ..lineTo(5 * s, 6 * s);
    canvas.drawPath(body, p);

    // Handle: M8 6 V4 a2 2 0 0 1 2 -2 H14 a2 2 0 0 1 2 2 V6
    final handle = Path()
      ..moveTo(8 * s, 6 * s)
      ..lineTo(8 * s, 4 * s)
      ..arcToPoint(Offset(10 * s, 2 * s),
          radius: Radius.circular(2 * s), clockwise: true)
      ..lineTo(14 * s, 2 * s)
      ..arcToPoint(Offset(16 * s, 4 * s),
          radius: Radius.circular(2 * s), clockwise: true)
      ..lineTo(16 * s, 6 * s);
    canvas.drawPath(handle, p);

    // Ridges: M10 11 V17, M14 11 V17
    canvas.drawLine(Offset(10 * s, 11 * s), Offset(10 * s, 17 * s), p);
    canvas.drawLine(Offset(14 * s, 11 * s), Offset(14 * s, 17 * s), p);
  }

  @override
  bool shouldRepaint(covariant _TrashPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
