import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/account_protection.dart';
import '../services/app_language.dart';
import '../services/auth_service.dart';
import '../services/course_setup_gate.dart';
import '../services/device_session_service.dart';
import '../services/google_auth.dart';
import '../widgets/app_modal_shell.dart';
import '../widgets/popup_action_button.dart';
import '../widgets/auth/auth_buttons.dart';
import '../widgets/auth/auth_screen_layout.dart';
import '../widgets/auth/floating_label_field.dart';
import '../widgets/auth/shake.dart';
import '../widgets/auth/terms_checkbox.dart';
import '../widgets/device_session_dialogs.dart';
import '../widgets/app_toast.dart';

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

  static final _emailRegex = RegExp(r'^\S+@\S+\.\S+$');

  bool get _emailValid => _emailRegex.hasMatch(_email.text.trim());
  bool get _canSubmit => _emailValid && _password.text.length >= 6;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _termsShakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    // Eviction notice: claimed on mount, shown after the transition settles
    // (480ms) so it lands on a finished screen, not over the entry animation.
    // Shows exactly once (consumed on read).
    DeviceSessionService.consumeEvictionNotice().then((notice) {
      if (!mounted || notice == null) return;
      Future.delayed(const Duration(milliseconds: 480), () {
        if (!mounted) return;
        showEvictionNoticeDialog(context, deviceName: notice.deviceName);
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

  /// NOTE-11 needs_claim prompt (AppModalShell): the account exists but
  /// has no password on the new backend yet — offer the claim page with
  /// the typed email prefilled.
  Future<void> _showNeedsClaimPrompt() {
    final email = _email.text.trim();
    return AppModalShell.show<void>(
      context: context,
      builder: (modalContext) => AppModalShell(
        accent: const Color(0xFF2563EB),
        accentMid: const Color(0xFF3B82F6),
        accentLight: const Color(0xFFBFDBFE),
        tagColor: const Color(0xFF1D4ED8),
        tagLabel: AppLanguage.tr('SET PASSWORD', 'पासवर्ड सेट'),
        onClose: () => Navigator.of(modalContext).pop(),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF2563EB),
          ),
          child: const Icon(Icons.lock_outline_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Set Your Password', 'पासवर्ड सेट गर्नुहोस्'),
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
          AppLanguage.tr(
            'This account does not have a password yet. Set your password now to log in.',
            'यो खातामा अहिले पासवर्ड छैन। लगइन गर्न अहिले नै आफ्नो पासवर्ड सेट गर्नुहोस्।',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: PopupActionButton(
          label: AppLanguage.tr('Set Your Password', 'पासवर्ड सेट गर्नुहोस्'),
          backgroundColor: const Color(0xFF1D4ED8),
          onTap: () {
            Navigator.of(modalContext).pop();
            if (mounted) {
              context.push('/claim-password', extra: email);
            }
          },
        ),
      ),
    );
  }

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

  /// NOTE 1 — blacklist: after a successful sign-in, a blacklisted email is
  /// signed straight back out and blocked. Returns true when blocked.
  Future<bool> _rejectIfBlacklisted(String? email) async {
    final e = (email ?? '').trim();
    if (e.isEmpty) return false;
    if (await AccountProtection.isEmailBlacklisted(e)) {
      await GoogleSignIn.instance.signOut().catchError((_) {});
      await AuthService.logout().catchError((_) {});
      if (!mounted) return true;
      _triggerShake();
      showAuthToast(
          context, AccountProtection.blacklistedMessage(),
          isError: true);
      return true;
    }
    return false;
  }

  Future<void> _afterSignIn(String uid) async {
    // NOTE 3 backfill: older accounts may lack the platform field —
    // fill it in on login (best-effort, never blocks).
    await AccountProtection.backfillPlatformIfMissing(uid);
    // One account = one device. Check AFTER auth (rules only let the owner
    // read their own session doc). Conflict → takeover dialog; the guard is
    // held off while the dialog is on screen.
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
        // Cancel = real sign-out, not just a dismissed dialog.
        await AuthService.logout().catchError((_) {});
        return;
      }
      final claimed =
          await DeviceSessionService.takeOverDeviceSession(uid).catchError((_) => false);
      if (!mounted) return;
      if (!claimed) {
        await AuthService.logout().catchError((_) {});
        return;
      }
      // Premium feel: confirm on this device too (push also sent).
      showToast(context, 'This device is now your active login.',
          ToastVariant.success);
    }
    await DeviceSessionService.clearEvictionNotice();
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
      // NOTE 1 — blacklisted emails cannot log back in.
      if (await _rejectIfBlacklisted(user.email)) return;
      await _afterSignIn(user.uid);
    } on AuthError catch (e) {
      if (!mounted) return;
      // NOTE-11: a migrated account whose password was never set gets
      // routed to the claim page (email prefilled) instead of an error.
      if (e.code == 'auth/needs-claim') {
        await _showNeedsClaimPrompt();
        return;
      }
      _triggerShake();
      if (e.code == 'auth/blacklisted') {
        showAuthToast(context, AccountProtection.blacklistedMessage(),
            isError: true);
        return;
      }
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
    // Button shows its own spinner + the screen dims (no white-card popup).
    setState(() => _googleLoading = true);
    try {
      // v7: singleton must be initialized exactly once before use.
      await GoogleAuth.ensureInitialized();
      // v7: authenticate() uses the button flow on Android, which ALWAYS
      // shows the Credential Manager chooser UI (no silent auto-select), so
      // no pre-signOut is needed — Google runs its full native flow
      // (account tap -> system row spinner -> consent -> return).
      // v7: Credential Manager bottom sheet on Android. Throws
      // GoogleSignInException(code: canceled) when the user dismisses it.
      final GoogleSignInAccount account;
      try {
        account = await GoogleSignIn.instance.authenticate();
      } catch (e) {
        if (GoogleAuth.isUserCancelled(e)) return; // user cancelled
        rethrow;
      }
      // v7: authentication is a sync getter — tokens arrive with authenticate().
      final idToken = account.authentication.idToken;
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
        googlePhotoUrl: account.photoUrl,
      );
      if (!mounted) return;
      // NOTE 1 — blacklisted emails cannot log back in.
      if (await _rejectIfBlacklisted(
          result.user.email ?? account.email)) {
        return;
      }
      if (!mounted) return;
      showAuthToast(context, 'Login successful');
      await _afterSignIn(result.user.uid);
    } on AuthError catch (e) {
      if (!mounted) return;
      final code = e.code;
      // v1.0.110: account-exists is now auto-linked inside
      // signInWithGoogleIdToken — reaching here means the worker refused
      // (bad token etc.), so keep the explanatory message.
      if (code == 'auth/blacklisted') {
        showAuthToast(context, AccountProtection.blacklistedMessage(),
            isError: true);
      } else if (code == 'auth/account-exists-with-different-credential') {
        showAuthToast(
          context,
          'Could not link this Google account. Please try again or use email login.',
          isError: true,
        );
      } else if (code == 'auth/google-account-creation-blocked') {
        showAuthToast(
          context,
          'No account found for this Google account. Please sign up first.',
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
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Image.asset(
            'assets/images/auth_illust_login.png',
            height: 130,
            fit: BoxFit.contain,
          ),
        ),
        _googleButton(),
        const AuthDivider(),
        AuthEmailButton(
            onPressed: () => setState(() => _showEmailFields = true)),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // NOTE-11: migrated accounts without a password claim one here.
            TextButton(
              onPressed: () => context.push('/claim-password',
                  extra: _email.text.trim()),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppLanguage.tr('Set Your Password', 'पासवर्ड सेट गर्नुहोस्'),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D4ED8)),
              ),
            ),
            TextButton(
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
          ],
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
    // Transparent status bar with dark icons so the light background flows
    // under the clock — same edge-to-edge treatment as home pages; kills
    // the dark band that used to sit above the login screen.
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
              title: 'Welcome Back',
              subtitle: 'Sign in to continue your Loksewa preparation journey',
              child: Shake(
                controller: _shakeController,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _showEmailFields ? _expanded() : _collapsed(),
                ),
              ),
            ),
            // Dim only while Google Sign-In is in flight (button carries its
            // own spinner; the white-card popup was removed per user request).
            if (_googleLoading)
              Container(color: Colors.black.withValues(alpha: 0.18)),
          ],
        ),
      ),
    );
  }
}
