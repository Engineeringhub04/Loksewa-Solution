import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Terms & Conditions — mirrors app/terms-conditions.tsx.
/// Eight numbered clauses (each with its own icon + tone and a §n pill),
/// plus the online-version URL.
///
/// NOTE: the clause copy stays English-only on purpose — React's documented
/// decision, because the hosted terms it mirrors are English. Only the
/// screen title is localised (React uses t('profile.termsConditions')).
/// The outbound link is display-only (no url_launcher): the button copies
/// the URL to the clipboard.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

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

  void _copyTermsUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: _termsUrl));
    showToast(context, 'Link copied', ToastVariant.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title:
                  AppLanguage.tr('Terms & Conditions', 'नियम र सर्तहरू')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SyllabusEntrance(
                  delayMs: 0,
                  child: Card(
                    color: AppColors.navy,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white
                                      .withValues(alpha: 0x1F / 0xFF),
                                ),
                                child: const Icon(
                                    Icons.description_outlined,
                                    color: Colors.white,
                                    size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLanguage.tr('Terms & Conditions',
                                      'नियम र सर्तहरू'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please read these terms before continuing to use Loksewa Solution.',
                            style: TextStyle(
                                color: Color(0xFFD7E3FF), height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          const StatusPill(
                            label: '8 clauses',
                            color: Color(0xFF7DD3FC),
                            icon: Icons.list_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ..._terms.asMap().entries.map((e) {
                  final i = e.key;
                  final t = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SyllabusEntrance(
                      delayMs: (i + 1) * 60,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.$2.withValues(
                                      alpha: 0x14 / 0xFF),
                                ),
                                child: Icon(t.$1, size: 19, color: t.$2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t.$3,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.bold),
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
                                      t.$4,
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                SyllabusEntrance(
                  delayMs: 9 * 60,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _copyTermsUrl(context),
                      icon:
                          const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('View online version'),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
}
