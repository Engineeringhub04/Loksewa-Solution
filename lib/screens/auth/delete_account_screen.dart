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
/// Warning card → "what you will lose" list → account email → type DELETE
/// to confirm → danger button → destructive [AppModalShell] confirm →
/// profile doc deleted first, then the Firebase Auth identity itself
/// ([AuthService.deleteCurrentAccount]), success toast, back to /login.
///
/// When offline the confirm field and delete button are hidden and only a
/// warning line + Cancel remain (same as React).
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
                  padding: const EdgeInsets.all(16),
                  children: [
                    SyllabusEntrance(
                      delayMs: 0,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: danger.withValues(alpha: 0x14 / 0xFF),
                          border: Border.all(color: danger),
                          // React radius.lg (20) on the warning box.
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 26, color: danger),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLanguage.tr('This cannot be undone',
                                        'यो फिर्ता गर्न मिल्दैन'),
                                    style: TextStyle(
                                        color: danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLanguage.tr(
                                      'Deleting your account permanently removes your profile and study data.',
                                      'खाता मेट्दा तपाईंको प्रोफाइल र अध्ययन डाटा सधैंको लागि हट्नेछ।',
                                    ),
                                    style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SyllabusEntrance(
                      delayMs: 60,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguage.tr('What you will lose',
                                    'तपाईंले गुमाउने कुराहरू'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              ..._losses.map((l) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Icon(l.$1, size: 18, color: danger),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            AppLanguage.tr(l.$2, l.$3),
                                            style: TextStyle(
                                                color: palette.textSecondary,
                                                fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (user?.email != null) ...[
                      const SizedBox(height: 12),
                      SyllabusEntrance(
                        delayMs: 120,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            // React colors.surfaceAlt — theme-aware so the
                            // email stays readable in both themes (the old
                            // fixed light-grey box washed the text out).
                            color: palette.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguage.tr(
                                    'Account to be deleted', 'मेटिने खाता'),
                                style: TextStyle(
                                    color: palette.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user!.email!,
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
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (offline)
                      SyllabusEntrance(
                        delayMs: 180,
                        child: Text(
                          AppLanguage.tr(
                              'No internet connection', 'इन्टरनेट जडान छैन'),
                          style:
                              TextStyle(color: palette.warning, fontSize: 13),
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
                            prefixIcon: const Icon(Icons.error_outline_rounded,
                                size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
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
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
