// Shared info row for the request Payment Summary card — copied exactly
// from subscription_detail_screen.dart's _InfoRow (icon + label + value
// with hairline dividers).
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RequestInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final Color? tone;
  final bool stacked;
  final bool last;

  const RequestInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
    this.stacked = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final iconColor = tone ?? pal.textSecondary;
    final content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: ExpoType.caption, color: pal.textSecondary)),
              const SizedBox(height: 4),
              value,
            ],
          )
        : Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: ExpoType.bodySmall,
                        color: pal.textSecondary)),
              ),
              Flexible(
                child: DefaultTextStyle(
                  style: TextStyle(
                      fontSize: ExpoType.bodySmall, color: pal.textPrimary),
                  textAlign: TextAlign.end,
                  child: value,
                ),
              ),
            ],
          );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: last ? Colors.transparent : pal.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: content),
        ],
      ),
    );
  }
}
