// PremiumGateDialog — dedicated premium-subscription gate popup.
//
// Mirrors src/components/feedback/PremiumGateDialog.tsx: three screens
// (subjects, units, chapters) each had a hand-rolled copy of the same
// Modal — the same amber accent, the same lock-then-diamond icon, the same
// button layout. The look is extracted here once so only the i18n copy
// differs per screen.
//
// This component owns: tone (warning #D97706 — React's ConfirmDialog
// TONE_ACCENT.warning), icon (diamond), confirmIcon (arrow-forward).
// It does NOT own the copy — titles, messages, and button labels arrive as
// props so each screen keeps its own i18n pairs exactly as they are.
//
// Optional "buy this content separately" action: when [buyLabel]/[onBuy]
// are provided, a primary "Buy This Content" CTA is rendered above the
// subscription button — the locked item can be purchased individually
// (checkout?contentId=...) without a subscription.
//
// Rendered as a full-screen dim overlay containing the shared AppModalShell
// card, so existing Stack-overlay call sites (which keep the gate above the
// header curve) can swap their private copies for this with no layout
// changes.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

class PremiumGateDialog extends StatelessWidget {
  final String title;
  final String? message;

  /// The locked item's display name (subject, unit, or chapter) shown as a
  /// pill subtitle — React's `itemName` → ConfirmDialog `subtitle`.
  final String? itemName;
  final String confirmLabel;
  final String? cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  /// Optional separate-purchase action ("Buy This Content"). When null the
  /// dialog renders the classic two-button (subscription / close) layout.
  final String? buyLabel;
  final VoidCallback? onBuy;

  const PremiumGateDialog({
    super.key,
    required this.title,
    this.message,
    this.itemName,
    required this.confirmLabel,
    this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.buyLabel,
    this.onBuy,
  });

  // React ConfirmDialog TONE_ACCENT.warning.
  static const _accent = Color(0xFFD97706);
  static const _accentDark = Color(0xFFB45309);
  static const _accentMid = Color(0xFFF59E0B);
  static const _accentLight = Color(0xFFFDE9C8);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);

  Widget _gradientButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [_accent, _accentDark],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_forward,
                    size: 17,
                    color: _accentDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _accent.withValues(alpha: 0.55), width: 1.5),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: _accentDark,
                decoration: TextDecoration.none),
          ),
        ),
      ),
    );
  }

  Widget _ghostButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _grey,
            decoration: TextDecoration.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBuy = buyLabel != null && onBuy != null;
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: AppModalShell(
          maxWidth: 340,
          borderRadius: 28,
          accent: _accent,
          accentMid: _accentMid,
          accentLight: _accentLight,
          tagColor: _accent,
          onClose: onCancel,
          icon: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [_accentMid, _accentDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.diamond, size: 28, color: Colors.white),
          ),
          tagLabel: AppLanguage.tr('PREMIUM', 'प्रिमियम'),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _navy,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null && message!.isNotEmpty)
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: _grey,
                    decoration: TextDecoration.none,
                  ),
                ),
              // Locked item as a pill — the premium touch that names exactly
              // what the user would unlock.
              if (itemName != null && itemName!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _accentLight,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: _accent.withValues(alpha: 0.35), width: 1),
                    ),
                    child: Text(
                      itemName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasBuy) ...[
                // Primary: buy this content separately.
                _gradientButton(label: buyLabel!, onTap: onBuy!),
                const SizedBox(height: 10),
                // Secondary: subscription plan.
                _outlineButton(label: confirmLabel, onTap: onConfirm),
                const SizedBox(height: 4),
                if (cancelLabel != null)
                  _ghostButton(label: cancelLabel!, onTap: onCancel),
              ] else ...[
                // Classic two-button layout (unchanged).
                if (cancelLabel != null) ...[
                  _outlineButton(label: cancelLabel!, onTap: onCancel),
                  const SizedBox(height: 10),
                ],
                _gradientButton(label: confirmLabel, onTap: onConfirm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
