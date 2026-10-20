// Shared info row for the request Payment Summary card.
// Layout: [icon] [fixed-width BOLD label] [value column].
// The fixed label width keeps every value starting at the SAME x, and the
// value's own column gives wrapped lines a hanging indent (2nd+ lines start
// directly under the 1st line's start) — no more unstable right-aligned text.
// Text emphasis rule: the label is BOLD, the value stays regular weight;
// only the Payment Method value gets extra colour (see requestMethodColor).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_language.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// Accent colour for the Payment Summary "Payment Method" value: eSewa
/// green, Khalti red, Manual QR app blue. Applies to the method NAME only —
/// the Platform row keeps its default colour.
Color requestMethodColor(BuildContext context, String method) {
  final pal = ExpoPalette.of(context);
  switch (method.toLowerCase()) {
    case 'esewa':
      return pal.success;
    case 'khalti':
      return pal.danger;
    default:
      return pal.primary;
  }
}

/// Copy-enabled Reference value for the summary card.
///
/// Behaves like every other value: it starts at the SAME left x as all
/// other rows' values (the row's fixed label width guarantees that) and
/// the copy icon sits immediately AFTER the value text, inside the value
/// column — never pushed to the right edge.
class RequestReferenceValue extends StatelessWidget {
  final String? ref;
  const RequestReferenceValue({super.key, required this.ref});

  @override
  Widget build(BuildContext context) {
    final value = (ref ?? '').trim();
    if (value.isEmpty) return const Text('—');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            showToast(
              context,
              AppLanguage.tr('Reference copied', 'सन्दर्भ प्रतिलिपि भयो'),
              ToastVariant.success,
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.copy_outlined,
                size: 15, color: ExpoPalette.of(context).textSecondary),
          ),
        ),
      ],
    );
  }
}

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
