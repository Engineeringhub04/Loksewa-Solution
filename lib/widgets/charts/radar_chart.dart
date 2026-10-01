import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

const _ringSteps = [0.2, 0.4, 0.6, 0.8, 1.0];

/// Room outside the outer ring for the axis labels.
const _labelInset = 30.0;
const _labelWidth = 62.0;

/// One axis of the [RadarChart].
class RadarAxis {
  const RadarAxis({
    required this.key,
    required this.label,
    required this.value,
    this.untouched = false,
  });

  final String key;
  final String label;

  /// 0..maxValue.
  final double value;

  /// Never-touched sources plot at zero but say so through a dimmed label.
  final bool untouched;
}

/// Six-axis skill radar. Shape at a glance: a lopsided hexagon is a lopsided
/// study habit, which is the point of the section.
///
/// The polygon scales in from the centre once on mount; untouched axes get
/// dimmed labels.
class RadarChart extends StatefulWidget {
  const RadarChart({
    super.key,
    required this.axes,
    required this.color,
    this.maxValue = 100,
    this.compareAxes,
    this.compareColor,
    this.maxSize = 230,
    this.emptyLabel,
  });

  final List<RadarAxis> axes;
  final Color color;
  final double maxValue;

  /// Optional second outline, e.g. the subcourse average.
  final List<RadarAxis>? compareAxes;
  final Color? compareColor;
  final double maxSize;
  final String? emptyLabel;

  @override
  State<RadarChart> createState() => _RadarChartState();
}

class _RadarChartState extends State<RadarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _signature = _ratiosSignature();
    _controller.forward();
  }

  @override
  void didUpdateWidget(RadarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Value-keyed: toggling the compare overlay must not replay the grow-out.
    final next = _ratiosSignature();
    if (next != _signature) {
      _signature = next;
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _ratiosSignature() =>
      widget.axes.map((a) => a.value.toStringAsFixed(3)).join(',');

  List<double> _ratios() {
    final max = widget.maxValue > 0 ? widget.maxValue : 1.0;
    return widget.axes.map((axis) {
      final safe = axis.value.isFinite ? axis.value : 0.0;
      return math.max(0.0, math.min(1.0, safe / max));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    if (widget.axes.length < 3) {
      return Center(
        child: Text(
          widget.emptyLabel ?? '',
          style: TextStyle(
            fontSize: ExpoType.bodySmall,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : widget.maxSize;
        final size = math.max(120.0, math.min(width, widget.maxSize));
        final center = size / 2;
        final radius = math.max(20.0, center - _labelInset);
        final count = widget.axes.length;
        final ratios = _ratios();

        // Angles are degrees clockwise from 12 o'clock.
        Offset polar(double r, double angleDeg) {
          final rad = (angleDeg - 90) * math.pi / 180;
          return Offset(center + r * math.cos(rad), center + r * math.sin(rad));
        }

        final labelPoints = List.generate(
            count, (i) => polar(radius + 16, (360 / count) * i));

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(size, size),
                      painter: _RadarPainter(
                        count: count,
                        center: center,
                        radius: radius,
                        ratios: ratios,
                        compareRatios: widget.compareAxes
                            ?.map((axis) {
                                final max = widget.maxValue > 0
                                    ? widget.maxValue
                                    : 1.0;
                                final safe =
                                    axis.value.isFinite ? axis.value : 0.0;
                                return math.max(
                                    0.0, math.min(1.0, safe / max));
                              }).toList(),
                        color: widget.color,
                        compareColor:
                            widget.compareColor ?? colors.textSecondary,
                        progress: _controller.value,
                        palette: colors,
                      ),
                    );
                  },
                ),
                // Labels are real Text, not painted text: they render in
                // Devanagari as well as English and pick up the app's font
                // handling.
                for (var i = 0; i < count; i++)
                  Positioned(
                    left: labelPoints[i].dx - _labelWidth / 2,
                    top: labelPoints[i].dy - 8,
                    width: _labelWidth,
                    child: IgnorePointer(
                      child: Text(
                        widget.axes[i].label,
                        key: ValueKey('radar-label-${widget.axes[i].key}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: ExpoType.caption,
                          fontWeight: widget.axes[i].untouched
                              ? FontWeight.w400
                              : FontWeight.w500,
                          color: widget.axes[i].untouched
                              ? colors.textDisabled
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.count,
    required this.center,
    required this.radius,
    required this.ratios,
    required this.compareRatios,
    required this.color,
    required this.compareColor,
    required this.progress,
    required this.palette,
  });

  final int count;
  final double center;
  final double radius;
  final List<double> ratios;
  final List<double>? compareRatios;
  final Color color;
  final Color compareColor;
  final double progress;
  final ExpoPalette palette;

  Offset _polar(double r, double angleDeg) {
    final rad = (angleDeg - 90) * math.pi / 180;
    return Offset(center + r * math.cos(rad), center + r * math.sin(rad));
  }

  Path _polygon(List<double> values, double scale) {
    final path = Path();
    for (var i = 0; i < count; i++) {
      final point =
          _polar(radius * values[i] * scale, (360 / count) * i);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = palette.divider
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Five concentric guide rings.
    for (final step in _ringSteps) {
      canvas.drawPath(
          _polygon(List.filled(count, step), 1.0), guide);
    }

    // Spokes.
    for (var i = 0; i < count; i++) {
      final end = _polar(radius, (360 / count) * i);
      canvas.drawLine(Offset(center, center), end, guide);
    }

    // Optional compare outline (static, dashed).
    final compare = compareRatios;
    if (compare != null && compare.length == count) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final point = _polar(radius * compare[i], (360 / count) * i);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      // Dashed via manual dashing.
      final dashed = Path();
      const dash = [4.0, 4.0];
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        var draw = true;
        var di = 0;
        while (distance < metric.length) {
          final len = dash[di % dash.length];
          final next = math.min(distance + len, metric.length);
          if (draw) {
            dashed.addPath(
                metric.extractPath(distance, next), Offset.zero);
          }
          distance = next;
          draw = !draw;
          di++;
        }
      }
      canvas.drawPath(
        dashed,
        Paint()
          ..color = compareColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // The main polygon grows out of the centre.
    final polygon = _polygon(ratios, progress);
    canvas.drawPath(
      polygon,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      polygon,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
        Offset(center, center), 2, Paint()..color = palette.textDisabled);
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ratios != ratios ||
        oldDelegate.palette != palette ||
        oldDelegate.color != color;
  }
}
