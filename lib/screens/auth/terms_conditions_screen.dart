import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Terms & Conditions — mirrors app/terms-conditions.tsx.
/// Eight numbered clauses + the online version URL (rendered as text:
/// url_launcher is not a dependency).
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const _terms = [
    (
      Icons.phone_android_outlined,
      'Using this app',
      'Loksewa Solution is a study aid for Nepali government (Loksewa) exam preparation. You agree to use it for your own personal, non-commercial preparation.'
    ),
    (
      Icons.person_outline,
      'Your account',
      'You are responsible for keeping your login credentials secure and for all activity that happens under your account. Please keep your profile information accurate.'
    ),
    (
      Icons.library_books_outlined,
      'Study content',
      'Questions, notes and current affairs are provided for practice only. While we work hard on accuracy, we cannot guarantee that every item matches the official syllabus or exam. Always confirm against official sources.'
    ),
    (
      Icons.warning_amber_outlined,
      'No result guarantee',
      'Using this app does not guarantee success in any examination. Your results depend on your own preparation.'
    ),
    (
      Icons.pan_tool_outlined,
      'Fair use',
      'Do not copy, resell, redistribute or scrape the content, attempt to break the app or its security, or post abusive material in discussions.'
    ),
    (
      Icons.forum_outlined,
      'Community discussions',
      'You own what you post, but you grant us permission to display it in the app. We may remove content that is abusive, misleading or off-topic.'
    ),
    (
      Icons.refresh_outlined,
      'Changes',
      'Features and these terms may be updated as the app grows. Continued use after an update means you accept the revised terms.'
    ),
    (
      Icons.mail_outline,
      'Contact',
      'Questions about these terms? Reach us at contact@kbr.com.np.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Terms & Conditions'),
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
                    'Terms & Conditions',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please read these terms before continuing to use Loksewa Solution.',
                    style:
                        TextStyle(color: Color(0xFFD7E3FF), height: 1.5),
                  ),
                  SizedBox(height: 12),
                  Chip(
                    label:
                        Text('8 clauses', style: TextStyle(fontSize: 12)),
                    backgroundColor: Colors.white24,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._terms.asMap().entries.map((e) {
            final i = e.key;
            final t = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(t.$1, color: AppColors.navy),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.$2,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Chip(
                                  label: Text('§${i + 1}',
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  visualDensity:
                                      VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.$3,
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
            );
          }),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Online version',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  SelectableText(
                    'https://www.kbr.com.np/terms',
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
