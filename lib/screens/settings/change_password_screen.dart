import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/change_password_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/auth/auth_buttons.dart';
import '../../widgets/auth/floating_label_field.dart';
import '../../widgets/popup_action_button.dart';
import '../../widgets/subpage_header.dart';

/// Security Settings → Change Password.
///
/// Old / New / Confirm fields (obscured, FloatingLabelField style like the
/// auth screens). Old-password verification re-authenticates with Identity
/// Toolkit `accounts:signInWithPassword`; the fresh idToken from that step
/// is then used for `accounts:update` with the new password. The stored
/// session is never touched.
///
/// Validations (inline errors, EN + NE):
/// - old empty → prompt; wrong → "Old password is incorrect."
/// - new < 6 chars → min-length error
/// - new == old → "must be different" error
/// - confirm != new → mismatch error
///
/// "Update Password" opens an AppModalShell CONFIRMATION popup
/// ("Change your password?"); Confirm runs verify → update with a spinner
/// on the confirm button. Success → success state. A "Forgot Password?"
/// link under the button goes to `/forgot-password`.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    this.debugEmail,
    this.verifyOldPassword,
    this.updatePassword,
  });

  /// Test seam: user email instead of [AuthService.currentUser].
  final String? debugEmail;

  /// Test seam: replaces [ChangePasswordService.verifyOldPassword].
  final Future<OldPasswordCheck> Function(String email, String oldPassword)?
      verifyOldPassword;

  /// Test seam: replaces [ChangePasswordService.updatePassword].
  final Future<bool> Function(String idToken, String newPassword)?
      updatePassword;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _blue = Color(0xFF1D4ED8);
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  String? _oldError;
  String? _newError;
  String? _confirmError;
  bool _success = false;

  String get _email =>
      widget.debugEmail ?? AuthService.currentUser?.email ?? '';

  Future<OldPasswordCheck> _verify(String email, String oldPassword) =>
      widget.verifyOldPassword?.call(email, oldPassword) ??
      ChangePasswordService.verifyOldPassword(email, oldPassword);

  Future<bool> _update(String idToken, String newPassword) =>
      widget.updatePassword?.call(idToken, newPassword) ??
      ChangePasswordService.updatePassword(idToken, newPassword);

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  /// Local (offline) validations. Returns true when the form is clean.
  bool _validateLocal() {
    final old = _old.text;
    final newPw = _new.text;
    final confirm = _confirm.text;
    var ok = true;
    if (old.isEmpty) {
      _oldError = AppLanguage.tr('Please enter your old password',
          'कृपया आफ्नो पुरानो पासवर्ड प्रविष्ट गर्नुहोस्');
      ok = false;
    }
    if (newPw.length < 6) {
      _newError = AppLanguage.tr('Password must be at least 6 characters',
          'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ');
      ok = false;
    } else if (newPw == old) {
      _newError = AppLanguage.tr(
          'New password must be different from the old password.',
          'नयाँ पासवर्ड पुरानो भन्दा फरक हुनुपर्छ।');
      ok = false;
    }
    if (confirm != newPw) {
      _confirmError =
          AppLanguage.tr('Passwords do not match', 'पासवर्डहरू मिलेनन्');
      ok = false;
    }
    setState(() {});
    return ok;
  }

  Future<void> _submit() async {
    setState(() {
      _oldError = null;
      _newError = null;
      _confirmError = null;
    });
    if (_email.isEmpty) {
      showAuthToast(
          context,
          AppLanguage.tr(
              'Please log in first', 'कृपया पहिले लगइन गर्नुहोस्'),
          isError: true);
      return;
    }
    if (!_validateLocal()) return;
    final confirmed = await _confirmPopup();
    if (confirmed != true || !mounted) return;
  }

  /// AppModalShell confirmation popup. Confirm runs the re-auth + update
  /// with a spinner on the confirm button; returns true only on success.
  Future<bool?> _confirmPopup() {
    return AppModalShell.show<bool>(
      context: context,
      builder: (modalContext) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) => AppModalShell(
            accent: _blue,
            accentMid: const Color(0xFF3B82F6),
            accentLight: const Color(0xFFBFDBFE),
            tagColor: _blue,
            tagLabel: AppLanguage.tr('SECURITY', 'सुरक्षा'),
            onClose: busy ? null : () => Navigator.of(ctx).pop(false),
            icon: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: _blue,
              ),
              child:
                  const Icon(Icons.lock_outline, size: 28, color: Colors.white),
            ),
            title: Text(
              AppLanguage.tr(
                  'Change your password?', 'आफ्नो पासवर्ड परिवर्तन गर्ने?'),
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
                'You will stay signed in on this device with the new password.',
                'नयाँ पासवर्डका साथ तपाईं यो डिभाइसमा साइन इन रहनुहुनेछ।',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF64748B),
                decoration: TextDecoration.none,
              ),
            ),
            footer: Row(
              children: [
                Expanded(
                  child: PopupCancelButton(
                    label: AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                    loading: busy,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PopupActionButton(
                    label: AppLanguage.tr('Confirm', 'पुष्टि गर्नुहोस्'),
                    backgroundColor: _blue,
                    loading: busy,
                    onTap: () async {
                      setModalState(() => busy = true);
                      final changed = await _runChange();
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop(changed);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Re-authenticates with the old password, then updates to the new one.
  /// Wrong old password → inline error on the old field; anything else →
  /// error toast. Returns true only when the password was changed.
  Future<bool> _runChange() async {
    final check = await _verify(_email, _old.text);
    if (!mounted) return false;
    if (!check.success) {
      if (check.wrongPassword) {
        setState(() {
          _oldError = AppLanguage.tr('Old password is incorrect.',
              'पुरानो पासवर्ड गलत छ।');
        });
      } else {
        showAuthToast(
            context,
            AppLanguage.tr('Something went wrong. Please try again.',
                'केही गलत भयो। कृपया पुनः प्रयास गर्नुहोस्।'),
            isError: true);
      }
      return false;
    }
    final ok = await _update(check.idToken!, _new.text);
    if (!mounted) return false;
    if (ok) {
      setState(() => _success = true);
      return true;
    }
    showAuthToast(
        context,
        AppLanguage.tr('Something went wrong. Please try again.',
            'केही गलत भयो। कृपया पुनः प्रयास गर्नुहोस्।'),
        isError: true);
    return false;
  }

  Widget _formCard() {
    // Always-white card (like AppModalShell): FloatingLabelField is an
    // always-light auth widget, so the form keeps the auth look in both
    // app themes.
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.mail_outline,
                  size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _email.isEmpty
                      ? AppLanguage.tr('Not signed in', 'साइन इन हुनुहुन्न')
                      : _email,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155)),
                ),
              ),
              const Icon(Icons.lock_outline,
                  size: 16, color: Color(0xFF94A3B8)),
            ],
          ),
          const SizedBox(height: 16),
          FloatingLabelField(
            label: AppLanguage.tr('Old Password', 'पुरानो पासवर्ड'),
            controller: _old,
            leftIcon: Icons.lock_outline,
            secureToggle: true,
            obscureText: true,
            errorText: _oldError,
            textInputAction: TextInputAction.next,
            nextFocus: _newFocus,
            onChanged: (_) {
              if (_oldError != null) setState(() => _oldError = null);
            },
          ),
          const SizedBox(height: 16),
          FloatingLabelField(
            label: AppLanguage.tr('New Password', 'नयाँ पासवर्ड'),
            controller: _new,
            focusNode: _newFocus,
            leftIcon: Icons.lock_outline,
            secureToggle: true,
            obscureText: true,
            errorText: _newError,
            textInputAction: TextInputAction.next,
            nextFocus: _confirmFocus,
            onChanged: (_) {
              if (_newError != null) setState(() => _newError = null);
            },
          ),
          const SizedBox(height: 16),
          FloatingLabelField(
            label: AppLanguage.tr('Confirm Password', 'पासवर्ड पुष्टि गर्नुहोस्'),
            controller: _confirm,
            focusNode: _confirmFocus,
            leftIcon: Icons.lock_outline,
            secureToggle: true,
            obscureText: true,
            errorText: _confirmError,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            onChanged: (_) {
              if (_confirmError != null) setState(() => _confirmError = null);
            },
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: AppLanguage.tr('Update Password', 'पासवर्ड अद्यावधिक गर्नुहोस्'),
            color: _blue,
            disabledColor: _blue,
            onPressed: _submit,
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => context.push('/forgot-password'),
              child: Text(
                AppLanguage.tr('Forgot Password?', 'पासवर्ड बिर्सनुभयो?'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _blue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(40),
            ),
            child:
                const Icon(Icons.check, size: 44, color: Color(0xFF16A34A)),
          ),
          const SizedBox(height: 16),
          Text(
            AppLanguage.tr('Password changed successfully',
                'पासवर्ड सफलतापूर्वक परिवर्तन भयो'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.tr(
              'Use your new password the next time you sign in.',
              'अर्को पटक साइन इन गर्दा आफ्नो नयाँ पासवर्ड प्रयोग गर्नुहोस्।',
            ),
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: AppLanguage.tr(
                'Back to Security Settings', 'सुरक्षा सेटिङमा फर्कनुहोस्'),
            color: _blue,
            disabledColor: _blue,
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/settings/security');
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: palette.background,
        body: Column(
          children: [
            SubpageHeader(
                title: AppLanguage.tr('Change Password', 'पासवर्ड परिवर्तन')),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _success ? _successCard() : _formCard(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
