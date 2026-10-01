import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'chart_math.dart';

const _padTop = 12.0;
const _padRight = 8.0;
const _padBottom = 22.0;
const _padLeft = 38.0;
const _maxXLabels = 6;

/// The page's main trend chart: gridlines, y-axis labels, sparse x labels, a
/// gradient area fill and a stroke that draws itself in once.
///
/// The first [seededCount] points are backfilled estimates rather than recorded
/// days — they are drawn dashed and dimmed so an estimate never passes for a
/// measurement. Touch/drag shows a vertical guide line with a floating pill
/// (label + formatted value).
class LineAreaChart extends StatefulWidget {
  const LineAreaChart({
    super.key,
    required this.values,
    this.labels,
    required this.color,
    this.height = 190,
    this.maxValue,
    this.seededCount = 0,
    this.formatValue = compactNumber,
    this.emptyLabel,
  });

  final List<double> values;

  /// One entry per value; empty strings are simply not drawn.
  final List<String>? labels;
  final Color color;
  final double height;

  /// Pins the scale. Leave unset to fit the data.
  final double? maxValue;

  final int seededCount;

  /// Formats the y-axis labels — percentages, durations, counts.
  final String Function(double value) formatValue;
  final String? emptyLabel;

  @override
  State<LineAreaChart> createState() => _LineAreaChartState();
}

class _LineAreaChartState extends State<LineAreaChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _signature = '';
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _signature = _valuesSignature(widget.values);
    _controller.forward();
  }

  @override
  void didUpdateWidget(LineAreaChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _valuesSignature(widget.values);
    if (next != _signature) {
      _signature = next;
      _selectedIndex = null;
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

  static String _valuesSignature(List<double> values) => values.join(',');

  double _top() {
    final dataMax =
        widget.values.fold<double>(0, (m, v) => v.isFinite && v > m ? v : m);
    return widget.maxValue ?? niceMax(dataMax);
  }

  void _selectAt(Offset local, double width) {
    final points = _buildPoints(widget.values, width, widget.height, _top());
    if (points.isEmpty) return;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final dist = (points[i].dx - local.dx).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    setState(() => _selectedIndex = best);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    if (widget.values.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            widget.emptyLabel ?? '',
            style: TextStyle(
              fontSize: ExpoType.bodySmall,
              color: colors.textSecondary,
            ),
          ),
        ),
      );
    }

    final labelStep = widget.labels == null || widget.labels!.isEmpty
        ? 1
        : math.max(1, (widget.labels!.length / _maxXLabels).ceil());

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 280.0;
        final points = _buildPoints(widget.values, width, widget.height, _top());

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _selectAt(details.localPosition, width),
          onPanUpdate: (details) => _selectAt(details.localPosition, width),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size(width, widget.height),
                painter: _LineAreaPainter(
                  values: widget.values,
                  points: points,
                  labels: widget.labels,
                  labelStep: labelStep,
                  color: widget.color,
                  maxValue: widget.maxValue,
                  seededCount: widget.seededCount,
                  formatValue: widget.formatValue,
                  progress: _controller.value,
                  selectedIndex: _selectedIndex,
                  palette: colors,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

List<Offset> _buildPoints(
    List<double> values, double width, double height, double top) {
  final count = values.length;
  if (count == 0) return [];
  final innerW = math.max(0.0, width - _padLeft - _padRight);
  final innerH = math.max(0.0, height - _padTop - _padBottom);
  final max = top > 0 ? top : 1;
  return List.generate(count, (index) {
    final ratio = count == 1 ? 0.5 : index / (count - 1);
    final v = values[index].isFinite ? values[index].clamp(0.0, max) : 0.0;
    return Offset(
      _padLeft + ratio * innerW,
      _padTop + innerH - (v / max) * innerH,
    );
  });
}

/// Catmull-Rom smoothing converted to cubic beziers, with control points
/// clamped to each segment's own y-range so the curve never overshoots below
/// the baseline and reads as negative activity that never happened.
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
    final c1x = p1.dx + (p2.dx - p0.dx) / 6;
    final c2x = p2.dx - (p3.dx - p1.dx) / 6;
    path.cubicTo(c1x, c1y, c2x, c2y, p2.dx, p2.dy);
  }
  return path;
}

Path _dashPath(Path source, List<double> dashArray) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    var dashIndex = 0;
    while (distance < metric.length) {
      final dashLen = dashArray[dashIndex % dashArray.length];
      final next = math.min(distance + dashLen, metric.length);
      if (draw) {
        result.addPath(metric.extractPath(distance, next), Offset.zero);
      }
      distance = next;
      draw = !draw;
      dashIndex++;
    }
  }
  return result;
}

List<double> _niceTicks(double max, int count) {
  final top = niceMax(max);
  final safe = math.max(1, count);
  return List.generate(safe + 1, (i) => (top / safe) * i);
}

class _LineAreaPainter extends CustomPainter {
  _LineAreaPainter({
    required this.values,
    required this.points,
    required this.labels,
    required this.labelStep,
    required this.color,
    required this.maxValue,
    required this.seededCount,
    required this.formatValue,
    required this.progress,
    required this.selectedIndex,
    required this.palette,
  });

  final List<double> values;
  final List<Offset> points;
  final List<String>? labels;
  final int labelStep;
  final Color color;
  final double? maxValue;
  final int seededCount;
  final String Function(double value) formatValue;
  final double progress;
  final int? selectedIndex;
  final ExpoPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = _padTop + math.max(0.0, size.height - _padTop - _padBottom);
    final dataMax =
        values.fold<double>(0, (m, v) => v.isFinite && v > m ? v : m);
    final top = maxValue ?? niceMax(dataMax);

