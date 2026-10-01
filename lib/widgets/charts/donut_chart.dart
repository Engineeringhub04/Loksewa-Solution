import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Degrees of breathing room between neighbouring arcs.
const _gapDeg = 2.0;

/// Ring chart for compositional data — where study time went, how points were
/// earned. Arcs draw themselves in once; the total sits in the centre.
///
/// Tapping a legend row or an arc calls [onSelect] with that slice's key; the
/// parent owns the [selectedKey] toggle. The selected arc nudges outward.
class DonutDatum {
  const DonutDatum({
    required this.key,
    required this.label,
    required this.value,
    required this.color,
    this.display,
  });

  final String key;
  final String label;
  final double value;
  final Color color;

  /// What the legend shows — "1h 20m", "340 PTS". Falls back to the share.
  final String? display;
}

class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.data,
    required this.centerValue,
    required this.centerLabel,
    this.selectedKey,
    this.onSelect,
    this.size = 140,
    this.thickness = 16,
    this.showLegend = true,
    this.emptyLabel,
  });

  final List<DonutDatum> data;
  final String centerValue;
  final String centerLabel;
  final String? selectedKey;
  final void Function(String key)? onSelect;
  final double size;
  final double thickness;
  final bool showLegend;
  final String? emptyLabel;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _Slice {
  _Slice({
    required this.key,
    required this.color,
    required this.startDeg,
    required this.sweepDeg,
    required this.startAt,
  });

  final String key;
  final Color color;

  /// Degrees clockwise from 12 o'clock.
  final double startDeg;
  final double sweepDeg;
  final double startAt;
}

class _DonutChartState extends State<DonutChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _signature = _dataSignature(widget.data);
    _controller.forward();
  }

  @override
  void didUpdateWidget(DonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Value-keyed: selecting a legend row rebuilds with a new `data` list
    // identity, and that must not replay the sweep.
    final next = _dataSignature(widget.data);
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

  static String _dataSignature(List<DonutDatum> data) =>
      data.map((d) => '${d.key}:${d.value}').join('|');

  List<_Slice> _slices() {
    final total = widget.data.fold<double>(
        0, (sum, d) => sum + (d.value > 0 ? d.value : 0));
    if (total <= 0) return [];
    final count = widget.data.length;
    var cursor = 0.0;
    return List.generate(count, (index) {
      final d = widget.data[index];
      final safe = d.value > 0 ? d.value : 0.0;
      final full = (safe / total) * 360;
      final start = cursor;
      cursor += full;
      // Slices smaller than the gap would otherwise render inside-out; they
      // get zero sweep and simply do not draw.
      final sweep = math.max(0.0, full - _gapDeg);
      return _Slice(
        key: d.key,
        color: d.color,
        startDeg: start + _gapDeg / 2,
        sweepDeg: sweep,
        startAt: (index / math.max(1, count)) * 0.4,
      );
    });
  }

  void _selectAt(Offset local, List<_Slice> slices) {
    final onSelect = widget.onSelect;
    if (onSelect == null || slices.isEmpty) return;
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = local - center;
    final dist = delta.distance;
    // The selected arc thickens conceptually; accept taps across the full
    // possible band.
    final maxThickness = widget.thickness + 6;
    final ringRadius = (widget.size - maxThickness) / 2;
    if ((dist - ringRadius).abs() > maxThickness) return;
    var deg = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90) % 360;
    if (deg < 0) deg += 360;
    for (final slice in slices) {
      if (slice.sweepDeg <= 0) continue;
      if (deg >= slice.startDeg &&
          deg <= slice.startDeg + slice.sweepDeg) {
        onSelect(slice.key);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final total = widget.data.fold<double>(
        0, (sum, d) => sum + (d.value > 0 ? d.value : 0));

    if (total <= 0) {
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

    final slices = _slices();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _selectAt(details.localPosition, slices),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _DonutPainter(
                        slices: slices,
                        thickness: widget.thickness,
                        selectedKey: widget.selectedKey,
                        progress: _controller.value,
                        trackColor: colors.surfaceAlt,
                      ),
                    );
                  },
                ),
              ),
              // Centre total — pointer-transparent so arc taps pass through.
              IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.centerValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ExpoType.h3,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.centerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ExpoType.caption,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.showLegend) ...[
          const SizedBox(width: ExpoSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(widget.data.length, (index) {
                final item = widget.data[index];
                final share =
                    total > 0 ? (item.value / total) * 100 : 0.0;
                final active = widget.selectedKey == item.key;
                final dimmed = widget.selectedKey != null && !active;

                final row = Opacity(
                  opacity: dimmed ? 0.5 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: item.color,
                            borderRadius:
                                BorderRadius.circular(ExpoRadius.pill),
                          ),
                        ),
                        const SizedBox(width: ExpoSpacing.xs),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: ExpoType.caption,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          item.display ?? '${share.toStringAsFixed(0)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ExpoType.caption,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                if (widget.onSelect == null) {
                  return KeyedSubtree(
                    key: ValueKey('donut-legend-${item.key}'),
                    child: row,
                  );
                }
                return GestureDetector(
                  key: ValueKey('donut-legend-${item.key}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onSelect!(item.key),
                  child: row,
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.thickness,
    required this.selectedKey,
    required this.progress,
    required this.trackColor,
  });

  final List<_Slice> slices;
  final double thickness;
  final String? selectedKey;
  final double progress;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // The radius is set from the THICKEST possible stroke — otherwise
    // selecting a slice would clip it against the viewbox.
    final maxThickness = thickness + 6;
    final ringRadius = (size.width - maxThickness) / 2;

    // Track, so the ring still reads as a ring while the arcs grow.
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );

    for (final slice in slices) {
      if (slice.sweepDeg <= 0) continue;
      final span = 1 - slice.startAt;
      final local = span <= 0
          ? 1.0
          : math.max(0.0, math.min(1.0, (progress - slice.startAt) / span));
      final sweep = slice.sweepDeg * local;
      if (sweep <= 0) continue;

      final selected = selectedKey == slice.key;
      final dimmed = selectedKey != null && !selected;
      // 12 o'clock clockwise → canvas radians (0 at 3 o'clock).
      final startRad = (slice.startDeg - 90) * math.pi / 180;

      // The selected arc nudges outward along its mid-angle.
      if (selected) {
        final midRad = (slice.startDeg + slice.sweepDeg / 2 - 90) *
            math.pi /
            180;
        canvas.save();
        canvas.translate(math.cos(midRad) * 6, math.sin(midRad) * 6);
      }
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        startRad,
        sweep * math.pi / 180,
        false,
        Paint()
          ..color = slice.color.withValues(alpha: dimmed ? 0.4 : 1.0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round,
      );
      if (selected) canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedKey != selectedKey ||
        oldDelegate.slices != slices;
  }
}
