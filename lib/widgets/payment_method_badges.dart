// "Accepted Payments" strip shown on the Subscription page — eSewa, Khalti,
// Fonepay as transparent text-only badges (no third-party logo assets are
// bundled, to avoid shipping trademarked artwork; each brand's own colour is
// used for recognizability instead).
//
// Mirrors `src/components/subscription/PaymentMethodBadges.tsx`.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

class _Brand {
  final String label;
  final Color color;
  const _Brand(this.label, this.color);
}

const _brands = [
  _Brand('eSewa', Color(0xFF60BB46)),
  _Brand('Khalti', Color(0xFF5C2D91)),
  _Brand('Fonepay', Color(0xFFEE3237)),
];

/// Accepted-payment-methods badge strip. [settings] is accepted for API
/// parity with the React original (which currently ignores it too) and is
/// reserved for future per-method gating.
class PaymentMethodBadges extends StatelessWidget {
  final Map<String, dynamic>? settings;
  const PaymentMethodBadges({super.key, this.settings});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLanguage.tr(
              'Accepted payment methods', 'स्वीकार गरिने भुक्तानी विधि'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: pal.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final brand in _brands)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: brand.color, width: 1.5),
                  borderRadius: BorderRadius.circular(ExpoRadius.pill),
                  color: brand.color.withValues(alpha: 0x12 / 0xFF),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: brand.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      brand.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: brand.color,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
