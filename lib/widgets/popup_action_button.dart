// Shared popup action button — Report-dialog pattern.
// The button KEEPS its background color during loading (never fades to
// Flutter's disabled grey); only a white spinner replaces the label.
// This fixes the "white/faded buttons" seen in logout/delete popups.
import 'package:flutter/material.dart';

class PopupActionButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool loading;
  final VoidCallback? onTap;

  const PopupActionButton({
    super.key,
    required this.label,
    required this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Never visually disabled — taps are just ignored while loading.
        onTap: loading ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: foregroundColor,
                    decoration: TextDecoration.none,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Secondary/cancel button for popups — fixed dark text on transparent
/// background (card is always white, so this stays visible in dark mode).
class PopupCancelButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const PopupCancelButton({
    super.key,
    required this.label,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: loading ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
