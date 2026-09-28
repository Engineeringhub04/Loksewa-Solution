import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Forgot password — mirrors app/(auth)/forgot-password.tsx.
/// Sends the reset email, then shows the "Check Your Email" state.
/// Errors are intentionally swallowed (prevents email enumeration).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _sent ? _buildSent() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Enter your email and we'll send you a secure reset link",
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
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
              : const Text('Send Reset Link'),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text(
            'Back to Login',
            style: TextStyle(color: Color(0xFF7C3AED)),
          ),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF3E8FF),
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              size: 44, color: Color(0xFF7C3AED)),
        ),
        const SizedBox(height: 16),
        const Text(
          'Check Your Email',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          "We've sent a password reset link to ${_email.text.trim()}. Open the link to set a new password.",
          style: const TextStyle(color: Colors.grey, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
          ),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}
