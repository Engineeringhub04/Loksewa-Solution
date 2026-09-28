import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// In-app password reset completion — mirrors app/reset-password.tsx.
/// Reads the Firebase action-link params (oobCode, mode) from the route.
/// NOTE: AuthService has no verifyPasswordResetCode/confirmPasswordReset yet,
/// so with a valid-looking oobCode we show the form but the actual confirm
/// call needs that AuthService method (flagged in the handoff). Without an
/// oobCode we show the invalid-link state, exactly like the original.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _reset(String oobCode) async {
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // confirmPasswordReset is not on AuthService yet — surfaced honestly.
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Password reset needs an auth-service update. Please request a new link.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final oobCode = params['oobCode'];
    final mode = params['mode'];
    final validParams = oobCode != null &&
        oobCode.isNotEmpty &&
        (mode == null || mode == 'resetPassword');

    return Scaffold(
      appBar: AppBar(title: const Text('Set New Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: validParams ? _buildForm(oobCode) : _buildInvalid(),
      ),
    );
  }

  Widget _buildForm(String oobCode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose a strong new password for your account',
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _reset(oobCode),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _loading ? null : () => _reset(oobCode),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Change Password'),
        ),
      ],
    );
  }

  Widget _buildInvalid() {
    return Column(
      children: [
        const SizedBox(height: 32),
        const Text(
          'Reset Link Unavailable',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'This reset link is invalid or has expired. Request a new link and open it on this device.',
          style: TextStyle(color: Colors.grey, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/forgot-password'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
          ),
          child: const Text('Request New Link'),
        ),
      ],
    );
  }
}
