import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/auth/auth_buttons.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';
import 'package:loksewa_solution/widgets/popup_action_button.dart';
import '../../services/app_language.dart';

/// Forgot password — Cloudflare code flow (Round-1 migration).
///
/// Step 1: the email collects a 6-digit code (POST /auth/reset/request).
/// Step 2: code + new password + confirm (POST /auth/reset/verify), then
/// a success popup (AppModalShell) returns the user to login. Request
/// failures render as an IN-PAGE info banner above the form (never a
/// popup) — the same visual language this screen has always used; verify
/// failures use the AppModalShell error popup.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _loading = false;
  bool _verifying = false;
  bool _codeSent = false;

  /// In-page info/warning banner text shown above the form; null = hidden.
  String? _banner;
  bool _bannerIsWarning = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool get _canVerify =>
      _code.text.trim().length == 6 &&
      _password.text.length >= 6 &&
      _confirm.text == _password.text;

  void _showBanner(String text, {bool warning = true}) {
    setState(() {
      _bannerIsWarning = warning;
      _banner = text;
    });
  }

  // ------------------------------------------------------------- step 1
  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      showAuthToast(
          context,
          AppLanguage.tr('Please enter a valid email',
              'कृपया मान्य इमेल प्रविष्ट गर्नुहोस्'),
          isError: true);
      return;
    }
    setState(() {
      _loading = true;
      _banner = null;
    });
    try {
      await AuthService.requestResetCode(email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _codeSent = true;
      });
      _codeFocus.requestFocus();
    } on CfError catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      switch (e.error) {
        case 'account_not_found':
          _showBanner(AppLanguage.tr(
            'No account found with this email address.',
            'यो इमेलबाट कुनै खाता फेला परेन।',
          ));
        case 'too_many_requests':
        case 'rate_limited':
          _showBanner(AppLanguage.tr(
            "You've already requested a code recently. Please check your email inbox (and spam folder) and try again later.",
            'तपाईंले भर्खरै कोड मागिसक्नुभएको छ। इमेल (स्पामसहित) जाँच्नुहोस् र केही समयपछि पुनः प्रयास गर्नुहोस्।',
          ));
        default:
          _showBanner(AppLanguage.tr(
            'Something went wrong. Please check your connection and try again.',
            'केही गलत भयो। कृपया आफ्नो इन्टरनेट जाँचेर पुनः प्रयास गर्नुहोस्।',
          ));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showBanner(AppLanguage.tr(
        'Something went wrong. Please check your connection and try again.',
        'केही गलत भयो। कृपया आफ्नो इन्टरनेट जाँचेर पुनः प्रयास गर्नुहोस्।',
      ));
    }
  }

  // ------------------------------------------------------------- step 2
  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_password.text.length < 6) {
      showAuthToast(
          context,
          AppLanguage.tr('Password must be at least 6 characters.',
              'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ।'),
          isError: true);
      return;
    }
    if (_confirm.text != _password.text) {
      showAuthToast(
          context,
          AppLanguage.tr(
              'Passwords do not match.', 'पासवर्डहरू मेल खाएनन्।'),
          isError: true);
      return;
    }
    setState(() => _verifying = true);
    try {
      await AuthService.resetWithCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      setState(() => _verifying = false);
      await _showSuccessPopup();
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      await _showErrorPopup(e);
    }
  }

  Future<void> _showSuccessPopup() {
    return AppModalShell.show<void>(
      context: context,
      builder: (modalContext) => AppModalShell(
        accent: const Color(0xFF2563EB),
        accentMid: const Color(0xFF3B82F6),
        accentLight: const Color(0xFFBFDBFE),
        tagColor: const Color(0xFF1D4ED8),
        tagLabel: AppLanguage.tr('PASSWORD RESET', 'पासवर्ड रिसेट'),
        onClose: () {
          Navigator.of(modalContext).pop();
          if (mounted) context.go('/login');
        },
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF2563EB),
          ),
          child: const Icon(Icons.check_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Password Reset', 'पासवर्ड रिसेट'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          AppLanguage.tr(
            'Your password has been reset successfully. You can now log in with your new password.',
            'तपाईंको पासवर्ड सफलतापूर्वक रिसेट भयो। अब नयाँ पासवर्डले लगइन गर्नुहोस्।',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: PopupActionButton(
          label: AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
          backgroundColor: const Color(0xFF1D4ED8),
          onTap: () {
            Navigator.of(modalContext).pop();
            if (mounted) context.go('/login');
          },
        ),
      ),
    );
  }

  Future<void> _showErrorPopup(Object e) {
    final isWrongCode = e is CfError && e.error == 'wrong_code';
    return AppModalShell.show<void>(
      context: context,
      builder: (modalContext) => AppModalShell(
        accent: const Color(0xFFDC2626),
        accentMid: const Color(0xFFEF4444),
        accentLight: const Color(0xFFFECACA),
        tagColor: const Color(0xFFDC2626),
        tagLabel: AppLanguage.tr('PASSWORD RESET', 'पासवर्ड रिसेट'),
        onClose: () => Navigator.of(modalContext).pop(),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFDC2626),
          ),
          child: const Icon(Icons.lock_reset_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Password Reset', 'पासवर्ड रिसेट'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          isWrongCode
              ? AppLanguage.tr(
                  'That code is incorrect or has expired. Please check the code and try again.',
                  'यो कोड मिलेन वा म्याद सकियो। कोड जाँचेर पुनः प्रयास गर्नुहोस्।',
                )
              : AppLanguage.tr(
                  'Something went wrong. Please check your connection and try again.',
                  'केही गलत भयो। कृपया आफ्नो इन्टरनेट जाँचेर पुनः प्रयास गर्नुहोस्।',
                ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: PopupActionButton(
          label: AppLanguage.tr('OK', 'ठीक छ'),
          backgroundColor: const Color(0xFF1D4ED8),
          onTap: () => Navigator.of(modalContext).pop(),
        ),
      ),
    );
  }

  /// In-page info/warning banner — rendered above the form, never a popup.
  Widget _buildBanner() {
    if (_banner == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bannerIsWarning
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFEFF6FF),
        border: Border.all(
          color: _bannerIsWarning
              ? const Color(0xFFFBBF24)
              : const Color(0xFF93C5FD),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _bannerIsWarning ? Icons.info_outline : Icons.error_outline,
            color: _bannerIsWarning
                ? const Color(0xFFB45309)
                : const Color(0xFF1D4ED8),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _banner!,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF374151), height: 20 / 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBanner(),
        FloatingLabelField(
          label: AppLanguage.tr('Email Address', 'इमेल ठेगाना'),
          controller: _email,
          leftIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: AppLanguage.tr('Send Code', 'कोड पठाउनुहोस्'),
          loading: _loading,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLanguage.tr('Enter Code', 'कोड प्रविष्ट गर्नुहोस्'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLanguage.tr(
            "We've sent a 6-digit code to ${_email.text.trim()}. Enter it below with your new password.",
            'हामीले ${_email.text.trim()} मा ६ अंकको कोड पठाएका छौं। तल कोड र नयाँ पासवर्ड प्रविष्ट गर्नुहोस्।',
          ),
          style: const TextStyle(
              fontSize: 15, color: Color(0xFF6B7280), height: 22 / 15),
        ),
        const SizedBox(height: 20),
        FloatingLabelField(
          label: AppLanguage.tr('Verification Code', 'प्रमाणीकरण कोड'),
          controller: _code,
          focusNode: _codeFocus,
          leftIcon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          nextFocus: _passwordFocus,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        FloatingLabelField(
          label: AppLanguage.tr('New Password', 'नयाँ पासवर्ड'),
          controller: _password,
          focusNode: _passwordFocus,
          leftIcon: Icons.lock_outline,
          secureToggle: true,
          obscureText: true,
          textInputAction: TextInputAction.next,
          nextFocus: _confirmFocus,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        FloatingLabelField(
          label: AppLanguage.tr('Confirm Password', 'पासवर्ड पुष्टि गर्नुहोस्'),
          controller: _confirm,
          focusNode: _confirmFocus,
          leftIcon: Icons.lock_outline,
          secureToggle: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: _verify,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: AppLanguage.tr('Reset Password', 'पासवर्ड रिसेट गर्नुहोस्'),
          loading: _verifying,
          enabled: _canVerify,
          onPressed: _verify,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _submit,
            child: Text(
              AppLanguage.tr('Resend Code', 'कोड पुनः पठाउनुहोस्'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8)),
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: Text(
              AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Transparent status bar with dark icons so the light background flows
    // under the clock — same edge-to-edge treatment as home pages; kills
    // the dark band that used to sit above this screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: AuthScreenLayout(
          title: AppLanguage.tr('Reset Password', 'पासवर्ड रिसेट'),
          subtitle: AppLanguage.tr(
              "Enter your email and we'll send you a 6-digit code",
              'आफ्नो इमेल प्रविष्ट गर्नुहोस्, हामी ६ अंकको कोड पठाउनेछौं'),
          onBack: () => context.pop(),
          // Flat reset illustration fills the space between header and card
          // (user mockup, 2026-10-10) — compact since the form is tall.
          // Hidden once the code step shows (same rule as the old "sent"
          // state); kept on error/banner states.
          illustrationAsset: _codeSent ? null : 'assets/images/auth_illust_reset.png',
          illustrationHeight: 150,
          // The form shows instantly — no preloading shimmer (user asked
          // for direct display on 2026-10-10).
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _codeSent ? _buildCodeStep() : _buildForm(),
          ),
        ),
      ),
    );
  }
}
