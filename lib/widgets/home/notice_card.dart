import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Premium notice card (mirrors PremiumNoticeCard.tsx, static edition):
/// accent spine, kind-tinted icon tile, title + excerpt, kind + date pills.
class NoticeCard extends StatelessWidget {
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

  _NoticeVisual get _visual {
    switch (kind) {
      case 'feature':
        return const _NoticeVisual(
            Icons.auto_awesome, Color(0xFF7C3AED), 'New');
      case 'update':
        return const _NoticeVisual(
            Icons.cloud_download_outlined, Color(0xFF3B82F6), 'Update');
      case 'maintenance':
        return const _NoticeVisual(
            Icons.build_outlined, Color(0xFFF59E0B), 'Maintenance');
      case 'exam':
        return const _NoticeVisual(
            Icons.calendar_today_outlined, Color(0xFFEF4444), 'Exam');
      case 'welcome':
        return const _NoticeVisual(
            Icons.waving_hand_outlined, Color(0xFF22C55E), 'Welcome');
      default:
        return const _NoticeVisual(
            Icons.campaign_outlined, Color(0xFF1D4ED8), 'Notice');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final v = _visual;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(ExpoRadius.lg),
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(16).copyWith(left: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ExpoRadius.lg),
            border: Border.all(color: palette.divider, width: 0.5),
          ),
          child: Stack(
            children: [
              // Accent spine nub (left edge).
              Positioned(
                left: -16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 4,
                    height: 24,
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
                      color: v.color.withValues(alpha: 0.12),
                      border: Border.all(
                        color: v.color.withValues(alpha: 0.3),
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
                          title,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: ExpoType.bodySmall,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (description != null &&
                            description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            description!,
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
                            _Pill(
                                label: v.label,
                                color: v.color,
                                palette: palette),
                            if (date.isNotEmpty)
                              _Pill(
                                label: date,
                                color: palette.textSecondary,
                                palette: palette,
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
      ),
    );
  }
}

class _NoticeVisual {
  final IconData icon;
  final Color color;
  final String label;
  const _NoticeVisual(this.icon, this.color, this.label);
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final ExpoPalette palette;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.color,
    required this.palette,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.1),
        border:
            Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
