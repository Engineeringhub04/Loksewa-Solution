import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../status_pill.dart';
import 'notice_visual.dart';

/// Premium notice card — mirrors src/components/home/PremiumNoticeCard.tsx.
///
/// Used by BOTH Home's "Recent Notices" section and the full Notices list:
/// 4px accent spine (a 24px nub at rest), kind-tinted 38px icon tile,
/// title (bodySmall bold, 2 lines) + optional excerpt (caption, 2 lines),
/// kind + date pills, chevron. Pressed: surface swaps to surfaceAlt and the
/// border picks up the tone colour.
class NoticeCard extends StatefulWidget {
  final String title;
  final String date;
  final String? kind;
  final String? description;
  final VoidCallback onPress;

  const NoticeCard({
    super.key,
    required this.title,
    required this.date,
    this.kind,
    this.description,
    required this.onPress,
  });

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final v = noticeVisual(widget.kind, palette);
    final isPressed = _pressed;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPress,
      child: Container(
        padding: const EdgeInsets.all(16).copyWith(left: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ExpoRadius.lg),
          color: isPressed ? palette.surfaceAlt : palette.surface,
          border: Border.all(
            color: isPressed
                ? v.color.withValues(alpha: 0x55 / 0xFF)
                : palette.divider,
            width: 0.5,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          children: [
            // Accent spine nub on the left edge: a 24px nub at rest that
            // grows from the centre upward and downward while pressed —
            // mirrors the reanimated scaleY in PremiumNoticeCard.
            Positioned(
              left: -22,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 4,
                  height: isPressed ? 56 : 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: v.color,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(ExpoRadius.md),
                    color: v.color.withValues(
                        alpha: (isDark ? 0x26 : 0x14) / 0xFF),
                    border: Border.all(
                      color: v.color.withValues(
                          alpha: (isDark ? 0x55 : 0x33) / 0xFF),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(v.icon, size: 18, color: v.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: ExpoType.bodySmall,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.description != null &&
                          widget.description!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.description!,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: ExpoType.caption,
                            height: 17 / 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusPill(label: v.label, color: v.color),
                          // Always rendered — the Expo card never hides the
                          // date pill (the ne-NP publishedAt fallback means it
                          // is only ever empty when publishedAt is missing).
                          StatusPill(
                            label: widget.date,
                            color: palette.textSecondary,
                            icon: Icons.access_time,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: palette.textDisabled),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
