import 'package:flutter/material.dart';

import '../../services/analytics/analytics_derive.dart';
import '../../theme/app_theme.dart';

/// "You vs your subcourse" — where the user sits among everyone studying the
/// same thing.
///
/// Mirrors CohortStrip.tsx. Loaded behind a tap, never on mount: the board is
/// up to 300 documents, and spending that on every visit for a section not
/// everyone cares about is the kind of cost that only shows up on someone
/// else's phone bill.
///
/// The strip is deliberately NOT a ranking list. Every marker is placed on one
/// axis — points, zero to the leader — so the user's position and the cohort
/// median are directly comparable.
class CohortStrip extends StatelessWidget {
  const CohortStrip({
    super.key,
    required this.facts,
    required this.loading,
    required this.prompt,
    required this.loadLabel,
    required this.emptyLabel,
    required this.medianLabel,
    required this.youLabel,
    required this.toNextLabel,
    this.headline,
    this.subline,
    required this.boardLabel,
    required this.onLoad,
    required this.onOpenBoard,
  });

  final CohortFacts? facts;
  final bool loading;

  /// Shown before the section has ever been opened.
  final String prompt;
  final String loadLabel;
  final String emptyLabel;
  final String medianLabel;
  final String youLabel;

  /// Label for the "points to catch the person above" cell.
  final String toNextLabel;

  /// Pre-formatted lines the screen builds.
  final String? headline;
  final String? subline;
  final String boardLabel;
  final VoidCallback onLoad;
  final VoidCallback onOpenBoard;

  static const _trackHeight = 10.0;
  static const _marker = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final facts = this.facts;

    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ExpoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: colors.primary),
            ),
            const SizedBox(height: ExpoSpacing.sm),
            Text(
              loadLabel,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (facts == null) {
      return GestureDetector(
        onTap: onLoad,
        child: Container(
          padding: const EdgeInsets.all(ExpoSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ExpoRadius.md),
            border: Border.all(color: colors.border),
            color: colors.surfaceAlt,
          ),
          child: Row(
            children: [
              Icon(Icons.people_outline,
                  size: 18, color: colors.primary),
              const SizedBox(width: ExpoSpacing.sm),
              Expanded(
                child: Text(
                  prompt,
                  style: TextStyle(
                    fontSize: ExpoType.bodySmall,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Text(
                loadLabel,
                style: TextStyle(
                  fontSize: ExpoType.caption,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (facts.rank == null || facts.size == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ExpoSpacing.md),
        child: Center(
          child: Text(
            emptyLabel,
            style: TextStyle(
              fontSize: ExpoType.bodySmall,
              color: colors.textSecondary,
            ),
          ),
        ),
      );
    }

    final medianPosition = facts.topPoints > 0
        ? ((facts.medianPoints / facts.topPoints) * 100).clamp(0.0, 100.0)
        : 0.0;
    final userPosition = (facts.position ?? 0).clamp(0.0, 100.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headline != null) ...[
          Text(
            headline!,
            style: TextStyle(
              fontSize: ExpoType.h3,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          if (subline != null)
            Text(
              subline!,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
          const SizedBox(height: ExpoSpacing.md),
        ],
        Padding(
          padding: const EdgeInsets.only(
              top: _marker / 2 + 2, bottom: 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth =
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
              return SizedBox(
                height: _trackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: _trackHeight,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ExpoRadius.pill),
                        color: colors.surfaceAlt,
                      ),
                    ),
                    // The fill draws itself in once.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 600),
                      builder: (context, progress, _) {
                        return Container(
                          height: _trackHeight,
                          width: trackWidth *
                              (userPosition / 100) *
                              progress,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                ExpoRadius.pill),
                            color: colors.primary,
                          ),
                        );
                      },
                    ),
                    // The cohort median sits on the same track as a plain
                    // tick — the number that tells the user whether their
                    // position is good, and it costs nothing to draw.
                    Positioned(
                      left: trackWidth * (medianPosition / 100) - 1,
                      top: -3,
                      child: Container(
                        width: 2,
                        height: _trackHeight + 6,
                        color: colors.textSecondary.withValues(alpha: 0.55),
                      ),
                    ),
                    Positioned(
                      left: trackWidth * (userPosition / 100) -
                          _marker / 2,
                      top: -(_marker - _trackHeight) / 2,
                      child: Container(
                        width: _marker,
                        height: _marker,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary,
                          border: Border.all(
                              color: colors.surface, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: ExpoSpacing.md),
        Row(
          children: [
            _Cell(
                label: medianLabel,
                value: '${facts.medianPoints.round()}'),
            const SizedBox(width: ExpoSpacing.sm),
            _Cell(
                label: youLabel,
                value: '${facts.myPoints.round()}',
                accent: true),
            if (facts.pointsToNext != null) ...[
              const SizedBox(width: ExpoSpacing.sm),
              _Cell(
                  label: toNextLabel,
                  value: '+${facts.pointsToNext!.round()}'),
            ],
          ],
        ),
        const SizedBox(height: ExpoSpacing.sm),
        GestureDetector(
          onTap: onOpenBoard,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  boardLabel,
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
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(ExpoSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ExpoRadius.md),
          color: colors.surfaceAlt,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.body,
                fontWeight: FontWeight.w700,
                color: accent ? colors.primary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
