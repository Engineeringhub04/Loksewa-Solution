// Shared "payment verification pending" banner — copied exactly from
// subscription_detail_screen.dart's _VerificationPendingBanner. Shown under
// the crown when a gateway payment is pending and needs recovery.
import 'package:flutter/material.dart';

import '../services/app_language.dart';
import '../theme/app_theme.dart';

class VerificationPendingBanner extends StatelessWidget {
  const VerificationPendingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pal.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
        border: Border.all(color: pal.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: pal.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLanguage.tr(
                'Payment Verification Pending! Pls Contact Admin',
                'भुक्तानी प्रमाणीकरण बाँकी छ! कृपया Admin लाई सम्पर्क गर्नुहोस्',
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: pal.warning,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
