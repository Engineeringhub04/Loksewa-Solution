import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One day in the [Heatmap].
class HeatmapDay {
  const HeatmapDay({
    required this.key,
    required this.value,
    this.seeded = false,
  });

  /// `YYYY-MM-DD` (Kathmandu date — never re-interpreted in another zone).
  final String key;
  final double value;

  /// Backfilled estimate rather than a recorded day.
  final bool seeded;
}

/// Level 0 is "nothing", so it gets the track colour rather than a faint tint.
const _levelOpacity = [0.0, 0.22, 0.45, 0.7, 1.0];
const _cellGap = 3.0;

/// Only every other weekday is labelled; seven labels in a small grid collide.
const _labelledWeekdays = [1, 3, 5];

/// Weekday of a `YYYY-MM-DD` key, read in UTC (0 = Sunday).
///
/// Local parsing would shift the whole grid by a day for anyone whose device is
/// behind UTC, because the keys are already Kathmandu dates and must not be
/// re-interpreted in another zone.
int _weekdayOf(String key) {
  try {
    return DateTime.parse('${key}T00:00:00Z').weekday % 7;
  } catch (_) {
    return 0;
  }
}

/// Four ascending thresholds over the non-zero values.
///
/// Quantiles rather than fixed cutoffs: a user doing 5 questions a day and one
/// doing 200 should both see a readable spread instead of a uniformly pale or
/// uniformly saturated grid.
List<double> _buildThresholds(List<double> values) {
  final active = values.where((v) => v > 0).toList()..sort();
  if (active.isEmpty) return [1, 2, 3, 4];
  double at(double ratio) =>
      active[math.min(active.length - 1, (active.length * ratio).floor())];
  final raw = [at(0.25), at(0.5), at(0.75), at(0.95)];
  // Force strictly increasing steps so a low-variance history still bands.
  return List.generate(
      4, (i) => math.max(raw[i], (i + 1).toDouble()));
}

int _levelOf(double value, List<double> thresholds) {
  if (value <= 0) return 0;
  if (value <= thresholds[0]) return 1;
  if (value <= thresholds[1]) return 2;
  if (value <= thresholds[2]) return 3;
  return 4;
}

class _Column {
  _Column(this.cells, this.firstKey);

  /// Seven slots, Sunday..Saturday. `null` pads the first and last weeks.
  final List<HeatmapDay?> cells;
  final String firstKey;
}

/// Contribution grid: weeks as columns, weekdays as rows.
///
/// A year of study reduced to a shape you can read in a second — the gaps are
/// as informative as the streaks, which is why empty days are drawn rather
/// than skipped. Horizontally scrollable; auto-scrolls to today on mount.
/// Tap a cell to call [onSelect]; the parent owns the [selectedKey] toggle.
class Heatmap extends StatefulWidget {
  const Heatmap({
    super.key,
    required this.days,
    required this.color,
    required this.weekdayLabels,
    this.monthLabelFor,
    this.cellSize = 13,
    this.selectedKey,
    this.onSelect,
    this.emptyLabel,
  });

  final List<HeatmapDay> days;
  final Color color;

  /// Seven entries, Sunday first, in the active language.
  final List<String> weekdayLabels;

  /// Returns a short month label for the first day of a column, or null.
  final String? Function(String dayKey)? monthLabelFor;
  final double cellSize;
  final String? selectedKey;
  final void Function(HeatmapDay day)? onSelect;
  final String? emptyLabel;

