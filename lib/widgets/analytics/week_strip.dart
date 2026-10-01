import 'package:flutter/material.dart';

import '../../services/analytics/analytics_derive.dart';
import '../../theme/app_theme.dart';

/// Seven dots for the last seven days — the smallest possible answer to "am I
/// actually keeping this up?".
///
/// Mirrors WeekStrip.tsx. Three states, not two: a day with no snapshot is
/// drawn as a hollow ring rather than an empty dot, because "we have no record
/// of this day" and "you did nothing this day" are different claims and only
/// one of them is ours to make. Today is marked with a ring rather than a
/// different fill, so it can be both "today" and "done" at once.
///
/// One shared one-shot timeline pops the dots in left to right.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.dots,
    required this.weekdayLabels,
    required this.color,
  });

  final List<WeekDot> dots;

  /// Seven short weekday names, Sunday first.
  final List<String> weekdayLabels;
  final Color color;

  static const _dot = 28.0;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      builder: (context, progress, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var index = 0; index < dots.length; index++)
              _dotColumn(
                colors: colors,
                dot: dots[index],
                index: index,
                progress: progress,
              ),
          ],
        );
      },
    );
  }

  Widget _dotColumn({
    required ExpoPalette colors,
    required WeekDot dot,
    required int index,
    required double progress,
  }) {
    // Each dot takes a slice of one shared timeline rather than owning an
    // animation, so the strip pops in left to right off a single tween.
    final startAt = (index / 7) * 0.6;
    final span = 1 - startAt;
    final local =
        span <= 0 ? 1.0 : ((progress - startAt) / span).clamp(0.0, 1.0);

    final active = dot.activities > 0;
    final recorded = dot.recorded;

    return Opacity(
      opacity: local,
      child: Transform.scale(
        scale: 0.6 + local * 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dot.weekday < weekdayLabels.length
                  ? weekdayLabels[dot.weekday]
                  : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: _dot + 6,
              height: _dot + 6,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: _dot,
                    height: _dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? color
                          : recorded
                              ? colors.surfaceAlt
                              : Colors.transparent,
                      border: !active && !recorded
                          ? Border.all(color: colors.border)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: active
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  if (dot.today)
                    Container(
                      width: _dot + 6,
                      height: _dot + 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: colors.primary, width: 1.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
