import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/widgets/auth/auth_buttons.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';
import '../../services/app_language.dart';

/// Forgot password — worker-backed flow.
/// POSTs the email to the loksewa-push-worker `/request-password-reset`
/// endpoint, then shows the "Check Your Email" state.
/// `rate_limited` / `no_provider` / `account_not_found` answers render as an
/// IN-PAGE info banner above the form (never a popup).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _purple = Color(0xFF7C3AED);
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  /// In-page info/warning banner text shown above the form; null = hidden.
  String? _banner;
  bool _bannerIsWarning = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

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
    final result = await PasswordResetService.requestReset(email);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case PasswordResetResult.sent:
        setState(() => _sent = true);
      case PasswordResetResult.rateLimited:
        setState(() {
          _bannerIsWarning = true;
          _banner = AppLanguage.tr(
            "You've already requested a password reset link today. Please check your email inbox (and spam folder) — the link is valid for 10 minutes. You can request a new link after 24 hours. Still having trouble? Contact Our Loksewa Solution Team.",
            'तपाईंले आज पासवर्ड रिसेट लिङ्क मागिसक्नुभएको छ। इमेल (स्पामसहित) जाँच्नुहोस् — लिङ्क १० मिनेट मान्य हुन्छ। २४ घण्टापछि पुनः प्रयास गर्नुहोस्। सहयोग चाहिएमा Loksewa Solution टिमलाई सम्पर्क गर्नुहोस्।',
          );
        });
      case PasswordResetResult.noProvider:
        setState(() {
          _bannerIsWarning = true;
          _banner = AppLanguage.tr(
            'Email service is not configured yet. Please contact Our Loksewa Solution Team.',
            'इमेल सेवा अहिले उपलब्ध छैन। कृपया Loksewa Solution टिमलाई सम्पर्क गर्नुहोस्।',
          );
        });
      case PasswordResetResult.invalidEmail:
      case PasswordResetResult.failed:
        setState(() {
          _bannerIsWarning = false;
          _banner = AppLanguage.tr(
            'Something went wrong. Please check your connection and try again.',
            'केही गलत भयो। कृपया आफ्नो इन्टरनेट जाँचेर पुनः प्रयास गर्नुहोस्।',
          );
        });
      case PasswordResetResult.accountNotFound:
        setState(() {
          _bannerIsWarning = true;
          _banner = AppLanguage.tr(
            'No account found with this email address.',
            'यो इमेलबाट कुनै खाता फेला परेन।',
          );
        });
    }
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
          label: AppLanguage.tr('Send Reset Link', 'रिसेट लिङ्क पठाउनुहोस्'),
          loading: _loading,
          color: _purple,
          disabledColor: _purple,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _purple),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      key: const ValueKey('sent'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF3E8FF),
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.mail_outline, size: 44, color: _purple),
        ),
        const SizedBox(height: 16),
        Text(
          AppLanguage.tr('Check Your Email', 'आफ्नो इमेल जाँच्नुहोस्'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLanguage.tr(
            "We've sent a password reset link to ${_email.text.trim()}. The link is valid for 10 minutes — tap it to open the app and set a new password.",
            'हामीले ${_email.text.trim()} मा पासवर्ड रिसेट लिङ्क पठाएका छौं। लिङ्क १० मिनेट मान्य हुन्छ — त्यसमा ट्याप गरेर एप खोल्नुहोस् र नयाँ पासवर्ड सेट गर्नुहोस्।',
          ),
          style: const TextStyle(
              fontSize: 15, color: Color(0xFF6B7280), height: 22 / 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        AuthPrimaryButton(
          label: AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
          color: _purple,
          disabledColor: _purple,
          onPressed: () => context.go('/login'),
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
              "Enter your email and we'll send you a secure reset link",
              'आफ्नो इमेल प्रविष्ट गर्नुहोस्, हामी सुरक्षित रिसेट लिङ्क पठाउनेछौं'),
          onBack: () => context.pop(),
          // Flat reset illustration fills the space between header and card
          // (user mockup, 2026-10-10) — compact since the form is tall.
          illustrationAsset: 'assets/images/auth_illust_reset.png',
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
            child: _sent ? _buildSent() : _buildForm(),
          ),
        ),
      ),
    );
  }
}
