import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:loksewa_solution/services/app_config.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/course_setup_gate.dart';
import 'package:loksewa_solution/services/device_session.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/widgets/auth/auth_buttons.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';
import 'package:loksewa_solution/widgets/auth/shake.dart';
import 'package:loksewa_solution/widgets/auth/terms_checkbox.dart';

/// Signup — mirrors app/(auth)/signup.tsx pixel-close.
/// Collapsed (Google / or / Continue with Email / terms / Login link) fades
/// into the expanded email form (Back, "Sign Up with Email", Full Name +
/// Email + Password fields, Create Account gated on name 2+ chars + valid
/// email + 6+ char password). Terms checkbox gates both actions.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _showFields = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _acceptedTerms = false;
  bool _termsError = false;

  late final AnimationController _shakeController;
  late final AnimationController _termsShakeController;
  late final GoogleSignIn _googleSignIn;

  static final _emailRegex = RegExp(r'^\S+@\S+\.\S+$');

  bool get _emailValid => _emailRegex.hasMatch(_email.text.trim());
  bool get _canSubmit =>
      _name.text.trim().length >= 2 &&
      _emailValid &&
      _password.text.length >= 6;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _termsShakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _googleSignIn = GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _shakeController.dispose();
    _termsShakeController.dispose();
    super.dispose();
  }

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

  void _triggerShake() => _shakeController.forward(from: 0.0);

  void _flagTermsRequired() {
    setState(() => _termsError = true);
    _termsShakeController.forward(from: 0.0);
    showAuthToast(
      context,
      'Please accept the Terms and Privacy Policy to continue.',
    );
  }

  void _toggleTerms() {
    setState(() {
      _acceptedTerms = !_acceptedTerms;
      if (_acceptedTerms) _termsError = false;
    });
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  Future<void> _afterSignIn(String uid) async {
    await DeviceSession.claimSession(uid);
    // Fresh email signup: React routes straight to course-setup
    // (initial mode — no back button, "Save Course").
    if (mounted) context.go('/course-setup');
  }

  Future<void> _handleSignup() async {
    _dismissKeyboard();
    if (!_acceptedTerms) {
      _flagTermsRequired();
      return;
    }
    if (!_canSubmit) {
      _triggerShake();
      if (_name.text.trim().length < 2) {
        showAuthToast(context, 'Name must be at least 2 characters',
            isError: true);
      } else if (!_emailValid) {
        showAuthToast(context, 'Please enter a valid email', isError: true);
      } else {
        showAuthToast(context, 'Password must be at least 6 characters',
            isError: true);
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final user = await AuthService.signUpWithEmail(
        _email.text.trim(),
        _password.text,
      );
      // Mirror registerWithEmail: store the display name on the user document.
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
      if (!mounted) return;
      showAuthToast(context, 'Account created successfully');
      await _afterSignIn(user.uid);
    } on AuthError catch (e) {
      if (!mounted) return;
      _triggerShake();
      showAuthToast(context, _friendlyError(e.code), isError: true);
    } catch (_) {
      if (!mounted) return;
      _triggerShake();
      showAuthToast(context, 'Network error. Please check your connection.',
          isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    _dismissKeyboard();
    if (!_acceptedTerms) {
      _flagTermsRequired();
      return;
    }
    setState(() => _googleLoading = true);
    try {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      final account = await _googleSignIn.signIn();
      if (account == null) return; // user cancelled
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (!mounted) return;
      if (idToken == null || idToken.isEmpty) {
        showAuthToast(
            context, 'Google Sign-In could not be completed. Please try again.',
            isError: true);
        return;
      }
      final result = await AuthService.signInWithGoogleIdToken(
        idToken,
        allowCreate: true,
      );
      if (!mounted) return;
      showAuthToast(context, 'Google account signed in successfully');
      // Google on the signup screen can be a new OR an existing account:
      // route on the course-setup gate (new users land on setup).
      await DeviceSession.claimSession(result.user.uid);
      final done = await CourseSetupGate.isComplete(result.user.uid);
      if (!mounted) return;
      context.go(done == true ? '/' : '/course-setup');
    } on AuthError catch (e) {
      if (!mounted) return;
      final code = e.code;
      if (code == 'auth/email-already-in-use' ||
          code == 'auth/account-exists-with-different-credential') {
        showAuthToast(
          context,
          'This email already has an account. Please use its existing login method.',
          isError: true,
        );
      } else {
        showAuthToast(context, _friendlyError(code), isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      showAuthToast(context, 'Google Sign-In failed. Please try again.',
          isError: true);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Widget _termsRow() {
    return Shake(
      controller: _termsShakeController,
      child: TermsCheckbox(
        accepted: _acceptedTerms,
        hasError: _termsError,
        onToggle: _toggleTerms,
        onOpenTerms: () => context.push('/terms-conditions'),
        onOpenPrivacy: () => context.push('/privacy-policy'),
      ),
    );
  }

  Widget _googleButton() => AuthGoogleButton(
        onPressed: _handleGoogleSignIn,
        loading: _googleLoading,
      );

  Widget _bottomLink() => AuthBottomLink(
        prefix: 'Already have an account? ',
        linkText: 'Login',
        onTap: () => context.push('/login'),
      );

  Widget _collapsed() {
    return Column(
      key: const ValueKey('collapsed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _googleButton(),
        const AuthDivider(),
        AuthEmailButton(onPressed: () => setState(() => _showFields = true)),
        _termsRow(),
        _bottomLink(),
      ],
    );
  }

  Widget _expanded() {
    return Column(
      key: const ValueKey('expanded'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showFields = false),
            icon: const Icon(Icons.arrow_back,
                size: 18, color: Color(0xFF1D4ED8)),
            label: const Text(
              'Back',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8)),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(bottom: 16),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        const Text(
          'Sign Up with Email',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 20),
        FloatingLabelField(
          label: 'Full Name',
          controller: _name,
          leftIcon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          nextFocus: _emailFocus,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        FloatingLabelField(
          label: 'Email',
          controller: _email,
          focusNode: _emailFocus,
          leftIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          nextFocus: _passwordFocus,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        FloatingLabelField(
          label: 'Password',
          controller: _password,
          focusNode: _passwordFocus,
          leftIcon: Icons.lock_outline,
          secureToggle: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: _handleSignup,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Create Account',
          loading: _loading,
          enabled: _canSubmit,
          onPressed: _handleSignup,
        ),
        const AuthDivider(),
        _googleButton(),
        _termsRow(),
        _bottomLink(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Transparent status bar with dark icons so the light background flows
    // under the clock — same edge-to-edge treatment as home pages; kills
    // the dark band that used to sit above the signup screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: Stack(
          children: [
            AuthScreenLayout(
              title: 'Create Account',
              subtitle:
                  'Join the Loksewa community and start your exam preparation today',
              onBack: () => context.pop(),
              child: Shake(
                controller: _shakeController,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _showFields ? _expanded() : _collapsed(),
                ),
              ),
            ),
            if (_googleLoading) const GoogleLoadingOverlay(),
          ],
        ),
      ),
    );
  }
}
