import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/cf_api.dart';
import '../../services/course_setup_gate.dart';
import '../../services/device_session_service.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/auth/auth_buttons.dart';
import '../../widgets/auth/auth_screen_layout.dart';
import '../../widgets/auth/floating_label_field.dart';
import '../../widgets/device_session_dialogs.dart';
import '../../widgets/popup_action_button.dart';

/// Set Your Password — NOTE-11 claim flow (Round-1 Cloudflare migration).
///
/// Migrated accounts were copied WITHOUT their passwords, so the first
/// sign-in on the new backend proves email ownership with a 6-digit code:
/// step 1 collects the email and requests the code; step 2 reveals the
/// code field + the "Set Your Password" fields. A successful verify logs
/// the user in and lands exactly like a normal login (device-session
/// check, then the course-setup gate). The layout duplicates the login
/// page's UI (AuthScreenLayout + FloatingLabelField + AuthPrimaryButton).
class ClaimPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ClaimPasswordScreen({super.key, this.initialEmail});

  @override
  State<ClaimPasswordScreen> createState() => _ClaimPasswordScreenState();
}

class _ClaimPasswordScreenState extends State<ClaimPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _codeSent = false;
  bool _sendingCode = false;
  bool _setting = false;

  static final _emailRegex = RegExp(r'^\S+@\S+\.\S+$');

  bool get _emailValid => _emailRegex.hasMatch(_email.text.trim());
  bool get _canVerify =>
      _code.text.trim().length == 6 &&
      _password.text.length >= 6 &&
      _confirm.text == _password.text;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _email.text = widget.initialEmail!;
    }
  }

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

  // ------------------------------------------------------------ popups
  /// Error popup — AppModalShell, red accent (same pattern as the
  /// invalid-reset-link popup in reset_link_service.dart).
  Future<void> _showErrorPopup(String title, String message) {
    return AppModalShell.show<void>(
      context: context,
      builder: (modalContext) => AppModalShell(
        accent: const Color(0xFFDC2626),
        accentMid: const Color(0xFFEF4444),
        accentLight: const Color(0xFFFECACA),
        tagColor: const Color(0xFFDC2626),
        tagLabel: AppLanguage.tr('PASSWORD', 'पासवर्ड'),
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
          title,
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
          message,
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

  String _errorMessage(Object e) {
    if (e is CfError) {
      switch (e.error) {
        case 'wrong_code':
          return AppLanguage.tr(
            'That code is incorrect or has expired. Please check the code and try again.',
            'यो कोड मिलेन वा म्याद सकियो। कोड जाँचेर पुनः प्रयास गर्नुहोस्।',
          );
        case 'blacklisted':
          return AppLanguage.tr(
            'This account cannot be used. Please contact Our Loksewa Solution Team.',
            'यो खाता प्रयोग गर्न मिल्दैन। कृपया Loksewa Solution टिमलाई सम्पर्क गर्नुहोस्।',
          );
        case 'too_many_requests':
        case 'rate_limited':
          return AppLanguage.tr(
            'Too many attempts. Please try again later.',
            'धेरै प्रयास भयो। कृपया केही समयपछि पुनः प्रयास गर्नुहोस्।',
          );
        default:
          return AppLanguage.tr(
            'Something went wrong. Please try again.',
            'केही गलत भयो। कृपया पुनः प्रयास गर्नुहोस्।',
          );
      }
    }
    return AppLanguage.tr(
      'Network error. Please check your connection and try again.',
      'नेटवर्क समस्या। कृपया इन्टरनेट जाँचेर पुनः प्रयास गर्नुहोस्।',
    );
  }

  // ------------------------------------------------------------- actions
  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (!_emailValid) {
      showAuthToast(
        context,
        AppLanguage.tr('Please enter a valid email address.',
            'कृपया मान्य इमेल ठेगाना प्रविष्ट गर्नुहोस्।'),
        isError: true,
      );
      return;
    }
    setState(() => _sendingCode = true);
    try {
      await AuthService.requestClaimCode(_email.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
      showAuthToast(
        context,
        AppLanguage.tr('Code sent. Please check your email.',
            'कोड पठाइयो। कृपया आफ्नो इमेल जाँच्नुहोस्।'),
      );
      _codeFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      await _showErrorPopup(
        AppLanguage.tr('Could Not Send Code', 'कोड पठाउन सकिएन'),
        _errorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_password.text.length < 6) {
      showAuthToast(
        context,
        AppLanguage.tr('Password must be at least 6 characters.',
            'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ।'),
        isError: true,
      );
      return;
    }
    if (_confirm.text != _password.text) {
      showAuthToast(
        context,
        AppLanguage.tr('Passwords do not match.',
            'पासवर्डहरू मेल खाएनन्।'),
        isError: true,
      );
      return;
    }
    if (_code.text.trim().length != 6) {
      showAuthToast(
        context,
        AppLanguage.tr('Please enter the 6-digit code.',
            'कृपया ६ अंकको कोड प्रविष्ट गर्नुहोस्।'),
        isError: true,
      );
      return;
    }
    setState(() => _setting = true);
    try {
      final user = await AuthService.claimWithCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      showAuthToast(
        context,
        AppLanguage.tr('Password set. Welcome back!',
            'पासवर्ड सेट भयो। स्वागत छ!'),
      );
      await _afterClaim(user.uid);
    } catch (e) {
      if (!mounted) return;
      await _showErrorPopup(
        AppLanguage.tr('Set Your Password', 'पासवर्ड सेट गर्नुहोस्'),
        _errorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _setting = false);
    }
  }

  /// Lands exactly like a normal login success: one-device check first,
  /// then the course-setup gate (see LoginScreen._afterSignIn).
  Future<void> _afterClaim(String uid) async {
    final check = await DeviceSessionService.checkDeviceSessionForLogin(uid);
    if (!mounted) return;
    if (check.outcome == LoginSessionOutcome.conflict &&
        check.existing != null) {
      final c = check.existing!;
      final takeOver = await showDeviceTakeoverDialog(
        context,
        deviceName: c.deviceName,
        lastActiveLabel: c.lastActiveLabel,
      );
      if (!mounted) return;
      if (!takeOver) {
        await AuthService.logout().catchError((_) {});
        if (mounted) context.go('/login');
        return;
      }
      final claimed =
          await DeviceSessionService.takeOverDeviceSession(uid)
              .catchError((_) => false);
      if (!mounted) return;
      if (!claimed) {
        await AuthService.logout().catchError((_) {});
        if (mounted) context.go('/login');
        return;
      }
      showToast(context, 'This device is now your active login.',
          ToastVariant.success);
    }
    await DeviceSessionService.clearEvictionNotice();
    final done = await CourseSetupGate.isComplete(uid);
    if (mounted) context.go(done == true ? '/' : '/course-setup');
  }

  // ------------------------------------------------------------------ UI
  Widget _stepOne() {
    return Column(
      key: const ValueKey('claim-step-1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLanguage.tr(
            'Enter your account email and we will send you a 6-digit code to confirm it is you.',
            'आफ्नो खाताको इमेल प्रविष्ट गर्नुहोस्, तपाईं नै हुनुहुन्छ भनेर पुष्टि गर्न हामी ६ अंकको कोड पठाउनेछौं।',
          ),
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF6B7280), height: 20 / 14),
        ),
        const SizedBox(height: 20),
        FloatingLabelField(
          label: AppLanguage.tr('Email', 'इमेल'),
          controller: _email,
          leftIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: _sendCode,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: AppLanguage.tr('Send Code', 'कोड पठाउनुहोस्'),
          loading: _sendingCode,
          enabled: _emailValid,
          onPressed: _sendCode,
        ),
      ],
    );
  }

  Widget _stepTwo() {
    return Column(
      key: const ValueKey('claim-step-2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLanguage.tr(
            'We sent a 6-digit code to ${_email.text.trim()}. Enter it below and choose your password.',
            'हामीले ${_email.text.trim()} मा ६ अंकको कोड पठाएका छौं। तल कोड हाल्नुहोस् र आफ्नो पासवर्ड रोज्नुहोस्।',
          ),
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF6B7280), height: 20 / 14),
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
          label: AppLanguage.tr('Set Your Password', 'पासवर्ड सेट गर्नुहोस्'),
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
          label: AppLanguage.tr('Set Password & Login', 'पासवर्ड सेट गरी लगइन गर्नुहोस्'),
          loading: _setting,
          enabled: _canVerify,
          onPressed: _verify,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _sendingCode ? null : _sendCode,
            child: Text(
              AppLanguage.tr('Resend Code', 'कोड पुनः पठाउनुहोस्'),
              style: const TextStyle(
                  fontSize: 13,
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
    // Transparent status bar with dark icons — same treatment as login.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: AuthScreenLayout(
          title: AppLanguage.tr('Set Your Password', 'पासवर्ड सेट गर्नुहोस्'),
          subtitle: AppLanguage.tr(
            'First time on the new system? Set your password to continue.',
            'नयाँ प्रणालीमा पहिलो पटक? जारी राख्न आफ्नो पासवर्ड सेट गर्नुहोस्।',
          ),
          onBack: () => context.pop(),
          illustrationAsset: 'assets/images/auth_illust_login.png',
          illustrationHeight: 130,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _codeSent ? _stepTwo() : _stepOne(),
          ),
        ),
      ),
    );
  }
}
