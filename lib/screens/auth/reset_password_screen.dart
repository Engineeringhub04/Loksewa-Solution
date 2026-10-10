import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/widgets/auth/auth_buttons.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';
import '../../services/app_language.dart';
import '../../widgets/preloading.dart';

/// In-app password reset completion.
/// Served at `/auth/reset-password` — the router redirects here without a
/// `token` back to `/`, so this screen always has a token to attempt.
/// The token is completed server-side: the screen POSTs it to the
/// loksewa-push-worker (`/complete-password-reset`), which validates the
/// one-time token and updates the password via the Firebase Admin SDK
/// (see [PasswordResetService.completeReset]). The app never touches
/// Identity Toolkit directly.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _ResetStatus { form, success, error }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _purple = Color(0xFF7C3AED);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _loading = false;
  bool _preloading = true;
  _ResetStatus _status = _ResetStatus.form;
  // Dynamic error copy: invalid/expired links get the "request a new link"
  // hint, transport/server failures get the generic retry message.
  String? _errorTitle;
  String? _errorHint;

  @override
  void initState() {
    super.initState();
    // 1s premium preloading shimmer: shown before the form so the page
    // doesn't pop in instantly — same treatment as the other auth screens.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String? get _token {
    final token = GoRouterState.of(context).uri.queryParameters['token'];
    return (token == null || token.isEmpty) ? null : token;
  }

  void _showLinkError() {
    _errorTitle = AppLanguage.tr('This link is invalid or has expired.',
        'यो लिङ्क अमान्य वा म्याद सकिएको छ।');
    _errorHint = AppLanguage.tr(
        'Please request a new reset link from the login screen.',
        'कृपया लगइन स्क्रिनबाट नयाँ रिसेट लिङ्क माग्नुहोस्।');
    setState(() => _status = _ResetStatus.error);
  }

  void _showServerError() {
    _errorTitle = AppLanguage.tr('Something went wrong.',
        'केही गडबड भयो।');
    _errorHint = AppLanguage.tr(
        'Please check your connection and try again, or request a new reset link.',
        'कृपया आफ्नो कनेक्सन जाँचेर पुनः प्रयास गर्नुहोस् वा नयाँ रिसेट लिङ्क माग्नुहोस्।');
    setState(() => _status = _ResetStatus.error);
  }

  Future<void> _reset() async {
    final token = _token;
    if (token == null) {
      _showLinkError();
      return;
    }
    if (_password.text.length < 6) {
      showAuthToast(
          context,
          AppLanguage.tr('Password must be at least 6 characters',
              'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ'),
          isError: true);
      return;
    }
    if (_password.text != _confirm.text) {
      showAuthToast(
          context,
          AppLanguage.tr(
              'Passwords do not match', 'पासवर्डहरू मिलेनन्'),
          isError: true);
      return;
    }
    setState(() => _loading = true);
    final result =
        await PasswordResetService.completeReset(token, _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case PasswordResetCompleteResult.success:
        setState(() => _status = _ResetStatus.success);
      case PasswordResetCompleteResult.invalidToken:
      case PasswordResetCompleteResult.expiredToken:
        _showLinkError();
      case PasswordResetCompleteResult.weakPassword:
        showAuthToast(
            context,
            AppLanguage.tr(
                'This password is too weak. Please choose a stronger password.',
                'यो पासवर्ड कमजोर छ। कृपया बलियो पासवर्ड छान्नुहोस्।'),
            isError: true);
      case PasswordResetCompleteResult.failed:
        _showServerError();
    }
  }

  Widget _form() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FloatingLabelField(
          label: AppLanguage.tr('New Password', 'नयाँ पासवर्ड'),
          controller: _password,
          leftIcon: Icons.lock_outline,
          secureToggle: true,
          obscureText: true,
          textInputAction: TextInputAction.next,
          nextFocus: _confirmFocus,
        ),
        const SizedBox(height: 16),
        FloatingLabelField(
          label: AppLanguage.tr('Confirm Password', 'पासवर्ड पुष्टि गर्नुहोस्'),
          controller: _confirm,
          focusNode: _confirmFocus,
          leftIcon: Icons.lock_outline,
          secureToggle: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: _reset,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label:
              AppLanguage.tr('Change Password', 'पासवर्ड परिवर्तन गर्नुहोस्'),
          loading: _loading,
          color: _purple,
          disabledColor: _purple,
          onPressed: _reset,
        ),
      ],
    );
  }

  Widget _success() {
    return Column(
      key: const ValueKey('success'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.check, size: 44, color: Color(0xFF16A34A)),
        ),
        const SizedBox(height: 16),
        Text(
          AppLanguage.tr(
              'Password reset successful', 'पासवर्ड सफलतापूर्वक रिसेट भयो'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
          color: _purple,
          disabledColor: _purple,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  Widget _error() {
    final title = _errorTitle ??
        AppLanguage.tr('This link is invalid or has expired.',
            'यो लिङ्क अमान्य वा म्याद सकिएको छ।');
    final hint = _errorHint ??
        AppLanguage.tr(
            'Please request a new reset link from the login screen.',
            'कृपया लगइन स्क्रिनबाट नयाँ रिसेट लिङ्क माग्नुहोस्।');
    return Column(
      key: const ValueKey('error'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(40),
          ),
          child:
              const Icon(Icons.error_outline, size: 44, color: Color(0xFFDC2626)),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          hint,
          style: const TextStyle(
              fontSize: 15, color: Color(0xFF6B7280), height: 22 / 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: AppLanguage.tr('Back to Login', 'लगइनमा फर्कनुहोस्'),
          color: _purple,
          disabledColor: _purple,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  /// 1s preloading shimmer shown on first build before the page content.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
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
          title: AppLanguage.tr('Set New Password', 'नयाँ पासवर्ड सेट गर्नुहोस्'),
          subtitle: AppLanguage.tr(
              'Choose a strong new password for your account',
              'आफ्नो खाताको लागि बलियो नयाँ पासवर्ड छान्नुहोस्'),
          child: _preloading
              ? _preloadingBody()
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: switch (_status) {
                    _ResetStatus.form => _form(),
                    _ResetStatus.success => _success(),
                    _ResetStatus.error => _error(),
                  },
                ),
        ),
      ),
    );
  }
}
