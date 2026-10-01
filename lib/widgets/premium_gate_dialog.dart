// PremiumGateDialog — dedicated premium-subscription gate popup.
//
// Mirrors src/components/feedback/PremiumGateDialog.tsx: three screens
// (subjects, units, chapters) each had a hand-rolled copy of the same
// Modal — the same amber accent, the same lock-then-diamond icon, the same
// two-button layout. The look is extracted here once so only the i18n copy
// differs per screen.
//
// This component owns: tone (warning #D97706 — React's ConfirmDialog
// TONE_ACCENT.warning), icon (diamond), confirmIcon (arrow-forward).
// It does NOT own the copy — titles, messages, and button labels arrive as
// props so each screen keeps its own i18n pairs exactly as they are.
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
  /// bold subtitle — React's `itemName` → ConfirmDialog `subtitle`.
  final String? itemName;
  final String confirmLabel;
  final String? cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const PremiumGateDialog({
    super.key,
    required this.title,
    this.message,
    this.itemName,
    required this.confirmLabel,
    this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  // React ConfirmDialog TONE_ACCENT.warning.
  static const _accent = Color(0xFFD97706);
  static const _accentDark = Color(0xFFB45309);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: AppModalShell(
          maxWidth: 340,
          borderRadius: 28,
          accent: _accent,
          accentMid: const Color(0xFFF59E0B),
          accentLight: const Color(0xFFFDE9C8),
          tagColor: _accent,
          onClose: onCancel,
          icon: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: _accent,
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
              if (itemName != null && itemName!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  itemName!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ],
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cancel first (ghost) — matches React AppDialog footer order.
              if (cancelLabel != null) ...[
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 1.5),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        cancelLabel!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                            decoration: TextDecoration.none),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Confirm second — amber gradient CTA with the arrow-forward
              // badge (React confirmIcon="arrow-forward").
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onConfirm,
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
                            confirmLabel,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
