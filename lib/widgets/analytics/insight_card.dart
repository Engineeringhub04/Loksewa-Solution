import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Visual tone of an insight card.
enum InsightTone { strength, focus }

/// The two rows that turn the charts above into something to actually do next.
///
/// Mirrors InsightCard.tsx. Everything higher up the page describes; this
/// prescribes — which is why it is the only section with a destination
/// attached. A hairline in the source's own colour runs down the leading
/// edge: enough to tie the card to its chart slice without tinting the whole
/// surface, which would read as an alert rather than a suggestion.
class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.tone,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.value,
    required this.accent,
    required this.ctaLabel,
    required this.onPress,
  });

  final InsightTone tone;

  /// "Your strength" / "Needs attention".
  final String eyebrow;

  /// The source name — "Practice", "Daily Test".
  final String title;

  /// One line of reasoning; never just a restatement of the number.
  final String description;

  /// Formatted figure shown on the right, e.g. "82%". Hidden when absent.
  final String? value;

  /// Fixed source hue, so this card matches its slice on the radar and donut.
  final Color accent;
  final String ctaLabel;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    // A Border with non-uniform sides cannot share a BoxDecoration with a
    // borderRadius (Flutter refuses to paint it), so the rounded corners come
    // from the clip and the square border is cut to fit them.
    return GestureDetector(
      onTap: onPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(ExpoSpacing.md),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(color: colors.border),
              right: BorderSide(color: colors.border),
              bottom: BorderSide(color: colors.border),
              left: BorderSide(color: accent, width: 3),
            ),
          ),
          child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ExpoRadius.md),
                color: accent.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Icon(
                tone == InsightTone.strength
                    ? Icons.military_tech
                    : Icons.trending_up,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: ExpoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ExpoType.caption,
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ExpoType.body,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ExpoType.caption,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ExpoSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null)
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ExpoType.bodyLarge,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ctaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ExpoType.caption,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 13, color: colors.primary),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
