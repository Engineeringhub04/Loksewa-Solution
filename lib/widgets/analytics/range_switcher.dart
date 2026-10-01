import 'package:flutter/material.dart';

import '../../services/analytics/analytics_types.dart';
import '../../theme/app_theme.dart';

/// One window option for the range switcher.
class RangeOption {
  const RangeOption({required this.value, required this.label});

  final AnalyticsRange value;
  final String label;
}

/// The 7D / 30D / 90D / All control that every range-scoped section reads from.
///
/// Mirrors RangeSwitcher.tsx: one control drives five sections, so it lives at
/// the top of the page rather than inside any single card. A sliding pill
/// marks the active segment (white text on the primary pill, secondary text
/// elsewhere — a theme text colour over the filled pill loses contrast).
class RangeSwitcher extends StatelessWidget {
  const RangeSwitcher({
    super.key,
    required this.options,
    required this.value,
    required this.onChange,
  });

  final List<RangeOption> options;
  final AnalyticsRange value;
  final ValueChanged<AnalyticsRange> onChange;

  static const _trackPadding = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final activeIndex = options.isEmpty
        ? 0
        : options
            .indexWhere((option) => option.value == value)
            .clamp(0, options.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final segment = options.isEmpty
            ? 0.0
            : (trackWidth - _trackPadding * 2) / options.length;

        return Container(
          padding: const EdgeInsets.all(_trackPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ExpoRadius.pill),
            color: colors.surfaceAlt,
            border: Border.all(color: colors.border),
          ),
          child: Stack(
            children: [
              // Drawn behind the labels; zero-width on the first frame.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: _trackPadding + activeIndex * segment,
                top: _trackPadding,
                bottom: _trackPadding,
                width: segment,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ExpoRadius.pill),
                    color: colors.primary,
                  ),
                ),
              ),
              Row(
                children: [
                  for (final option in options)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onChange(option.value),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: ExpoType.caption,
                                fontWeight: option.value == value
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: option.value == value
                                    ? Colors.white
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
