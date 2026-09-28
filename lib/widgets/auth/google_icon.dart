import 'package:flutter/material.dart';

/// Official multi-color Google "G" logo, drawn from the same SVG paths as
/// GoogleIcon.tsx (viewBox 0 0 48 48) with the official brand colors:
/// blue #4285F4, green #34A853, yellow #FBBC05, red #EA4335.
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
    // The paths below are authored in the 48x48 SVG viewBox.
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xFFFBBC05);
    canvas.drawPath(_gYellow(), paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawPath(_gRed(), paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawPath(_gGreen(), paint);
    paint.color = const Color(0xFF4285F4);
    canvas.drawPath(_gBlue(), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Path _gYellow() {
  final p = Path();
  p.moveTo(43.611, 20.083);
  p.lineTo(42.000, 20.083);
  p.lineTo(42.000, 20.000);
  p.lineTo(24.000, 20.000);
  p.lineTo(24.000, 28.000);
  p.lineTo(35.303, 28.000);
  p.cubicTo(33.654, 32.657, 29.223, 36.000, 24.000, 36.000);
  p.cubicTo(17.373, 36.000, 12.000, 30.627, 12.000, 24.000);
  p.cubicTo(12.000, 17.373, 17.373, 12.000, 24.000, 12.000);
  p.cubicTo(27.059, 12.000, 29.842, 13.154, 31.961, 15.039);
  p.lineTo(37.618, 9.382);
  p.cubicTo(34.046, 6.053, 29.268, 4.000, 24.000, 4.000);
  p.cubicTo(12.955, 4.000, 4.000, 12.955, 4.000, 24.000);
  p.cubicTo(4.000, 35.045, 12.955, 44.000, 24.000, 44.000);
  p.cubicTo(35.045, 44.000, 44.000, 35.045, 44.000, 24.000);
  p.cubicTo(44.000, 22.659, 43.862, 21.350, 43.611, 20.083);
  p.close();
  return p;
}

Path _gRed() {
  final p = Path();
  p.moveTo(6.306, 14.691);
  p.lineTo(12.877, 19.510);
  p.cubicTo(14.655, 15.108, 18.961, 12.000, 24.000, 12.000);
  p.cubicTo(27.059, 12.000, 29.842, 13.154, 31.961, 15.039);
  p.lineTo(37.618, 9.382);
  p.cubicTo(34.046, 6.053, 29.268, 4.000, 24.000, 4.000);
  p.cubicTo(16.318, 4.000, 9.656, 8.337, 6.306, 14.691);
  p.close();
  return p;
}

Path _gGreen() {
  final p = Path();
  p.moveTo(24.000, 44.000);
  p.cubicTo(29.166, 44.000, 33.860, 42.023, 37.409, 38.808);
  p.lineTo(31.219, 33.570);
  p.cubicTo(29.211, 35.091, 26.715, 36.000, 24.000, 36.000);
  p.cubicTo(18.798, 36.000, 14.381, 32.683, 12.717, 28.054);
  p.lineTo(6.195, 33.079);
  p.cubicTo(9.505, 39.556, 16.227, 44.000, 24.000, 44.000);
  p.close();
  return p;
}

Path _gBlue() {
  final p = Path();
  p.moveTo(43.611, 20.083);
  p.lineTo(42.000, 20.083);
  p.lineTo(42.000, 20.000);
  p.lineTo(24.000, 20.000);
  p.lineTo(24.000, 28.000);
  p.lineTo(35.303, 28.000);
  p.cubicTo(34.511, 30.237, 33.072, 32.166, 31.216, 33.571);
  p.cubicTo(31.217, 33.570, 31.218, 33.570, 31.219, 33.569);
  p.lineTo(37.409, 38.807);
  p.cubicTo(36.971, 39.205, 44.000, 34.000, 44.000, 24.000);
  p.cubicTo(44.000, 22.659, 43.862, 21.350, 43.611, 20.083);
  p.close();
  return p;
}