  @override
  State<Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<Heatmap>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _enterController;
  late List<_Column> _columns;
  late List<double> _thresholds;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _rebuild();
    // Today lives at the right-hand edge, which is off-screen on a long range.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      _enterController.forward();
    });
  }

  @override
  void didUpdateWidget(Heatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days != widget.days) {
      _rebuild();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _enterController.dispose();
    super.dispose();
  }

  void _rebuild() {
    final cols = <_Column>[];
    var current = <HeatmapDay?>[];

    for (var index = 0; index < widget.days.length; index++) {
      final day = widget.days[index];
      final weekday = _weekdayOf(day.key);
      if (index == 0) {
        current = List<HeatmapDay?>.filled(weekday, null, growable: true);
      }
      current.add(day);
      if (weekday == 6) {
        cols.add(_Column(current, current.firstWhere((c) => c != null)!.key));
        current = [];
      }
    }
    if (current.isNotEmpty) {
      final firstReal = current.firstWhere((c) => c != null,
          orElse: () => null);
      while (current.length < 7) {
        current.add(null);
      }
      if (firstReal != null) {
        cols.add(_Column(current, firstReal.key));
      }
    }

    _columns = cols;
    _thresholds =
        _buildThresholds(widget.days.map((d) => d.value).toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    if (widget.days.isEmpty) {
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

    final step = widget.cellSize + _cellGap;
    var lastMonthLabel = '';

    return AnimatedBuilder(
      animation: _enterController,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Weekday gutter stays put while the weeks scroll under it.
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                children: List.generate(7, (index) {
                  final label = index < widget.weekdayLabels.length
                      ? widget.weekdayLabels[index]
                      : '';
                  return Container(
                    height: widget.cellSize,
                    margin: const EdgeInsets.only(bottom: _cellGap),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _labelledWeekdays.contains(index) ? label : '',
                      style: TextStyle(
                        fontSize: 9,
                        height: 11 / 9,
                        color: colors.textDisabled,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: ExpoSpacing.xs),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_columns.length, (columnIndex) {
                    final column = _columns[columnIndex];
                    final monthLabel =
                        widget.monthLabelFor?.call(column.firstKey) ?? '';
                    final showMonth = monthLabel.isNotEmpty &&
                        monthLabel != lastMonthLabel;
                    if (showMonth) lastMonthLabel = monthLabel;

                    // Capped stagger: the sweep should suggest time passing,
                    // not make the user wait for it.
                    final delayMs =
                        math.min(columnIndex * 12, 300).toDouble();
                    final opacity = CurvedAnimation(
                      parent: _enterController,
                      curve: Interval(
                        delayMs / 520,
                        math.min(1.0, (delayMs + 220) / 520),
                        curve: Curves.easeOut,
                      ),
                    ).value;

                    return Opacity(
                      opacity: opacity,
                      child: Container(
                        margin: EdgeInsets.only(
                            right: columnIndex == _columns.length - 1
                                ? 0
                                : _cellGap),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 14,
                              width: step * 3,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  showMonth ? monthLabel : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontSize: 9,
                                    height: 10 / 9,
                                    color: colors.textDisabled,
                                  ),
                                ),
                              ),
                            ),
                            ...List.generate(7, (cellIndex) {
                              final cell = cellIndex < column.cells.length
                                  ? column.cells[cellIndex]
                                  : null;
                              if (cell == null) {
                                return Container(
                                  width: widget.cellSize,
                                  height: widget.cellSize,
                                  margin: const EdgeInsets.only(
                                      bottom: _cellGap),
                                );
                              }
                              final level =
                                  _levelOf(cell.value, _thresholds);
                              final selected =
                                  widget.selectedKey == cell.key;
                              final cellOpacity = level == 0
                                  ? 1.0
                                  : _levelOpacity[level] *
                                      (cell.seeded ? 0.5 : 1.0);
                              return Container(
                                margin: const EdgeInsets.only(
                                    bottom: _cellGap),
                                child: GestureDetector(
                                  key: ValueKey('heatmap-cell-${cell.key}'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.onSelect == null
                                      ? null
                                      : () => widget.onSelect!(cell),
                                  child: Opacity(
                                    opacity: cellOpacity,
                                    child: Container(
                                      width: widget.cellSize,
                                      height: widget.cellSize,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                            math.min(4.0, ExpoRadius.sm)),
                                        color: level == 0
                                            ? colors.surfaceAlt
                                            : widget.color,
                                        border: selected
                                            ? Border.all(
                                                color: colors.textPrimary,
                                                width: 1.5,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The "less → more" key that sits under the grid.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({
    super.key,
    required this.color,
    required this.lessLabel,
    required this.moreLabel,
    this.cellSize = 10,
  });

  final Color color;
  final String lessLabel;
  final String moreLabel;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          lessLabel,
          style: TextStyle(
            fontSize: ExpoType.caption,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: ExpoSpacing.xs),
        ...List.generate(_levelOpacity.length, (index) {
          return Opacity(
            opacity: index == 0 ? 1.0 : _levelOpacity[index],
            child: Container(
              width: cellSize,
              height: cellSize,
              margin: EdgeInsets.only(
                  right: index == _levelOpacity.length - 1
                      ? 0
                      : ExpoSpacing.xs),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(math.min(3.0, ExpoRadius.sm)),
                color: index == 0 ? colors.surfaceAlt : color,
              ),
            ),
          );
        }),
        const SizedBox(width: ExpoSpacing.xs),
        Text(
          moreLabel,
          style: TextStyle(
            fontSize: ExpoType.caption,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
