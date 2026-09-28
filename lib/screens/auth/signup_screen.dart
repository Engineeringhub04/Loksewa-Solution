import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/device_session.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Signup — mirrors app/(auth)/signup.tsx.
/// Name + email + password, terms checkbox gates the action, Create Account
/// stays disabled until the fields are valid. On success the user document is
/// written, this device claims the account, and we go home.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _acceptedTerms = false;
  bool _termsError = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _emailValid =>
      RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim());
  bool get _canSubmit =>
      _name.text.trim().length >= 2 && _emailValid && _password.text.length >= 6;

  String _friendlyError(String code) {
    switch (code) {
      case 'auth/email-already-in-use':
        return 'This email is already registered';
      case 'auth/weak-password':
        return 'Password must be at least 6 characters';
      case 'auth/invalid-email':
        return 'Please enter a valid email';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  Future<void> _signUp() async {
    if (!_acceptedTerms) {
      setState(() => _termsError = true);
      return;
    }
    if (!_canSubmit) {
      setState(() {
        if (_name.text.trim().length < 2) {
          _error = 'Name must be at least 2 characters';
        } else if (!_emailValid) {
          _error = 'Please enter a valid email';
        } else {
          _error = 'Password must be at least 6 characters';
        }
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await AuthService.signUpWithEmail(
        _email.text.trim(),
        _password.text,
      );
      // Mirror registerWithEmail: store the display name on the user document.
      // (The Identity Toolkit displayName update needs an AuthService method;
      // the document write keeps the name visible everywhere in-app.)
      try {
        final idToken = await AuthService.getValidIdToken();
        await FirestoreRest.setDocument(
          'users/${user.uid}',
          {
            'displayName': _name.text.trim(),
            'email': user.email ?? _email.text.trim(),
          },
          idToken: idToken,
          merge: true,
        );
      } catch (_) {}
      await DeviceSession.claimSession(user.uid);
      if (mounted) context.go('/');
    } on AuthError catch (e) {
      setState(() => _error = _friendlyError(e.code));
    } catch (_) {
      setState(() => _error = 'Network error. Please check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Join the Loksewa community and start your exam preparation today',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _signUp(),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() {
                _acceptedTerms = !_acceptedTerms;
                if (_acceptedTerms) _termsError = false;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 10, top: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _termsError && !_acceptedTerms
                              ? Colors.red
                              : (_acceptedTerms
                                  ? AppColors.navy
                                  : Colors.grey.shade400),
                          width: 1.5,
                        ),
                        color: _acceptedTerms ? AppColors.navy : null,
                      ),
                      child: _acceptedTerms
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    Expanded(
                      child: Wrap(
                        children: [
                          Text(
                            'I agree to the ',
                            style: TextStyle(
                              fontSize: 13,
                              color: _termsError && !_acceptedTerms
                                  ? Colors.red
                                  : Colors.grey.shade600,
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                context.push('/terms-conditions'),
                            child: const Text(
                              'Terms and Conditions',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.navy,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            ' and ',
                            style: TextStyle(
                              fontSize: 13,
                              color: _termsError && !_acceptedTerms
                                  ? Colors.red
                                  : Colors.grey.shade600,
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                context.push('/privacy-policy'),
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.navy,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_loading || !_canSubmit) ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
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
                  : const Text('Create Account'),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account? ',
                    style: TextStyle(color: Colors.grey)),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
