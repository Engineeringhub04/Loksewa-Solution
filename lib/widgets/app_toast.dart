import 'package:flutter/material.dart';

/// Global toast helper — mirrors ToastHost.tsx / toastStore.ts (PRD §8.4).
///
/// Floating rounded card filled with the variant color
/// (success #16A34A, error #DC2626, warning #D97706, info #2563EB),
/// white icon + white semibold message + dismiss button,
/// auto-dismisses after 3 seconds, floats above the bottom edge.
///
/// Call `showToast(context, 'message', ToastVariant.success)` from anywhere.
enum ToastVariant { success, error, warning, info }

Color _bgFor(ToastVariant v) => switch (v) {
      ToastVariant.success => const Color(0xFF16A34A),
      ToastVariant.error => const Color(0xFFDC2626),
      ToastVariant.warning => const Color(0xFFD97706),
      ToastVariant.info => const Color(0xFF2563EB),
    };

IconData _iconFor(ToastVariant v) => switch (v) {
      ToastVariant.success => Icons.check_circle,
      ToastVariant.error => Icons.cancel,
      ToastVariant.warning => Icons.warning,
      ToastVariant.info => Icons.info,
    };

void showToast(
  BuildContext context,
  String message, [
  ToastVariant variant = ToastVariant.info,
]) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(_iconFor(variant), size: 22, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: messenger.hideCurrentSnackBar,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 18, color: Color(0xD9FFFFFF)),
            ),
          ),
        ],
      ),
      backgroundColor: _bgFor(variant),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 6,
      duration: const Duration(seconds: 3),
    ),
  );
}
