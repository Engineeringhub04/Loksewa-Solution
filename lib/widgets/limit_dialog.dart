// Practice limit / generic app dialog card — FeedSpring-style redesign.
// White card in BOTH light and dark mode (the design is inherently light):
// orange gradient header fading down to white, centered icon tile, white
// tagline pill, navy title, grey body, stacked white Cancel + orange gradient
// CTA buttons. Shell extracted to AppModalShell. Used by
// subject_practice_screen.dart (_appDialog) and additional_topic_screen.dart
// (_limitDialog).
//
// NOTE: every Text in this dialog carries an explicit
// `decoration: TextDecoration.none` as a defensive guard.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

class LimitDialogCard extends StatelessWidget {
  final String tagline;
  final String title;
  final String message;
  final Widget? bodyExtra;
  final IconData icon;
  final String confirmLabel;
  final IconData? confirmIcon;
  final String? cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const LimitDialogCard({
    super.key,
    required this.tagline,
    required this.title,
    required this.message,
    this.bodyExtra,
    required this.icon,
    required this.confirmLabel,
    this.confirmIcon,
    this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  static const _orange = Color(0xFFDE6E00);
  static const _orangeDark = Color(0xFFB45300);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      maxWidth: 340,
      borderRadius: 30,
      accent: _orange,
      accentMid: const Color(0xFFF59E0B),
      accentLight: const Color(0xFFFCD9A8),
      tagColor: _orange,
      onClose: onCancel,
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: _orange,
          boxShadow: [
            BoxShadow(
              color: _orange.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(icon, size: 28, color: Colors.white),
      ),
      tagLabel: tagline,
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
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: _grey,
              decoration: TextDecoration.none,
            ),
          ),
          if (bodyExtra != null) ...[
            const SizedBox(height: 10),
            bodyExtra!,
          ],
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cancel first — white, light slate border.
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
          // Confirm second — orange gradient CTA.
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
                    colors: [_orange, _orangeDark],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _orange.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    if (confirmIcon != null) ...[
                      Icon(confirmIcon, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                    ],
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
                    // Clean circular white badge with a centered arrow.
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
                          color: _orangeDark,
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
    );
  }
}
