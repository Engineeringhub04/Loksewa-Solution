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
import '../../widgets/syllabus_entrance.dart';

/// Security Settings → Change Password.
///
/// Old / New / Confirm fields (obscured, FloatingLabelField style like the
/// auth screens). The change runs as a single POST /auth/change-password
/// on the loksewa-api (Phase-3): the worker verifies the old password
/// against the CF account and revokes the user's other sessions. The
/// stored session is never touched.
///
/// Validations (inline errors, EN + NE):
/// - old empty → prompt; wrong → "Old password is incorrect."
/// - new < 6 chars → min-length error
/// - new == old → "must be different" error
/// - confirm != new → mismatch error
///
/// "Update Password" opens an AppModalShell CONFIRMATION popup
/// ("Change your password?"); Confirm runs the change with a spinner
/// on the confirm button. Success → success state. A "Forgot Password?"
/// link under the button goes to `/forgot-password`.
///
/// Premium treatment: the shared gradient subpage header, the smooth
/// SyllabusEntrance on the form card (NOTE-24), a password-tips card
/// below the form, and surfaces that follow the app theme (NOTE-23).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    this.debugEmail,
    this.changePassword,
  });

  /// Test seam: user email instead of [AuthService.currentUser].
  final String? debugEmail;

  /// Test seam: replaces [ChangePasswordService.changePassword].
  final Future<PasswordChangeOutcome> Function(
      String oldPassword, String newPassword)? changePassword;

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

  Future<PasswordChangeOutcome> _change(
          String oldPassword, String newPassword) =>
      widget.changePassword?.call(oldPassword, newPassword) ??
      ChangePasswordService.changePassword(oldPassword, newPassword);

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

  /// Submits the old + new password to POST /auth/change-password.
  /// Wrong old password → inline error on the old field; anything else →
  /// error toast. Returns true only when the password was changed.
  Future<bool> _runChange() async {
    final outcome = await _change(_old.text, _new.text);
    if (!mounted) return false;
    switch (outcome) {
      case PasswordChangeOutcome.ok:
        setState(() => _success = true);
        return true;
      case PasswordChangeOutcome.wrongPassword:
        setState(() {
          _oldError = AppLanguage.tr('Old password is incorrect.',
              'पुरानो पासवर्ड गलत छ।');
        });
        return false;
      case PasswordChangeOutcome.error:
        showAuthToast(
            context,
            AppLanguage.tr('Something went wrong. Please try again.',
                'केही गलत भयो। कृपया पुनः प्रयास गर्नुहोस्।'),
            isError: true);
        return false;
    }
  }

  Widget _formCard() {
    // NOTE-23: the card follows the app theme like every other settings
    // page (palette surface/border/text), and the fields take
    // FloatingLabelField's dark variant in dark mode. Popups on this
    // page keep the pinned AppModalShell colors — pages only.
    final palette = ExpoPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_outline,
                    size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr(
                          'Choose a new password', 'नयाँ पासवर्ड छान्नुहोस्'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _email.isEmpty
                          ? AppLanguage.tr(
                              'Not signed in', 'साइन इन हुनुहुन्न')
                          : _email,
                      style: TextStyle(
                          fontSize: 13, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FloatingLabelField(
            label: AppLanguage.tr('Old Password', 'पुरानो पासवर्ड'),
            controller: _old,
            leftIcon: Icons.lock_outline,
            secureToggle: true,
            obscureText: true,
            dark: dark,
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
            dark: dark,
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
            dark: dark,
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
              // Logged-in entry: the account email rides along so the
              // reset page opens locked to it (NOTE-22 + reset lock).
              onPressed: () => _email.isEmpty
                  ? context.push('/forgot-password')
                  : context.push('/forgot-password', extra: _email),
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
    final palette = ExpoPalette.of(context);
    return SyllabusEntrance(
      delayMs: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4ADE80), Color(0xFF16A34A)],
                ),
                borderRadius: BorderRadius.circular(42),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.check, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              AppLanguage.tr('Password changed successfully',
                  'पासवर्ड सफलतापूर्वक परिवर्तन भयो'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLanguage.tr(
                'Use your new password the next time you sign in.',
                'अर्को पटक साइन इन गर्दा आफ्नो नयाँ पासवर्ड प्रयोग गर्नुहोस्।',
              ),
              style: TextStyle(fontSize: 14, color: palette.textSecondary),
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
      ),
    );
  }

  /// Password-tips card under the form — mirrors the inline validations so
  /// users see the rules before they trip on them. Premium treatment: a
  /// softly amber-tinted card, a gradient lightbulb tile, and one tinted
  /// icon chip per rule with a green check pill — the app's premium-card
  /// language, following the theme (NOTE-23).
  Widget _tipsCard() {
    final palette = ExpoPalette.of(context);
    const tips = [
      (Icons.straighten_outlined, 'At least 6 characters', 'कम्तीमा ६ अक्षर'),
      (Icons.difference_outlined, 'Different from your old password',
          'पुरानो पासवर्डभन्दा फरक'),
      (Icons.visibility_off_outlined, 'Never share it with anyone',
          'कसैसँग पनि साझा नगर्नुहोस्'),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.lightbulb_outline,
                    size: 21, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                AppLanguage.tr('Password tips', 'पासवर्ड सुझावहरू'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (icon, en, ne) in tips) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: palette.primary.withValues(alpha: 0.1),
                    ),
                    child: Icon(icon, size: 17, color: palette.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLanguage.tr(en, ne),
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: palette.textSecondary),
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          const Color(0xFF16A34A).withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 14, color: Color(0xFF16A34A)),
                  ),
                ],
              ),
            ),
          ],
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
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: SyllabusEntrance(
                  delayMs: 0,
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _success ? _successCard() : _formCard(),
                      ),
                      if (!_success) ...[
                        const SizedBox(height: 12),
                        SyllabusEntrance(
                          delayMs: 140,
                          child: _tipsCard(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
