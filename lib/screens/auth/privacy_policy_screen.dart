import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/trash_icon.dart';

/// Privacy Policy — mirrors app/privacy-policy.tsx.
/// Readable in-app summary in five tone-coded sections + the full hosted
/// policy URL.
///
/// NOTE: the section copy stays English-only on purpose — React's documented
/// decision, because the hosted policy it summarises is English. Only the
/// screen title is localised (React uses t('profile.privacyPolicy') for it).
/// The outbound link is display-only (no url_launcher): the button copies the
/// URL to the clipboard.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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

  void _copyPolicyUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: _policyUrl));
    showToast(context, 'Link copied', ToastVariant.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Privacy Policy', 'गोपनीयता नीति')),
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
                                    Icons.shield_outlined,
                                    color: Colors.white,
                                    size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLanguage.tr(
                                      'Privacy Policy', 'गोपनीयता नीति'),
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
                            'Your privacy matters. Here is exactly what Loksewa Solution stores and why.',
                            style: TextStyle(
                                color: Color(0xFFD7E3FF), height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              StatusPill(
                                label: 'No data selling',
                                color: Color(0xFF4ADE80),
                                icon: Icons.check_circle_outline,
                              ),
                              StatusPill(
                                label: 'You can delete it all',
                                color: Color(0xFF7DD3FC),
                                icon: Icons.delete_outline,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ..._sections.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
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
                                  color: s.$2.withValues(
                                      alpha: 0x14 / 0xFF),
                                ),
                                child: s.$1 != null
                                    ? Icon(s.$1,
                                        size: 19, color: s.$2)
                                    : TrashIcon(size: 19, color: s.$2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.$3,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      s.$4,
                                      style: const TextStyle(
                                          color: Colors.grey, height: 1.5),
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
                  delayMs: 6 * 60,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF0EA5E9)
                                      .withValues(alpha: 0x14 / 0xFF),
                                ),
                                child: const Icon(Icons.language_outlined,
                                    size: 19,
                                    color: Color(0xFF0EA5E9)),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Full policy',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const SelectableText(
                            _policyUrl,
                            style: TextStyle(
                                color: AppColors.navy, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _copyPolicyUrl(context),
                              icon: const Icon(Icons.copy_outlined,
                                  size: 18),
                              label: const Text(
                                  'Read the full policy online'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
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
