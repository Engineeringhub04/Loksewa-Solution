import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Privacy Policy — mirrors app/privacy-policy.tsx.
/// Readable in-app summary in five sections + the full hosted policy URL.
/// (The outbound link renders as text: url_launcher is not a dependency.)
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = [
    (
      Icons.description_outlined,
      'What we collect',
      'Your name, email address and — only if you choose to add them — your date of birth, gender and profile photo. We also store your selected course so the app can show relevant content.'
    ),
    (
      Icons.bar_chart_outlined,
      'Study data',
      'Your quiz and mock test attempts, scores, bookmarks and notes are saved to your account so your progress follows you across devices.'
    ),
    (
      Icons.lock_outline,
      'How it is protected',
      'Your data is stored in Google Firebase and is readable only by your own signed-in account. We never sell your personal information to anyone.'
    ),
    (
      Icons.share_outlined,
      'What we never do',
      'We do not sell, rent or trade your personal data. Aggregated, anonymous statistics may be used to improve the app, but these can never identify you.'
    ),
    (
      Icons.delete_outline,
      'Your control',
      'You can edit your profile at any time, and you can permanently delete your account and its data from Profile → Delete Account.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Privacy Policy'),
          Expanded(
            child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.navy,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Privacy Policy',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your privacy matters. Here is exactly what Loksewa Solution stores and why.',
                    style:
                        TextStyle(color: Color(0xFFD7E3FF), height: 1.5),
                  ),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text('No data selling',
                            style: TextStyle(fontSize: 12)),
                        backgroundColor: Colors.white24,
                      ),
                      Chip(
                        label: Text('You can delete it all',
                            style: TextStyle(fontSize: 12)),
                        backgroundColor: Colors.white24,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(s.$1, color: AppColors.navy),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.$2,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                s.$3,
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
              )),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Full policy',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  SelectableText(
                    'https://www.kbr.com.np/privacy',
                    style: TextStyle(color: AppColors.navy, fontSize: 14),
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
}
