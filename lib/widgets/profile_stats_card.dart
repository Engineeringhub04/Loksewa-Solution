import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/charts/chart_math.dart';

/// Profile → the one card that answers "how am I doing, across the whole app?"
///
/// Mirrors `src/components/profile/ProfileStatsCard.tsx`.
///
/// The ring and the points read the SAME stored aggregate the main leaderboard
/// ranks people on (users/{uid}/app_mainleaderboard/{subcourseId}), so the
/// percentage here and the position on the board can never quietly disagree.
/// Rank and streak live only on the mirrored users/{uid}.stats map.
class ProfileStatsCard extends StatefulWidget {
  /// The stored private aggregate, or null when it hasn't been published yet.
  final MainLeaderboardScore? score;

  /// The mirrored headline numbers from users/{uid}.stats. Rank and streak
  /// exist ONLY here — the aggregate above carries neither.
  final UserStats? stats;
  final bool loading;

  /// Shown as the scope chip so the user knows what the score is measured over.
  final String? subcourseName;

  /// Opens the full Analytics page.
  final VoidCallback onPress;

  const ProfileStatsCard({
    super.key,
    required this.score,
    required this.stats,
    required this.loading,
    required this.subcourseName,
    required this.onPress,
  });

  @override
  State<ProfileStatsCard> createState() => _ProfileStatsCardState();
}

class _ProfileStatsCardState extends State<ProfileStatsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _progress;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _progress = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _signature = _computeSignature();
    _c.forward();
  }

  String _computeSignature() {
    final percent = displayCoveragePercent(widget.score?.percent ?? 0);
    // The aggregate is the ONLY source for points. users/{uid}.stats.points
    // is a frozen React-era mirror (the Flutter app never writes it) —
    // falling back to it is exactly the "profile says much more" bug.
    final points = math.max(0, (widget.score?.points ?? 0).round());
    return '$percent:$points';
  }

  @override
  void didUpdateWidget(covariant ProfileStatsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keyed on a signature rather than on `score`, which is a fresh object on
    // every fetch — otherwise the ring would re-sweep on each pull-to-refresh
    // even when nothing changed.
    final sig = _computeSignature();
    if (sig != _signature) {
      _signature = sig;
      _c.reset();
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);

    final percent = displayCoveragePercent(widget.score?.percent ?? 0);

    // Live aggregate first — and ONLY the aggregate. The mirror
    // (users/{uid}.stats.points) is a frozen React-era value the Flutter app
    // never writes; showing it is the "profile says much more than the
    // Analytics hero" bug. Before the first aggregate of a session lands the
    // card honestly shows its loading/empty state instead of a fossil number.
    final points = math.max(0, (widget.score?.points ?? 0).round());
    final tests = (widget.score != null && widget.score!.breakdown.isNotEmpty)
        ? testsTakenOf(widget.score!.breakdown)
        : math.max(0, widget.stats?.testsTaken ?? 0);
    final rank = math.max(0, (widget.stats?.rank ?? 0).round());
    final streak = math.max(0, (widget.stats?.streak ?? 0).round());

    final hasData = points > 0 || (widget.score?.activityCount ?? 0) > 0;

    final percentLabel = percent == percent.roundToDouble()
        ? '${percent.round()}%'
        : '${percent.toStringAsFixed(1)}%';

    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A single accent hairline instead of a gradient wash — the profile
            // header directly above is already a gradient.
            Container(height: 3, color: palette.primary),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Hero: the ring is the card ──
                  Row(
                    children: [
                      SizedBox(
                        width: 66,
                        height: 66,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _progress,
                              builder: (context, _) => CustomPaint(
                                size: const Size(66, 66),
                                painter: _RingPainter(
                                  progress: _progress.value,
                                  percent: percent,
                                  color: palette.primary,
                                  trackColor: palette.surfaceAlt,
                                  dim: !hasData,
                                  dimColor: palette.border,
                                ),
                              ),
                            ),
                            Text(
                              hasData ? percentLabel : '—',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: palette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Labels the RING, not the card.
                            Text(
                              AppLanguage.tr(
                                      'Content covered', 'पुगेको सामग्री')
                                  .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 0.4,
                                color: palette.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    compactNumber(points.toDouble()),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    AppLanguage.tr('Points', 'अंक'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.subcourseName != null &&
                                widget.subcourseName!.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: palette.primary
                                      .withValues(alpha: 0x14 / 0xFF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.school_outlined,
                                        size: 10, color: palette.primary),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        widget.subcourseName!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: palette.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 16, color: palette.primary),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Rank / streak / tests, or the reason there are none ──
                  // Fixed height so the card never resizes when values change.
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasData
                        ? Row(
                            children: [
                              _stripCell(
                                palette,
                                icon: Icons.emoji_events_outlined,
                                tint: palette.warning,
                                value: rank > 0 ? '#$rank' : '—',
                                label: AppLanguage.tr('Rank', 'र्‍याङ्क'),
                              ),
                              _stripCell(
                                palette,
                                icon: Icons.local_fire_department_outlined,
                                tint: palette.danger,
                                value:
                                    compactNumber(streak.toDouble()),
                                label: AppLanguage.tr('Streak', 'स्ट्रिक'),
                                divided: true,
                              ),
                              _stripCell(
                                palette,
                                icon: Icons.description_outlined,
                                tint: palette.info,
                                value: compactNumber(tests.toDouble()),
                                label: AppLanguage.tr('Tests', 'परीक्षा'),
                                divided: true,
                              ),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            child: Row(
                              children: [
                                Icon(Icons.rocket_launch_outlined,
                                    size: 13, color: palette.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.loading && widget.score == null
                                        ? AppLanguage.tr(
                                            'Loading your stats...',
                                            'तथ्याङ्क लोड हुँदैछ...')
                                        : AppLanguage.tr(
                                            'No stats yet — start any activity and they build up',
                                            'अझ तथ्याङ्क छैन — जुनसुकै गतिविधि सुरु गर्नुहोस्, बन्दै जान्छ'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: palette.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

  Widget _stripCell(
    ExpoPalette palette, {
    required IconData icon,
    required Color tint,
    required String value,
    required String label,
    bool divided = false,
  }) {
    return Expanded(
      child: Container(
        decoration: divided
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: palette.divider, width: 0.5),
                ),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: tint),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sweeping arc. Starts at 12 o'clock and runs clockwise.
class _RingPainter extends CustomPainter {
  final double progress;
  final double percent;
  final Color color;
  final Color trackColor;
  final bool dim;
  final Color dimColor;

  const _RingPainter({
    required this.progress,
    required this.percent,
    required this.color,
    required this.trackColor,
    required this.dim,
    required this.dimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * (percent / 100) * progress,
      false,
      Paint()
        ..color = dim ? dimColor : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.percent != percent ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.dim != dim ||
      oldDelegate.dimColor != dimColor;
}
