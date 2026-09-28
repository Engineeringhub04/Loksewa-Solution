import 'package:flutter/material.dart';

/// Multi-color Google "G" drawn with a CustomPainter — mirrors GoogleIcon.tsx
/// (official brand colors: blue #4285F4, green #34A853, yellow #FBBC05,
/// red #EA4335).
class GoogleIcon extends StatelessWidget {
  final double size;

  const GoogleIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final strokeW = size.width * 0.19;
    final radius = size.width / 2 - strokeW / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.butt;

    // Angles in radians: 0 = east, positive = clockwise.
    // Four ~100-degree arcs tile the ring; the blue bar finishes the G.
    paint.color = const Color(0xFFEA4335); // red — left
    canvas.drawArc(rect, 2.25, 1.75, false, paint);
    paint.color = const Color(0xFFFBBC05); // yellow — top
    canvas.drawArc(rect, -2.45, 1.7, false, paint);
    paint.color = const Color(0xFF34A853); // green — bottom
    canvas.drawArc(rect, 0.72, 1.7, false, paint);
    paint.color = const Color(0xFF4285F4); // blue — right
    canvas.drawArc(rect, -0.85, 1.7, false, paint);
    canvas.drawLine(
      Offset(cx - strokeW * 0.2, cy),
      Offset(cx + radius + strokeW * 0.1, cy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