    // Gridlines + y labels, drawn from the top down so the axis reads
    // high-to-low the way the values do.
    final labelStyle = TextStyle(color: palette.textDisabled, fontSize: 9);
    for (var i = _niceTicks(top, 4).length - 1; i >= 0; i--) {
      final tick = _niceTicks(top, 4)[i];
      final ratio = top > 0 ? tick / top : 0;
      final y = baseline - ratio * (baseline - _padTop);
      final grid = Paint()
        ..color = palette.divider
        ..strokeWidth = 1;
      if (i != 0) {
        // Dashed gridline.
        var x = _padLeft;
        while (x < size.width - _padRight) {
          canvas.drawLine(Offset(x, y), Offset(x + 3, y), grid);
          x += 8;
        }
      } else {
        canvas.drawLine(
            Offset(_padLeft, y), Offset(size.width - _padRight, y), grid);
      }
      final tp = TextPainter(
        text: TextSpan(text: formatValue(tick), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_padLeft - 6 - tp.width, y - tp.height / 2));
    }

    // The seeded prefix and the observed remainder overlap by one point,
    // otherwise the two strokes meet with a visible gap at the boundary.
    final cut = math.max(0, math.min(seededCount, points.length));
    final seededPts = cut >= 2 ? points.sublist(0, cut) : <Offset>[];
    final livePts =
        cut >= 1 ? points.sublist(math.max(0, cut - 1)) : points;

    // Gradient area fill.
    final areaPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, _padTop),
        Offset(0, baseline),
        [color.withValues(alpha: 0.3), color.withValues(alpha: 0.02)],
      );
    if (points.length >= 2) {
      final area = _smoothPath(points)
        ..lineTo(points.last.dx, baseline)
        ..lineTo(points.first.dx, baseline)
        ..close();
      final areaOpacity = math.max(0.0, progress * 1.6 - 0.6);
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Color.fromRGBO(0, 0, 0, areaOpacity),
      );
      canvas.drawPath(area, areaPaint);
      canvas.restore();
    }

    // Seeded (estimated) prefix: dashed + dimmed.
    if (seededPts.length >= 2) {
      final seededOpacity = math.max(0.0, progress * 1.6 - 0.6) * 0.55;
      canvas.drawPath(
        _dashPath(_smoothPath(seededPts), const [5, 4]),
        Paint()
          ..color = color.withValues(alpha: seededOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Live line: draws itself in once.
    if (livePts.length >= 2) {
      final live = _smoothPath(livePts);
      final drawn = Path();
      for (final metric in live.computeMetrics()) {
        drawn.addPath(
            metric.extractPath(0, metric.length * progress), Offset.zero);
      }
      canvas.drawPath(
        drawn,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else if (livePts.length == 1) {
      canvas.drawCircle(livePts.first, 2.5, Paint()..color = color);
    }

    // The most recent value always gets a marker — it is the number the user
    // actually came to check.
    final last = points.last;
    canvas.drawCircle(
      last,
      3.5,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      last,
      4.5,
      Paint()
        ..color = palette.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // X labels are thinned rather than rotated — a long range would otherwise
    // stack unreadable strings along the axis.
    if (labels != null) {
      for (var i = 0; i < labels!.length; i++) {
        final label = labels![i];
        if (label.isEmpty) continue;
        final isLast = i == labels!.length - 1;
        if (i % labelStep != 0 && !isLast) continue;
        if (i >= points.length) continue;
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = i == 0
            ? points[i].dx
            : isLast
                ? points[i].dx - tp.width
                : points[i].dx - tp.width / 2;
        tp.paint(canvas, Offset(x, size.height - 6 - tp.height));
      }
    }

    // Touch/drag: vertical guide line + floating pill (label + value).
    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      final point = points[selected];
      canvas.drawLine(
        Offset(point.dx, _padTop),
        Offset(point.dx, baseline),
        Paint()
          ..color = palette.textSecondary.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(point, 4, Paint()..color = palette.surface);
      canvas.drawCircle(point, 4,
          Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);

      final valueText = formatValue(
          values[selected].isFinite ? values[selected] : 0);
      final labelText =
          labels != null && selected < labels!.length ? labels![selected] : '';
      final valueTp = TextPainter(
        text: TextSpan(
          text: valueText,
          style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTp = labelText.isNotEmpty
          ? (TextPainter(
              text: TextSpan(
                  text: labelText,
                  style: TextStyle(
                      color: palette.textSecondary, fontSize: 10)),
              textDirection: TextDirection.ltr,
            )..layout())
          : null;
      final pillW = math.max(valueTp.width, labelTp?.width ?? 0) + 20;
      const pillH = 40.0;
      var pillX = point.dx - pillW / 2;
      pillX =
          pillX.clamp(4.0, math.max(4.0, size.width - pillW - 4)).toDouble();
      var pillY = point.dy - pillH - 10;
      if (pillY < _padTop) pillY = point.dy + 10;
      final pillRect =
          RRect.fromRectAndRadius(Rect.fromLTWH(pillX, pillY, pillW, pillH),
              const Radius.circular(10));
      canvas.drawShadow(
          Path()..addRRect(pillRect), Colors.black.withValues(alpha: 0.25),
          4, false);
      canvas.drawRRect(
          pillRect, Paint()..color = palette.surface);
      canvas.drawRRect(
          pillRect,
          Paint()
            ..color = palette.border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      valueTp.paint(
          canvas, Offset(pillX + (pillW - valueTp.width) / 2, pillY + 6));
      if (labelTp != null) {
        labelTp.paint(
            canvas,
            Offset(pillX + (pillW - labelTp.width) / 2,
                pillY + 6 + valueTp.height + 1));
      }
    }
  }

  @override
  bool shouldRepaint(_LineAreaPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.values != values ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.palette != palette ||
        oldDelegate.color != color;
  }
}
