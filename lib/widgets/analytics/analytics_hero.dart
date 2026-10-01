import 'package:flutter/material.dart';

import 'analytics_shared.dart';

/// The page's identity card: which subcourse these numbers describe, how far
/// along it is, and the three figures worth checking first.
///
/// Mirrors AnalyticsHero.tsx: fixed blue gradient (#2563EB → #1D4ED8 →
/// #0B1F5B, radius 24), an offset white glow blob, a 56px translucent
/// school-icon box, course/subcourse names, a LIVE animated progress ring on
/// the right, and a bottom inner strip (PTS · Rank/Active days · Streak).
///
/// This is the single place on the screen that does NOT follow the app theme.
/// The gradient is fixed, so everything drawn on it is fixed white too.
class AnalyticsHero extends StatelessWidget {
  const AnalyticsHero({
    super.key,
    required this.courseName,
    required this.subcourseName,
    required this.percent,
    required this.points,
    required this.streak,
    required this.activeDays,
    this.rank,
    this.switchable = false,
    this.onPress,
  });

  final String courseName;
  final String subcourseName;

  /// 0..100 — the weighted score the leaderboard ranks on.
  final double percent;
  final int points;

  /// Current streak in days.
  final int streak;

  /// Days with real work inside the selected window.
  final int activeDays;

  /// Only known once the cohort section has been opened. Until then the middle
  /// cell shows active days rather than a placeholder — a dash where a rank
  /// belongs reads as "unranked", which would be wrong.
  final int? rank;

  /// Shows the switch affordance; the card is only tappable when true.
  final bool switchable;
  final VoidCallback? onPress;

  static const _onBlue = Colors.white;
  static const _onBlueDim = Color(0xBDFFFFFF); // rgba(255,255,255,0.74)

  @override
  Widget build(BuildContext context) {
    final interactive = switchable && onPress != null;

    final body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0B1F5B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x591D4ED8),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(18),
      child: Stack(
        children: [
          // Offset white glow blob.
          const Positioned(
            top: -30,
            right: -20,
            child: SizedBox(
              width: 120,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x1FFFFFFF),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: const Color(0x2EFFFFFF),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.school,
                        size: 26, color: _onBlue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This period',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.3,
                            color: _onBlueDim,
                          ),
                        ),
                        Text(
                          courseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _onBlue,
                          ),
                        ),
                        // The switch affordance sits inline with the subcourse
                        // name rather than in a corner chip: the card's
                        // top-right corner belongs to the ring.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                subcourseName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _onBlueDim,
                                ),
                              ),
                            ),
                            if (interactive) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.swap_horiz,
                                  size: 14, color: _onBlueDim),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _HeroRing(percent: percent),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      _StripCell(
                          value: formatCount(points), label: 'Points'),
                      const _StripDivider(),
                      if (rank != null)
                        _StripCell(value: '#$rank', label: 'Rank')
                      else
                        _StripCell(
                            value: formatCount(activeDays),
                            label: 'Active days'),
                      const _StripDivider(),
                      _StripCell(
                        value: formatCount(streak),
                        label: 'Day streak',
                        icon: Icons.local_fire_department,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!interactive) return body;
    return GestureDetector(
      onTap: onPress,
      child: body,
    );
  }
}

class _StripCell extends StatelessWidget {
  const _StripCell({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: const Color(0xFFFDBA74)),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, color: AnalyticsHero._onBlueDim),
          ),
        ],
      ),
    );
  }
}

class _StripDivider extends StatelessWidget {
  const _StripDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: const Color(0x47FFFFFF),
    );
  }
}

/// A local ring rather than a shared progress-ring widget: the track and label
/// colours are fixed white-on-blue, which a theme-driven component cannot do.
///
/// One-shot draw-in, keyed on the percentage itself: switching subcourse
/// redraws the ring; a parent re-render for any other reason does not.
class _HeroRing extends StatelessWidget {
  const _HeroRing({required this.percent});

  final double percent;

  static const _size = 62.0;

  @override
  Widget build(BuildContext context) {
    final ratio =
        ((percent.isFinite ? percent : 0.0).clamp(0.0, 100.0)) / 100.0;
    return TweenAnimationBuilder<double>(
      // A new key recreates the tween state, so only a changed percentage
      // replays the draw-in.
      key: ValueKey<double>(ratio),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, progress, _) {
        return SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(_size, _size),
                painter: _RingPainter(progress: ratio * progress),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 5) / 2;
    const stroke = 5.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x3DFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.141592653589793 / 2,
        2 * 3.141592653589793 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
