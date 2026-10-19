// Shared info row for the request Payment Summary card.
// Layout: [icon] [fixed-width BOLD label] [value column].
// The fixed label width keeps every value starting at the SAME x, and the
// value's own column gives wrapped lines a hanging indent (2nd+ lines start
// directly under the 1st line's start) — no more unstable right-aligned text.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RequestInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final Color? tone;
  final bool stacked;
  final bool last;

  /// Fixed width of the label column — every value starts at the same x.
  /// Wide enough for "Payment Method" / "भुक्तानी विधि" in bold; longer
  /// labels wrap to two lines inside it without moving the value column.
  static const double labelWidth = 128;

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
    final labelStyle = TextStyle(
      fontSize: ExpoType.bodySmall,
      fontWeight: FontWeight.w700,
      color: pal.textPrimary,
    );
    final content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(height: 4),
              value,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(label, style: labelStyle, maxLines: 2),
              ),
              const SizedBox(width: 10),
              Expanded(child: value),
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
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: content),
        ],
      ),
    );
  }
}
