import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/widgets/auth/auth_buttons.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';

/// Forgot password — mirrors app/(auth)/forgot-password.tsx.
/// Sends the reset email, then shows the "Check Your Email" state.
/// Errors are intentionally swallowed (prevents email enumeration).
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

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      showAuthToast(context, 'Please enter a valid email', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.sendPasswordReset(email);
    } catch (_) {
      // Intentionally ignored — always show the same message.
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _sent = true;
        });
      }
    }
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FloatingLabelField(
          label: 'Email Address',
          controller: _email,
          leftIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Send Reset Link',
          loading: _loading,
          color: _purple,
          disabledColor: _purple,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: const Text(
              'Back to Login',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _purple),
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
          child: const Icon(Icons.mail_outline,
              size: 44, color: _purple),
        ),
        const SizedBox(height: 16),
        const Text(
          'Check Your Email',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "We've sent a password reset link to ${_email.text.trim()}. Until app-link setup is completed, Firebase may open its secure web page; afterward, the link can open this app's reset screen on the device.",
          style: const TextStyle(
              fontSize: 15, color: Color(0xFF6B7280), height: 22 / 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        AuthPrimaryButton(
          label: 'Back to Login',
          color: _purple,
          disabledColor: _purple,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: AuthScreenLayout(
        title: 'Reset Password',
        subtitle: "Enter your email and we'll send you a secure reset link",
        onBack: () => context.pop(),
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
    );
  }
}
