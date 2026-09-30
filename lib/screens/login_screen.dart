import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/app_config.dart';
import '../services/auth_service.dart';
import '../services/course_setup_gate.dart';
import '../services/device_session.dart';
import '../widgets/auth/auth_buttons.dart';
import '../widgets/auth/auth_screen_layout.dart';
import '../widgets/auth/floating_label_field.dart';
import '../widgets/auth/shake.dart';
import '../widgets/auth/terms_checkbox.dart';

/// Login — mirrors app/(auth)/login.tsx pixel-close.
/// Collapsed state (Continue with Google / or / Continue with Email / terms /
/// Sign Up) fades into the expanded email state (Back, "Login with Email",
/// floating-label fields, Forgot Password, Login button gated on valid
/// email + 6+ char password, Google button, terms, Sign Up link).
/// Terms checkbox gates both auth actions (red + shake when skipped).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _showEmailFields = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _acceptedTerms = false;
  bool _termsError = false;

  late final AnimationController _shakeController;
  late final AnimationController _termsShakeController;
  late final GoogleSignIn _googleSignIn;

  static final _emailRegex = RegExp(r'^\S+@\S+\.\S+$');

  bool get _emailValid => _emailRegex.hasMatch(_email.text.trim());
  bool get _canSubmit => _emailValid && _password.text.length >= 6;

  @override
  void initState() {
    super.initState();
    _shakeController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _termsShakeController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _googleSignIn =
        GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
    // Eviction notice: claimed on mount, shown after the transition settles
    // (480ms) so it lands on a finished screen, not over the entry animation.
    DeviceSession.consumeEvictionNotice().then((notice) {
      if (!mounted || notice == null) return;
      Future.delayed(const Duration(milliseconds: 480), () {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Signed out'),
            content: Text(notice.isEmpty
                ? 'Your account was signed in on another device, so this phone was signed out.'
                : 'Your account was signed in on "$notice", so this phone was signed out.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    _shakeController.dispose();
    _termsShakeController.dispose();
    super.dispose();
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'auth/invalid-credential':
        return 'Email or password is incorrect.';
      case 'auth/user-disabled':
        return 'This account has been disabled.';
      case 'auth/too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'auth/invalid-email':
        return 'Please enter a valid email address.';
      case 'auth/invalid-api-key':
        return 'Server configuration error. Please update to the latest version of the app.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  void _triggerShake() => _shakeController.forward(from: 0.0);

  /// Terms skipped — flash the row red, shake and toast.
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
    // Claim this device for the account (one account = one device).
    await DeviceSession.claimSession(uid);
    // React parity: no course setup on this account → course-setup
    // (initial mode), not home. Unknown (offline) → setup, like React's
    // .catch(() => false).
    final done = await CourseSetupGate.isComplete(uid);
    if (mounted) context.go(done == true ? '/' : '/course-setup');
  }

  Future<void> _handleLogin() async {
    _dismissKeyboard();
    if (!_acceptedTerms) {
      _flagTermsRequired();
      return;
    }
    if (!_canSubmit) {
      _triggerShake();
      showAuthToast(context, 'Please enter a valid email and password',
          isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final user = await AuthService.signInWithEmail(
        _email.text.trim(),
        _password.text,
      );
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
      // Force the account chooser (mirrors the Expo auth-session prompt).
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
        allowCreate: false,
      );
      if (!mounted) return;
      showAuthToast(context, 'Login successful');
      await _afterSignIn(result.user.uid);
    } on AuthError catch (e) {
      if (!mounted) return;
      final code = e.code;
      if (code == 'auth/account-exists-with-different-credential' ||
          code == 'auth/google-account-creation-blocked') {
        showAuthToast(
          context,
          'This Google account is not linked here. Please use the existing login method for this email.',
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
        prefix: "Don't have an account? ",
        linkText: 'Sign Up',
        onTap: () => context.push('/signup'),
      );

  Widget _collapsed() {
    return Column(
      key: const ValueKey('collapsed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _googleButton(),
        const AuthDivider(),
        AuthEmailButton(onPressed: () => setState(() => _showEmailFields = true)),
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
            onPressed: () => setState(() => _showEmailFields = false),
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
          'Login with Email',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 20),
        FloatingLabelField(
          label: 'Email',
          controller: _email,
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
          onSubmitted: _handleLogin,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/forgot-password'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8)),
            ),
          ),
        ),
        AuthPrimaryButton(
          label: 'Login',
          loading: _loading,
          enabled: _canSubmit,
          onPressed: _handleLogin,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Stack(
        children: [
          AuthScreenLayout(
            title: 'Welcome Back',
            subtitle:
                'Sign in to continue your Loksewa preparation journey',
            child: Shake(
              controller: _shakeController,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child:
                    _showEmailFields ? _expanded() : _collapsed(),
              ),
            ),
          ),
          if (_googleLoading) const GoogleLoadingOverlay(),
        ],
      ),
    );
  }
}
