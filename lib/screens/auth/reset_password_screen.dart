import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/widgets/auth/auth_buttons.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';

/// In-app password reset completion — mirrors app/reset-password.tsx.
/// Reads the Firebase action-link params (oobCode, mode) from the route,
/// validates the code, then lets the user set a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _CodeStatus { checking, valid, invalid }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _purple = Color(0xFF7C3AED);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _loading = false;
  _CodeStatus _status = _CodeStatus.checking;
  String? _oobCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _validateCode());
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    final params = GoRouterState.of(context).uri.queryParameters;
    final oobCode = params['oobCode'];
    final mode = params['mode'];
    // Allow manual testing with only oobCode, but reject an action link
    // explicitly meant for another Firebase action.
    if (oobCode == null ||
        oobCode.isEmpty ||
        (mode != null && mode != 'resetPassword')) {
      if (mounted) setState(() => _status = _CodeStatus.invalid);
      return;
    }
    try {
      final result = await AuthService.verifyPasswordResetCode(oobCode);
      if (!mounted) return;
      setState(() {
        _oobCode = oobCode;
        _status = (result.requestType == null ||
                result.requestType == 'PASSWORD_RESET')
            ? _CodeStatus.valid
            : _CodeStatus.invalid;
      });
    } catch (_) {
      if (mounted) setState(() => _status = _CodeStatus.invalid);
    }
  }

  Future<void> _reset() async {
    if (_status != _CodeStatus.valid || _oobCode == null) {
      showAuthToast(context, 'This reset link is invalid or has expired',
          isError: true);
      return;
    }
    if (_password.text.length < 6) {
      showAuthToast(context, 'Password must be at least 6 characters',
          isError: true);
      return;
    }
    if (_password.text != _confirm.text) {
      showAuthToast(context, 'Passwords do not match', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.confirmPasswordReset(_oobCode!, _password.text);
      if (!mounted) return;
      context.go('/login');
      showAuthToast(context, 'Password changed successfully');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = _CodeStatus.invalid;
      });
      showAuthToast(context, 'This reset link is invalid or has expired',
          isError: true);
    }
  }

  Widget _checking() {
    return const Column(
      key: ValueKey('checking'),
      children: [
        SizedBox(height: 24),
        CircularProgressIndicator(color: _purple),
        SizedBox(height: 16),
        Text(
          'Checking reset link...',
          style: TextStyle(
              fontSize: 15, color: Color(0xFF6B7280), height: 22 / 15),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _invalid() {
    return Column(
      key: const ValueKey('invalid'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Reset Link Unavailable',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'This reset link is invalid or has expired. Request a new link and open it after the app-link setup is enabled.',
          style: TextStyle(
              fontSize: 15, color: Color(0xFF6B7280), height: 22 / 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Request New Link',
          color: _purple,
          disabledColor: _purple,
          onPressed: () => context.go('/forgot-password'),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FloatingLabelField(
          label: 'New Password',
          controller: _password,
          leftIcon: Icons.lock_outline,
          secureToggle: true,
          obscureText: true,
          textInputAction: TextInputAction.next,
          nextFocus: _confirmFocus,
        ),
        const SizedBox(height: 16),
        FloatingLabelField(
          label: 'Confirm Password',
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
          label: 'Change Password',
          loading: _loading,
          color: _purple,
          disabledColor: _purple,
          onPressed: _reset,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: AuthScreenLayout(
        title: 'Set New Password',
        subtitle: 'Choose a strong new password for your account',
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: switch (_status) {
            _CodeStatus.checking => _checking(),
            _CodeStatus.invalid => _invalid(),
            _CodeStatus.valid => _form(),
          },
        ),
      ),
    );
  }
}
