import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// App Info — mirrors app/app-info.tsx.
/// Identity block, About section, "What you get" highlights, Reach us,
/// Follow us, Legal. No build/package internals — only the app version.
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  static const _highlights = [
    (Icons.library_books_outlined, 'Complete syllabus',
        'Subject-wise notes and chapters mapped to the Loksewa syllabus.'),
    (Icons.timer_outlined, 'Mock tests & quizzes',
        'Timed practice with instant scoring and detailed explanations.'),
    (Icons.newspaper_outlined, 'Daily current affairs',
        'Gorkhapatra highlights and a fresh question every day.'),
    (Icons.bar_chart_outlined, 'Progress analytics',
        'See your strong and weak subjects as you prepare.'),
    (Icons.people_outlined, 'Discussion forum',
        'Ask questions and learn together with other aspirants.'),
  ];

  static const _socials = [
    ('Facebook', 'https://www.facebook.com/profile.php?id=61580182268110'),
    ('YouTube', 'https://www.youtube.com/loksewasolution0'),
    ('Instagram', 'https://www.instagram.com/loksewasolution'),
    ('X', 'https://x.com/loksewa_soln'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'App Info'),
          Expanded(
            child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 108,
                      height: 108,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Loksewa Solution',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Prepare Smarter, Score Higher',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Chip(
                    label: Text('Version 1.0.0'),
                    avatar: Icon(Icons.check_circle,
                        size: 18, color: AppColors.navy),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'About',
            children: const [
              Text(
                "Nepal's trusted digital preparation platform for Loksewa and other competitive government exams.",
                style: TextStyle(
                    color: Colors.grey, fontSize: 15, height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'What you get',
            children: _highlights
                .map((h) => ListTile(
                      leading: Icon(h.$1, color: AppColors.navy),
                      title: Text(h.$2,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(h.$3),
                      contentPadding: EdgeInsets.zero,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Reach us',
            children: const [
              ListTile(
                leading: Icon(Icons.language, color: AppColors.navy),
                title: Text('Website'),
                subtitle: Text('kbr.com.np'),
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: Icon(Icons.mail_outline, color: AppColors.navy),
                title: Text('Support'),
                subtitle: Text('contact@kbr.com.np'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Follow Us',
            children: _socials
                .map((s) => ListTile(
                      title: Text(s.$1),
                      subtitle: Text(s.$2,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      contentPadding: EdgeInsets.zero,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Legal',
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined,
                    color: AppColors.navy),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: EdgeInsets.zero,
                onTap: () => context.push('/privacy-policy'),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined,
                    color: AppColors.navy),
                title: const Text('Terms & Conditions'),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: EdgeInsets.zero,
                onTap: () => context.push('/terms-conditions'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Made for Nepali students 🇳🇵',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
      {required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
