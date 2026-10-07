import 'package:flutter/material.dart';
import '../app_toast.dart';
import 'google_icon.dart';

/// Shared auth buttons + divider + toast helper — mirrors the styles in
/// login.tsx / signup.tsx / forgot-password.tsx.

/// Backwards-compatible auth toast: delegates to the global [showToast]
/// (Expo ToastHost design). Same signature, so all call sites keep working.
void showAuthToast(BuildContext context, String message,
    {bool isError = false}) {
  showToast(
      context, message, isError ? ToastVariant.error : ToastVariant.info);
}

/// White "Continue with Google" button with the multi-color G.
class AuthGoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const AuthGoogleButton(
      {super.key, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF374151),
          disabledBackgroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF374151)),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoogleIcon(size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "or" divider with lines on both sides.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      width: double.infinity,
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFE5E7EB), height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFE5E7EB), height: 1)),
        ],
      ),
    );
  }
}

/// Primary filled button (blue #1D4ED8 or purple #7C3AED).
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool enabled;
  final Color color;
  final Color disabledColor;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.enabled = true,
    this.color = const Color(0xFF1D4ED8),
    this.disabledColor = const Color(0xFF93B4F3),
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: active ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? color : disabledColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledColor,
          disabledForegroundColor: Colors.white,
          elevation: active ? 4 : 0,
          shadowColor: color.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

/// "Continue with Email" blue button with mail icon.
class AuthEmailButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AuthEmailButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1D4ED8),
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: const Color(0xFF1D4ED8).withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Continue with Email',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom "Don't have an account? Sign Up" style link row.
class AuthBottomLink extends StatelessWidget {
  final String prefix;
  final String linkText;
  final VoidCallback onTap;

  const AuthBottomLink({
    super.key,
    required this.prefix,
    required this.linkText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prefix,
              style:
                  const TextStyle(fontSize: 15, color: Color(0xFF6B7280))),
          GestureDetector(
            onTap: onTap,
            child: Text(
              linkText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
