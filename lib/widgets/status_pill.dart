import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Small status/label pill — mirrors src/components/premium/StatusPill.tsx
/// (size "sm"): hairline border, pill radius, 8/3 padding, overline (10px)
/// bold label, optional 11px icon. Colour comes from the tone base colour:
/// soft tinted fill + stronger hairline border, legible in both themes.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill(
      {super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgAlpha = isDark ? 0x26 / 0xFF : 0x14 / 0xFF;
    final borderAlpha = isDark ? 0x55 / 0xFF : 0x33 / 0xFF;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExpoRadius.pill),
        color: color.withValues(alpha: bgAlpha),
        border: Border.all(
            color: color.withValues(alpha: borderAlpha), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: ExpoType.overline,
                fontWeight: FontWeight.w600,
                height: 12 / 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
