import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Terms & Conditions — mirrors app/terms-conditions.tsx.
/// Premium redesign: gradient hero, numbered clause cards (each with its own
/// icon + tone and a §n pill) and the online-version URL. The eight clauses
/// and the outbound link are unchanged.
///
/// NOTE: the clause copy stays English-only on purpose — React's documented
/// decision, because the hosted terms it mirrors are English. Only the
/// screen title and UI chrome (subtitle, pills, buttons) are localised.
/// The outbound link is display-only (no url_launcher): the button copies
/// the URL to the clipboard.
class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key});

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  static const _termsUrl = 'https://www.kbr.com.np/terms';

  static const _terms = [
    (
      Icons.phone_android_outlined,
      Color(0xFF2563EB),
      'Using this app',
      'Loksewa Solution is a study aid for Nepali government (Loksewa) exam preparation. You agree to use it for your own personal, non-commercial preparation.'
    ),
    (
      Icons.account_circle_outlined,
      Color(0xFF0EA5E9),
      'Your account',
      'You are responsible for keeping your login credentials secure and for all activity that happens under your account. Please keep your profile information accurate.'
    ),
    (
      Icons.library_books_outlined,
      Color(0xFF8B5CF6),
      'Study content',
      'Questions, notes and current affairs are provided for practice only. While we work hard on accuracy, we cannot guarantee that every item matches the official syllabus or exam. Always confirm against official sources.'
    ),
    (
      Icons.error_outline,
      Color(0xFFD97706),
      'No result guarantee',
      'Using this app does not guarantee success in any examination. Your results depend on your own preparation.'
    ),
    (
      Icons.pan_tool_outlined,
      Color(0xFFDC2626),
      'Fair use',
      'Do not copy, resell, redistribute or scrape the content, attempt to break the app or its security, or post abusive material in discussions.'
    ),
    (
      Icons.forum_outlined,
      Color(0xFF0EA5E9),
      'Community discussions',
      'You own what you post, but you grant us permission to display it in the app. We may remove content that is abusive, misleading or off-topic.'
    ),
    (
      Icons.refresh_outlined,
      Color(0xFF16A34A),
      'Changes',
      'Features and these terms may be updated as the app grows. Continued use after an update means you accept the revised terms.'
    ),
    (
      Icons.mail_outline,
      Color(0xFF2563EB),
      'Contact',
      'Questions about these terms? Reach us at contact@kbr.com.np.'
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

  void _copyTermsUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: _termsUrl));
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
              title:
                  AppLanguage.tr('Terms & Conditions', 'नियम र सर्तहरू')),
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
                ..._terms.asMap().entries.map((e) {
                  final i = e.key;
                  final t = e.value;
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
                                color: t.$2.withValues(alpha: 0.12),
                              ),
                              child: Icon(t.$1, size: 21, color: t.$2),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          // English-only by React's
                                          // documented decision (the hosted
                                          // terms are English).
                                          AppLanguage.tr(t.$3, t.$3),
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: palette.textPrimary),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      StatusPill(
                                        label: '§${i + 1}',
                                        color: t.$2,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppLanguage.tr(t.$4, t.$4),
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
                  delayMs: 9 * 60,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius:
                          BorderRadius.circular(ExpoRadius.lg),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: palette.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            _termsUrl,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: palette.info, fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _copyTermsUrl(context),
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: Text(AppLanguage.tr('View online version',
                              'अनलाइन संस्करण हेर्नुहोस्')),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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

  /// Gradient hero with decorative rings, glass document tile, subtitle and
  /// the clause-count pill.
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
                        child: const Icon(Icons.description_outlined,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          AppLanguage.tr(
                              'Terms & Conditions', 'नियम र सर्तहरू'),
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
                      'Please read these terms before continuing to use Loksewa Solution.',
                      'Loksewa Solution प्रयोग जारी राख्नुअघि यी सर्तहरू पढ्नुहोस्।',
                    ),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.55,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  StatusPill(
                    label: AppLanguage.tr('8 clauses', '८ वटा बुँदा'),
                    color: const Color(0xFF7DD3FC),
                    icon: Icons.list_outlined,
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
}
