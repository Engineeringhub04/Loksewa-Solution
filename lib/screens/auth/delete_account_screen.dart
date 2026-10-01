import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';

/// Delete Account — mirrors app/delete-account.tsx.
///
/// Premium redesign (danger-gradient hero, loss list, account card) with the
/// delete flow kept byte-identical: warning → "what you will lose" list →
/// account email → type DELETE to confirm → danger button → destructive
/// [AppModalShell] confirm → profile doc deleted first, then the Firebase
/// Auth identity itself ([AuthService.deleteCurrentAccount]), success toast,
/// back to /login.
///
/// When offline the confirm field and delete button are hidden and only a
/// warning line + Cancel remain (same as React). The full-screen deleting
/// overlay (dim barrier above everything, incl. the header) is unchanged.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _confirmWord = 'DELETE';

  final _confirmText = TextEditingController();
  bool _deleting = false;
  bool? _offline;

  @override
  void initState() {
    super.initState();
    _checkOnline();
  }

  Future<void> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(
          () => _offline = results.every((r) => r == ConnectivityResult.none));
    } catch (_) {
      if (mounted) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _confirmText.dispose();
    super.dispose();
  }

  bool get _matches => _confirmText.text.trim().toUpperCase() == _confirmWord;

  Future<void> _askConfirm() async {
    // Theme-aware danger red (React colors.error: #DC2626 light / #F87171 dark).
    final danger = ExpoPalette.of(context).danger;
    final ok = await AppModalShell.show<bool>(
      context: context,
      builder: (ctx) => AppModalShell(
        accent: danger,
        accentMid: const Color(0xFFEF4444),
        accentLight: const Color(0xFFFECACA),
        tagColor: danger,
        tagLabel: AppLanguage.tr('DELETE', 'मेट्नुहोस्'),
        onClose: () => Navigator.of(ctx).pop(false),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: danger,
          ),
          child: const Icon(Icons.warning_amber_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr(
              'Delete account permanently?', 'खाता सधैंको लागि मेट्ने?'),
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
            'This is your last chance to cancel. Your account and data will be deleted immediately.',
            'रद्द गर्ने अन्तिम मौका। तपाईंको खाता र डाटा तुरुन्तै मेटिनेछ।',
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
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: Text(AppLanguage.tr(
                    'Delete My Account', 'मेरो खाता मेट्नुहोस्')),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _doDelete();
  }

  Future<void> _doDelete() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() => _deleting = true);
    try {
      // Remove the stored profile data first — once the auth identity is gone
      // the request would no longer be authorised to touch the document.
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument('users/${user.uid}', idToken: idToken)
          .catchError((_) {});
      // Then delete the Firebase Auth identity itself.
      await AuthService.deleteCurrentAccount();
      if (!mounted) return;
      showToast(
        context,
        AppLanguage.tr('Your account has been deleted', 'तपाईंको खाता मेटियो'),
        ToastVariant.success,
      );
      context.go('/login');
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppLanguage.tr('Could not delete your account. Please try again.',
            'खाता मेट्न सकिएन। पुनः प्रयास गर्नुहोस्।'),
        ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final offline = _offline == true;
    // Theme-aware palette (React useTheme colors): danger red, secondary
    // text and surfaceAlt all flip correctly between light and dark.
    final palette = ExpoPalette.of(context);
    final danger = palette.danger;
    final enabled = _matches && !_deleting;
    return Scaffold(
      // Stack (not Column): the deleting dim barrier sits ABOVE everything
      // including the header — same as React's full-screen PageLoaderOverlay
      // — so it never leaves white slivers at the header's curved corners.
      body: Stack(
        children: [
          Column(
            children: [
              SubpageHeader(
                  title: AppLanguage.tr('Delete Account', 'खाता मेट्नुहोस्')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    SyllabusEntrance(
                      delayMs: 0,
                      child: _dangerHero(danger),
                    ),
                    const SizedBox(height: 16),
                    SyllabusEntrance(
                      delayMs: 60,
                      child: _lossesCard(context, palette, danger),
                    ),
                    if (user?.email != null) ...[
                      const SizedBox(height: 16),
                      SyllabusEntrance(
                        delayMs: 120,
                        child: _accountCard(context, palette, user!.email!),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (offline)
                      SyllabusEntrance(
                        delayMs: 180,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            AppLanguage.tr('No internet connection',
                                'इन्टरनेट जडान छैन'),
                            style: TextStyle(
                                color: palette.warning, fontSize: 13),
                          ),
                        ),
                      )
                    else ...[
                      SyllabusEntrance(
                        delayMs: 180,
                        child: TextField(
                          controller: _confirmText,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: AppLanguage.tr(
                              'Type $_confirmWord to confirm',
                              'पुष्टि गर्न $_confirmWord टाइप गर्नुहोस्',
                            ),
                            prefixIcon: Icon(Icons.error_outline_rounded,
                                size: 20, color: danger),
                            filled: true,
                            fillColor: danger.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: danger, width: 1.5),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SyllabusEntrance(
                        delayMs: 240,
                        // React's danger Button: the red fill + white label
                        // stay the same when disabled — only the whole button
                        // dims to 50% opacity. Never a grey/white box.
                        child: Opacity(
                          opacity: enabled ? 1.0 : 0.5,
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: enabled ? _askConfirm : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: danger,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: danger,
                                disabledForegroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              child: Text(AppLanguage.tr(
                                  'Delete My Account', 'मेरो खाता मेट्नुहोस्')),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(
                        AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                        // React's text-variant Button uses colors.primary —
                        // theme-aware, readable on both themes.
                        style: TextStyle(color: palette.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_deleting)
            Container(
              color: Colors.black54,
              child: Center(
                child: PreloadingWidget(
                  label: AppLanguage.tr(
                      'Deleting your account...', 'खाता मेटिँदै...'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Danger-gradient hero with decorative rings and the irreversible-action
  /// warning.
  Widget _dangerHero(Color danger) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFDC2626),
            Color(0xFFB91C1C),
            Color(0xFF991B1B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -36,
              top: -36,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 58,
              bottom: -48,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguage.tr('This cannot be undone',
                              'यो फिर्ता गर्न मिल्दैन'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLanguage.tr(
                            'Deleting your account permanently removes your profile and study data.',
                            'खाता मेट्दा तपाईंको प्रोफाइल र अध्ययन डाटा सधैंको लागि हट्नेछ।',
                          ),
                          style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.88),
                              fontSize: 14,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Theme-aware surface card used for the losses list and the account box.
  Widget _surfaceCard(BuildContext context, {required Widget child}) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: palette.border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }

  /// "What you will lose" — the same four losses as React, as divided rows.
  Widget _lossesCard(
      BuildContext context, ExpoPalette palette, Color danger) {
    return _surfaceCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLanguage.tr('What you will lose', 'तपाईंले गुमाउने कुराहरू'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _losses.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: palette.divider, indent: 28),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Icon(_losses[i].$1, size: 19, color: danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLanguage.tr(_losses[i].$2, _losses[i].$3),
                      style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 14,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The signed-in account that will be deleted.
  Widget _accountCard(
      BuildContext context, ExpoPalette palette, String email) {
    return _surfaceCard(
      context,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: palette.primary.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.account_circle_outlined,
                size: 22, color: palette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr('Account to be deleted', 'मेटिने खाता'),
                  style: TextStyle(
                      color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// (icon, English loss line, Nepali loss line) — same four losses as React.
const _losses = [
  (
    Icons.account_circle_outlined,
    'Your profile, name, photo and course selection',
    'तपाईंको प्रोफाइल, नाम, फोटो र कोर्स छनोट',
  ),
  (
    Icons.bar_chart_outlined,
    'All quiz and mock test results and analytics',
    'सबै क्विज र मक टेस्टका नतिजा र विश्लेषण',
  ),
  (
    Icons.bookmark_outline,
    'Saved bookmarks, notes and downloads',
    'सेभ गरिएका बुकमार्क, नोट र डाउनलोड',
  ),
  (
    Icons.forum_outlined,
    'Access to your discussion posts and comments',
    'तपाईंका छलफल पोस्ट र कमेन्टमा पहुँच',
  ),
];
