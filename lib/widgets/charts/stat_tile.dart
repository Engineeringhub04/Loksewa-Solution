import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// KPI tile: one number, its movement, and the shape behind it.
///
/// The delta is the part that earns the tile its space — "4h 20m" alone says
/// nothing about whether the user is doing better than last week. [delta] is
/// in percentage POINTS and may be negative.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.delta,
    this.deltaLabel,
    this.trend,
    this.higherIsBetter = true,
    this.onPress,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  /// Percentage-point change against the previous equivalent period.
  final double? delta;

  /// Qualifies the delta — "this week", "vs last 30 days".
  final String? deltaLabel;
  final List<double>? trend;

  /// For metrics where a fall is the good outcome.
  final bool higherIsBetter;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final d = delta;
    final hasDelta = d != null && d.isFinite && d.abs().round() != 0;
    final improving = hasDelta ? (d > 0) == higherIsBetter : false;
    final deltaColor =
        hasDelta ? (improving ? colors.success : colors.danger) : colors.textSecondary;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The icon is tinted inline rather than sitting in its own tinted
        // square — a box this small reads as clutter next to the number it
        // introduces.
        Row(
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ExpoType.caption,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ExpoType.h2,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasDelta)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          d > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 11,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${d.abs().toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: ExpoType.caption,
                            fontWeight: FontWeight.w600,
                            color: deltaColor,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '—',
                      style: TextStyle(
                        fontSize: ExpoType.caption,
                        color: colors.textDisabled,
                      ),
                    ),
                  if (deltaLabel != null)
                    Text(
                      deltaLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.textDisabled,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: ExpoSpacing.xs),
            if (trend != null && trend!.length > 1)
              Sparkline(
                values: trend!,
                color: accent,
                // Roughly half the tile, so the number stays dominant.
                width: 64,
                height: 24,
              ),
          ],
        ),
      ],
    );

    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: body,
    );

    if (onPress == null) return card;
    return GestureDetector(
      onTap: onPress,
      child: card,
    );
  }
}

/// Axis-less micro line for KPI tiles. Draws itself in once and then holds
/// still.
class Sparkline extends StatefulWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 72,
    this.height = 28,
    this.strokeWidth = 2,
    this.showArea = true,
    this.maxValue,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;
  final bool showArea;

  /// Pins the vertical scale, e.g. to compare two tiles against each other.
  final double? maxValue;

  @override
  State<Sparkline> createState() => _SparklineState();
}

class _SparklineState extends State<Sparkline>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Offset> _points() {
    final count = widget.values.length;
    if (count == 0) return [];
    final pad = widget.strokeWidth;
    final innerW = math.max(0.0, widget.width - pad * 2);
    final innerH = math.max(0.0, widget.height - pad * 2);
    final dataMax = widget.values
        .fold<double>(0, (m, v) => v.isFinite && v > m ? v : m);
    final max = widget.maxValue ?? (dataMax > 0 ? dataMax : 1);
    return List.generate(count, (index) {
      final ratio = count == 1 ? 0.5 : index / (count - 1);
      final v = widget.values[index].isFinite
          ? widget.values[index].clamp(0.0, max)
          : 0.0;
      return Offset(
        pad + ratio * innerW,
        pad + innerH - (v / max) * innerH,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    // One point cannot describe a trend; a dot is honest, a flat line is not.
    if (widget.values.length < 2) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.values.length == 1
                  ? widget.color
                  : colors.textDisabled,
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.width, widget.height),
          painter: _SparklinePainter(
            points: _points(),
            color: widget.color,
            strokeWidth: widget.strokeWidth,
            showArea: widget.showArea,
            baselineY: widget.height - widget.strokeWidth,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

Path _smoothPath(List<Offset> points) {
  final path = Path();
  final count = points.length;
  if (count == 0) return path;
  path.moveTo(points[0].dx, points[0].dy);
  if (count == 1) return path;
  if (count == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }
  for (var i = 0; i < count - 1; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 < count ? i + 2 : count - 1];
    var c1y = p1.dy + (p2.dy - p0.dy) / 6;
    var c2y = p2.dy - (p3.dy - p1.dy) / 6;
    final lo = math.min(p1.dy, p2.dy);
    final hi = math.max(p1.dy, p2.dy);
    c1y = c1y.clamp(lo, hi);
    c2y = c2y.clamp(lo, hi);
    path.cubicTo(p1.dx + (p2.dx - p0.dx) / 6, c1y,
        p2.dx - (p3.dx - p1.dx) / 6, c2y, p2.dx, p2.dy);
  }
  return path;
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.showArea,
    required this.baselineY,
    required this.progress,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool showArea;
  final double baselineY;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final line = _smoothPath(points);

    if (showArea && points.length >= 2) {
      final area = Path.from(line)
        ..lineTo(points.last.dx, baselineY)
        ..lineTo(points.first.dx, baselineY)
        ..close();
      // Trails the line so the fill reads as a consequence of it, not a race.
      final areaOpacity = math.max(0.0, progress * 1.6 - 0.6);
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(0, baselineY),
            [
              color.withValues(alpha: 0.32 * areaOpacity),
              color.withValues(alpha: 0.0),
            ],
          ),
      );
    }

    final drawn = Path();
    for (final metric in line.computeMetrics()) {
      drawn.addPath(
          metric.extractPath(0, metric.length * progress), Offset.zero);
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.points != points ||
        oldDelegate.color != color;
  }
}
