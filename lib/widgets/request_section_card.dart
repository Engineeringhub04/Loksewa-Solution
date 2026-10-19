// Shared section card for request detail pages — copied exactly from
// subscription_detail_screen.dart's _SectionCard so exam/content purchase
// request pages render sections (timeline, problem, summary, receipt)
// same-to-same with the subscription page.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RequestSectionCard extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String title;
  final Widget? trailing;
  final Widget child;

  const RequestSectionCard({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0x1F / 0xFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: ExpoType.body, fontWeight: FontWeight.bold),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: ExpoSpacing.md),
          child,
        ],
      ),
    );
  }
}
