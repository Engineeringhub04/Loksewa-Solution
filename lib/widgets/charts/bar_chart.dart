import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'chart_math.dart';

const _padTop = 12.0;
const _padRight = 6.0;
const _padBottom = 20.0;
const _padLeft = 34.0;

/// The last bar starts moving when the first is halfway — a ripple, not a wave.
const _staggerSpan = 0.5;
const _maxXLabels = 7;

class _BarRect {
  _BarRect(this.x, this.y, this.width, this.height, this.value);
  final double x;
  final double y;
  final double width;
  final double height;
  final double value;
}

/// Vertical, time-indexed bars (daily effort).
///
/// Tap a bar to call [onSelect] with its index; the parent owns the
/// [selectedIndex] toggle.
class BarChart extends StatefulWidget {
  const BarChart({
    super.key,
    required this.values,
    this.labels,
    required this.color,
    this.height = 180,
    this.maxValue,
    this.averageValue,
    this.averageLabel,
    this.accentIndices,
    this.accentColor,
    this.seededCount = 0,
    this.selectedIndex,
    this.onSelect,
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

  /// Draws a dashed reference line, e.g. the period average.
  final double? averageValue;
  final String? averageLabel;

  /// Per-bar tint override — used to mark weekends.
  final List<int>? accentIndices;
  final Color? accentColor;

  /// Leading bars that are backfilled estimates; drawn dimmer.
  final int seededCount;
  final int? selectedIndex;
  final void Function(int index)? onSelect;
  final String Function(double value) formatValue;
  final String? emptyLabel;

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart>
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
    _signature = widget.values.join(',');
    _controller.forward();
  }

  @override
  void didUpdateWidget(BarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keyed on the VALUES, not the list identity: a parent re-render
    // (selecting a bar, switching theme) passes a fresh list every time, and
    // depending on identity would restart the grow animation on every tap.
    final next = widget.values.join(',');
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

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    if (widget.values.isEmpty) {
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

    final accents = widget.accentIndices?.toSet() ?? <int>{};
    final labelStep = widget.labels == null || widget.labels!.isEmpty
        ? 1
        : math.max(1, (widget.labels!.length / _maxXLabels).ceil());

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 280.0;
        final innerW = math.max(0.0, width - _padLeft - _padRight);
        final innerH = math.max(0.0, widget.height - _padTop - _padBottom);
        final baseline = _padTop + innerH;
        final dataMax = widget.values
            .fold<double>(0, (m, v) => v.isFinite && v > m ? v : m);
        final top = widget.maxValue ?? niceMax(dataMax);

        final gapRatio = widget.values.length > 40 ? 0.2 : 0.36;
        const minHeight = 2.0;
        final slot = widget.values.isEmpty ? 0.0 : innerW / widget.values.length;
        final barWidth = math.max(1.0, slot * (1 - gapRatio));
        final bars = List<_BarRect>.generate(widget.values.length, (index) {
          final v = widget.values[index];
          final safe = v.isFinite ? math.max(0.0, v) : 0.0;
          final scaled = (math.min(safe, top) / (top > 0 ? top : 1)) * innerH;
          final h = safe > 0 ? math.max(minHeight, scaled) : minHeight;
          return _BarRect(
            _padLeft + slot * index + (slot - barWidth) / 2,
            baseline - h,
            barWidth,
            h,
            safe,
          );
        });

        double? averageY;
        if (widget.averageValue != null && top > 0) {
          averageY = baseline -
              (math.min(widget.averageValue!, top) / top) *
                  (baseline - _padTop);
        }

        return Stack(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(width, widget.height),
                  painter: _BarChartPainter(
                    bars: bars,
                    baseline: baseline,
                    top: top,
                    labels: widget.labels,
                    labelStep: labelStep,
                    color: widget.color,
                    accents: accents,
                    accentColor: widget.accentColor,
                    seededCount: widget.seededCount,
                    selectedIndex: widget.selectedIndex,
                    averageY: averageY,
                    averageLabel: widget.averageLabel,
                    formatValue: widget.formatValue,
                    progress: _controller.value,
                    palette: colors,
                  ),
                );
              },
            ),
            // Touch targets live above the bars rather than on them: a 2px
            // bar for a zero day is impossible to hit, but its whole column
            // is comfortable.
            if (widget.onSelect != null)
              Positioned(
                left: _padLeft,
                top: _padTop,
                width: innerW,
                height: math.max(0.0, baseline - _padTop),
                child: Row(
                  children: List.generate(widget.values.length, (index) {
                    return Expanded(
                      child: GestureDetector(
                        key: ValueKey('bar-tap-$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onSelect!(index),
                        child: const SizedBox.expand(),
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.bars,
    required this.baseline,
    required this.top,
    required this.labels,
    required this.labelStep,
    required this.color,
    required this.accents,
    required this.accentColor,
    required this.seededCount,
    required this.selectedIndex,
    required this.averageY,
    required this.averageLabel,
    required this.formatValue,
    required this.progress,
    required this.palette,
  });

  final List<_BarRect> bars;
  final double baseline;
  final double top;
  final List<String>? labels;
  final int labelStep;
  final Color color;
  final Set<int> accents;
  final Color? accentColor;
  final int seededCount;
  final int? selectedIndex;
  final double? averageY;
  final String? averageLabel;
  final String Function(double value) formatValue;
  final double progress;
  final ExpoPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // Baseline.
    canvas.drawLine(
      Offset(_padLeft, baseline),
      Offset(size.width - _padRight, baseline),
      Paint()
        ..color = palette.divider
        ..strokeWidth = 1,
    );

    // Top axis label.
    final axisStyle = TextStyle(color: palette.textDisabled, fontSize: 9);
    final topTp = TextPainter(
      text: TextSpan(text: formatValue(top), style: axisStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    topTp.paint(canvas, Offset(_padLeft - 6 - topTp.width, _padTop - 2));

    final count = bars.length;
    for (var i = 0; i < count; i++) {
      final bar = bars[i];
      // Each bar derives its own slice of the shared timeline instead of
      // owning an animation, so a 90-day chart still runs exactly one.
      final startAt = (i / math.max(1, count)) * _staggerSpan;
      final span = 1 - startAt;
      final local = span <= 0
          ? 1.0
          : math.max(0.0, math.min(1.0, (progress - startAt) / span));
      final grown = bar.height * local;
      if (grown <= 0) continue;

      final barColor =
          accents.contains(i) && accentColor != null ? accentColor! : color;
      // Estimated days read as background texture; the selected bar reads as
      // foreground. Everything else sits in between.
      final opacity = i < seededCount
          ? 0.38
          : (selectedIndex == null || selectedIndex == i ? 1.0 : 0.45);

      final radius = math.min(ExpoRadius.sm, bar.width / 2);
      final rect = Rect.fromLTWH(
          bar.x, baseline - grown, bar.width, grown);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        Paint()..color = barColor.withValues(alpha: opacity),
      );
    }

    // Dashed average line.
    if (averageY != null) {
      final avgPaint = Paint()
        ..color = palette.textSecondary
        ..strokeWidth = 1;
      var x = _padLeft;
      while (x < size.width - _padRight) {
        canvas.drawLine(Offset(x, averageY!), Offset(x + 4, averageY!), avgPaint);
        x += 8;
      }
      if (averageLabel != null) {
        final avgTp = TextPainter(
          text: TextSpan(text: averageLabel, style: axisStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        avgTp.paint(
          canvas,
          Offset(size.width - _padRight - avgTp.width, averageY! - 4 - avgTp.height),
        );
      }
    }

    // X labels, thinned.
    if (labels != null) {
      for (var i = 0; i < labels!.length; i++) {
        final label = labels![i];
        if (label.isEmpty) continue;
        final isLast = i == labels!.length - 1;
        if (i % labelStep != 0 && !isLast) continue;
        if (i >= bars.length) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: selectedIndex == i
                  ? palette.textPrimary
                  : palette.textDisabled,
              fontSize: 9,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(bars[i].x + bars[i].width / 2 - tp.width / 2,
              size.height - 5 - tp.height),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.valuesSignature != valuesSignature ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.palette != palette;
  }

  String get valuesSignature => bars.map((b) => b.value).join(',');
}

// ---------------------------------------------------------------------------
// RankedBars
// ---------------------------------------------------------------------------

/// One horizontal bar row in [RankedBars].
class RankedBarRow {
  const RankedBarRow({
    required this.key,
    required this.label,
    required this.value,
    this.display,
    this.color,
    this.muted = false,
  });

  final String key;
  final String label;

  /// Drives the bar length, relative to [RankedBars.maxValue].
  final double value;

  /// What the user reads — "72%", "340 PTS". Defaults to the value.
  final String? display;
  final Color? color;

  /// Dims the row and its label for sources never touched.
  final bool muted;
}

/// Horizontal category bars — one row per source, label above the track, value
/// on the right. Bars fill from the left with the same stagger as the vertical
/// chart, so the two read as one family.
class RankedBars extends StatefulWidget {
  const RankedBars({
    super.key,
    required this.rows,
    required this.color,
    this.maxValue,
    this.barHeight = 8,
    this.onSelect,
    this.emptyLabel,
  });

  final List<RankedBarRow> rows;
  final Color color;
  final double? maxValue;

  /// Track height in px.
  final double barHeight;
  final void Function(String key)? onSelect;
  final String? emptyLabel;

  @override
  State<RankedBars> createState() => _RankedBarsState();
}

class _RankedBarsState extends State<RankedBars>
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
    _signature = _rowsSignature(widget.rows);
    _controller.forward();
  }

  @override
  void didUpdateWidget(RankedBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Value-keyed, so tapping a row to select it does not re-run the fill.
    final next = _rowsSignature(widget.rows);
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

  static String _rowsSignature(List<RankedBarRow> rows) =>
      rows.map((r) => '${r.key}:${r.value}').join('|');

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    if (widget.rows.isEmpty) {
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

    final dataMax =
        widget.rows.fold<double>(0, (m, r) => r.value > m ? r.value : m);
    final top = widget.maxValue ?? niceMax(dataMax);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.rows.length, (index) {
            final row = widget.rows[index];
            final startAt =
                (index / math.max(1, widget.rows.length)) * _staggerSpan;
            final span = 1 - startAt;
            final local = span <= 0
                ? 1.0
                : math.max(
                    0.0, math.min(1.0, (_controller.value - startAt) / span));
            final ratio =
                top > 0 ? math.max(0.0, math.min(1.0, row.value / top)) : 0.0;

            final content = Opacity(
              opacity: row.muted ? 0.5 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ExpoType.bodySmall,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        row.display ?? compactNumber(row.value),
                        style: TextStyle(
                          fontSize: ExpoType.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: widget.barHeight,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius:
                          BorderRadius.circular(ExpoRadius.pill),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio * local,
                      child: Container(
                        decoration: BoxDecoration(
                          color: row.color ?? widget.color,
                          borderRadius:
                              BorderRadius.circular(ExpoRadius.pill),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );

            final padded = Padding(
              padding: EdgeInsets.only(
                  bottom: index == widget.rows.length - 1 ? 0 : ExpoSpacing.sm),
              child: content,
            );

            if (widget.onSelect != null) {
              return GestureDetector(
                key: ValueKey('ranked-row-${row.key}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelect!(row.key),
                child: padded,
              );
            }
            return KeyedSubtree(
              key: ValueKey('ranked-row-${row.key}'),
              child: padded,
            );
          }),
        );
      },
    );
  }
}
