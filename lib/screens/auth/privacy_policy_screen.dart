import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/trash_icon.dart';

/// Privacy Policy — mirrors app/privacy-policy.tsx.
/// Premium redesign: gradient hero, tone-coded section cards and an
/// accent-spined "full policy" panel. All five sections + the hosted policy
/// URL are unchanged.
///
/// NOTE: the section copy stays English-only on purpose — React's documented
/// decision, because the hosted policy it summarises is English. Only the
/// screen title and UI chrome (pills, subtitle, buttons) are localised.
/// The outbound link is display-only (no url_launcher): the button copies the
/// URL to the clipboard.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  static const _policyUrl = 'https://www.kbr.com.np/privacy';

  static const _sections = [
    (
      Icons.description_outlined,
      Color(0xFF2563EB),
      'What we collect',
      'Your name, email address and — only if you choose to add them — your date of birth, gender and profile photo. We also store your selected course so the app can show relevant content.'
    ),
    (
      Icons.bar_chart_outlined,
      Color(0xFF0EA5E9),
      'Study data',
      'Your quiz and mock test attempts, scores, bookmarks and notes are saved to your account so your progress follows you across devices.'
    ),
    (
      Icons.lock_outline,
      Color(0xFF16A34A),
      'How it is protected',
      'Your data is stored in Google Firebase and is readable only by your own signed-in account. We never sell your personal information to anyone.'
    ),
    (
      Icons.share_outlined,
      Color(0xFFD97706),
      'What we never do',
      'We do not sell, rent or trade your personal data. Aggregated, anonymous statistics may be used to improve the app, but these can never identify you.'
    ),
    (
      null,
      Color(0xFFDC2626),
      'Your control',
      'You can edit your profile at any time, and you can permanently delete your account and its data from Profile → Delete Account.'
    ),
  ];

  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
  }

  void _copyPolicyUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: _policyUrl));
    showToast(
      context,
      AppLanguage.tr('Link copied', 'लिङ्क प्रतिलिपि भयो'),
      ToastVariant.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Privacy Policy', 'गोपनीयता नीति')),
          Expanded(
            child: _preloading
                ? _preloadingBody()
                : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                SyllabusEntrance(
                  delayMs: 0,
                  child: _hero(),
                ),
                const SizedBox(height: 16),
                ..._sections.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SyllabusEntrance(
                      delayMs: (i + 1) * 60,
                      child: _surfaceCard(
                        context,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                color: s.$2.withValues(alpha: 0.12),
                              ),
                              child: s.$1 != null
                                  ? Icon(s.$1, size: 21, color: s.$2)
                                  : TrashIcon(size: 21, color: s.$2),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    // English-only by React's documented
                                    // decision (the hosted policy is English).
                                    AppLanguage.tr(s.$3, s.$3),
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: palette.textPrimary),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppLanguage.tr(s.$4, s.$4),
                                    style: TextStyle(
                                        color: palette.textSecondary,
                                        height: 1.55,
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                SyllabusEntrance(
                  delayMs: 6 * 60,
                  child: _policyLinkCard(context, palette),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 1s preloading shimmer shown on first build before the page content.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
    );
  }

  /// Gradient hero with decorative rings, glass shield tile, subtitle and
  /// the two reassurance pills.
  Widget _hero() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1D4ED8),
            Color(0xFF2563EB),
            Color(0xFF3B82F6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.28),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        child: const Icon(Icons.shield_outlined,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          AppLanguage.tr('Privacy Policy', 'गोपनीयता नीति'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLanguage.tr(
                      'Your privacy matters. Here is exactly what Loksewa Solution stores and why.',
                      'तपाईंको गोपनीयता महत्त्वपूर्ण छ। Loksewa Solution ले के भण्डार गर्छ र किन गर्छ, यहाँ स्पष्ट छ।',
                    ),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.55,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusPill(
                        label: AppLanguage.tr(
                            'No data selling', 'डाटा बिक्री हुँदैन'),
                        color: const Color(0xFF4ADE80),
                        icon: Icons.check_circle_outline,
                      ),
                      StatusPill(
                        label: AppLanguage.tr(
                            'You can delete it all', 'सबै मेट्न सक्नुहुन्छ'),
                        color: const Color(0xFF7DD3FC),
                        icon: Icons.delete_outline,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Theme-aware surface card: white + hairline border + soft shadow in
  /// light, raised surface + border in dark.
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

  /// "Full policy" panel with an info-coloured accent spine, the selectable
  /// URL and the copy-link button (display-only: no url_launcher).
  Widget _policyLinkCard(BuildContext context, ExpoPalette palette) {
    const tone = Color(0xFF0EA5E9);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: palette.border),
      ),
      // Clip the spine to the card's curve: the spine's square inner
      // corners would otherwise poke ~2px past the rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: const BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(ExpoRadius.lg),
                    bottomLeft: Radius.circular(ExpoRadius.lg),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: tone.withValues(alpha: 0.12),
                            ),
                            child: const Icon(Icons.language_outlined,
                                size: 20, color: tone),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            AppLanguage.tr('Full policy', 'पूर्ण नीति'),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: palette.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: palette.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          _policyUrl,
                          style: TextStyle(color: palette.info, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _copyPolicyUrl(context),
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: Text(AppLanguage.tr(
                              'Read the full policy online',
                              'पूर्ण नीति अनलाइन पढ्नुहोस्')),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
