import 'package:flutter/material.dart';

import '../../services/analytics/analytics_derive.dart';
import '../../theme/app_theme.dart';
import 'analytics_shared.dart';

/// Four things worth aiming at, ordered by how close they are.
///
/// Mirrors MilestoneList.tsx. Ordering matters more than the list does: a
/// milestone at 3% is discouraging noise; the one at 80% is the reason someone
/// opens the app tomorrow, so it goes first and anything already earned drops
/// to the bottom (the data layer does the sort).
///
/// One shared one-shot timeline, sliced per row — four bars, one animation.
class MilestoneList extends StatelessWidget {
  const MilestoneList({
    super.key,
    required this.milestones,
    required this.labelFor,
    required this.doneLabel,
    this.onPress,
  });

  final List<Milestone> milestones;

  /// Milestone key → the line the user reads. Built by the screen.
  final String Function(Milestone milestone) labelFor;
  final String doneLabel;
  final VoidCallback? onPress;

  /// Plot height the list needs for [count] rows, so a fixed-height card
  /// doesn't have to guess: icon row (28) + gap (6) + track (6), with a 16px
  /// gutter between rows.
  static double preferredHeight(int count) {
    if (count <= 0) return 0;
    return count * (28.0 + 6.0 + _track) + (count - 1) * ExpoSpacing.md;
  }

  static const _track = 6.0;
  static const _staggerSpan = 0.5;

  static IconData _iconFor(Milestone milestone) {
    if (milestone.done) return Icons.check;
    switch (milestone.icon) {
      case 'trophy':
        return Icons.emoji_events;
      case 'flame':
        return Icons.local_fire_department;
      case 'ribbon':
        return Icons.military_tech;
      case 'hourglass':
        return Icons.hourglass_empty;
      default:
        return Icons.flag_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final signature = milestones
        .map((item) => '${item.key}:${item.progress.round()}')
        .join('|');

    final body = TweenAnimationBuilder<double>(
      // Replays only when the milestone pattern actually changes (e.g.
      // switching subcourse), never on an unrelated parent re-render.
      key: ValueKey<String>(signature),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, progress, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < milestones.length; index++)
              Padding(
                padding: EdgeInsets.only(
                    bottom:
                        index == milestones.length - 1 ? 0 : ExpoSpacing.md),
                child: _row(
                  context: context,
                  colors: colors,
                  milestone: milestones[index],
                  index: index,
                  count: milestones.length,
                  progress: progress,
                ),
              ),
          ],
        );
      },
    );

    if (onPress == null) return body;
    return GestureDetector(onTap: onPress, child: body);
  }

  Widget _row({
    required BuildContext context,
    required ExpoPalette colors,
    required Milestone milestone,
    required int index,
    required int count,
    required double progress,
  }) {
    final startAt = (index / (count <= 0 ? 1 : count)) * _staggerSpan;
    final span = 1 - startAt;
    final local =
        span <= 0 ? 1.0 : ((progress - startAt) / span).clamp(0.0, 1.0);
    final ratio = (milestone.progress / 100).clamp(0.0, 1.0);

    final milestoneColor = analyticsHex(milestone.color);
    final fillColor = milestone.done ? colors.success : milestoneColor;

    return Opacity(
      opacity: milestone.done ? 0.65 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ExpoRadius.sm),
                  color: milestoneColor.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Icon(_iconFor(milestone),
                    size: 15, color: milestoneColor),
              ),
              const SizedBox(width: ExpoSpacing.sm),
              Expanded(
                child: Text(
                  labelFor(milestone),
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
                milestone.done
                    ? doneLabel
                    : '${milestone.currentLabel} / ${milestone.targetLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ExpoType.caption,
                  fontWeight: FontWeight.w600,
                  color: milestone.done
                      ? colors.success
                      : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: _track,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ExpoRadius.pill),
              color: colors.surfaceAlt,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio * local,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ExpoRadius.pill),
                  color: fillColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
