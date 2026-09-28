import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Terms + Privacy checkbox row — mirrors the renderTerms() blocks in
/// login.tsx / signup.tsx. Red + error text when skipped; the parent drives
/// the shake animation. Links open the in-app terms/privacy screens
/// (which carry the https://www.kbr.com.np/terms and /privacy URLs).
class TermsCheckbox extends StatelessWidget {
  final bool accepted;
  final bool hasError;
  final VoidCallback onToggle;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  const TermsCheckbox({
    super.key,
    required this.accepted,
    required this.hasError,
    required this.onToggle,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    final showError = hasError && !accepted;
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 14, left: 8, right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: showError
                      ? const Color(0xFFDC2626)
                      : accepted
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFFD1D5DB),
                  width: 1.5,
                ),
                color: accepted
                    ? const Color(0xFF1D4ED8)
                    : showError
                        ? const Color(0xFFDC2626).withValues(alpha: 0.08)
                        : null,
              ),
              child: accepted
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 20 / 13,
                    color: showError
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF6B7280),
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms and Conditions',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D4ED8),
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = onOpenTerms,
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D4ED8),
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = onOpenPrivacy,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
