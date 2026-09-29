import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// "Daily challenge" gradient card (mirrors QuestionOfDayCard.tsx).
enum QotdCardStatus { loading, live, completed, empty }

class QuestionOfDayCard extends StatefulWidget {
  final QotdCardStatus status;
  final VoidCallback onPress;

  const QuestionOfDayCard({
    super.key,
    required this.status,
    required this.onPress,
  });

  @override
  State<QuestionOfDayCard> createState() => _QuestionOfDayCardState();
}

class _QuestionOfDayCardState extends State<QuestionOfDayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.status == QotdCardStatus.live) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(QuestionOfDayCard old) {
    super.didUpdateWidget(old);
    if (widget.status == QotdCardStatus.live && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (widget.status != QotdCardStatus.live && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.status == QotdCardStatus.completed;
    final empty = widget.status == QotdCardStatus.empty;
    final live = widget.status == QotdCardStatus.live;

    final label = done
        ? 'COMPLETED'
        : empty
            ? 'NO QUESTION'
            : widget.status == QotdCardStatus.loading
                ? 'LOADING'
                : 'LIVE';
    final subtitle = done
        ? 'Today\u2019s challenge is complete. See you tomorrow.'
        : empty
            ? 'No question is scheduled for your course today.'
            : 'Your daily knowledge challenge is ready.';
    final accent = done
        ? const Color(0xFF4ADE80)
        : empty
            ? const Color(0xFF94A3B8)
            : const Color(0xFFFF6B6B);

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 18),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        child: InkWell(
          onTap: widget.onPress,
          borderRadius: BorderRadius.circular(ExpoRadius.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ExpoRadius.lg),
            child: Container(
            constraints: const BoxConstraints(minHeight: 154),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
              gradient: const LinearGradient(
                colors: [Color(0xFF0B1F51), Color(0xFF143B8F), Color(0xFF2257C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x521D4ED8),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Glow circles.
                Positioned(
                  right: -42,
                  top: -70,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF60A5FA).withValues(alpha: 0.18),
                    ),
                  ),
                ),
                Positioned(
                  left: -28,
                  bottom: -48,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                // Content fills the card; React's padding applied here.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 12, color: Color(0xFF93C5FD)),
                            SizedBox(width: 6),
                            Text(
                              'DAILY CHALLENGE',
                              style: TextStyle(
                                color: Color(0xFFBFDBFE),
                                fontSize: ExpoType.overline,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: live
                                ? const Color(0x577F1D1D)
                                : const Color(0x5707122E),
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.1)),
                            boxShadow: live
                                ? const [
                                    BoxShadow(
                                      color: Color(0xE6EF4444),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: live
                                    ? Tween(begin: 1.0, end: 0.35)
                                        .animate(_pulse)
                                    : const AlwaysStoppedAnimation(1.0),
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: accent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: ExpoType.overline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white.withValues(alpha: 0.14),
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Icon(
                            done
                                ? Icons.check
                                : empty
                                    ? Icons.calendar_today_outlined
                                    : Icons.lightbulb_outline,
                            size: 25,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Question of the Day',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: const Color(0xFFEFF6FF)
                                      .withValues(alpha: 0.78),
                                  fontSize: ExpoType.bodySmall,
                                  height: 18 / 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          child: const Icon(Icons.arrow_forward,
                              size: 17, color: Color(0xFFDBEAFE)),
                        ),
                      ],
                    ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
