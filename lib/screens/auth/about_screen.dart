import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// About — mirrors app/about.tsx.
/// Logo, app name, version, description, social links and legal entries.
/// (External links render as text: url_launcher is not a dependency.)
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _socials = [
    ('Facebook', 'https://www.facebook.com/profile.php?id=61580182268110'),
    ('YouTube', 'https://www.youtube.com/loksewasolution0'),
    ('Instagram', 'https://www.instagram.com/loksewasolution'),
    ('X', 'https://x.com/loksewa_soln'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loksewa Solution',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Version 1.0.0',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            "Nepal's trusted digital preparation platform for Loksewa and other competitive government exams.",
            style: TextStyle(color: Colors.grey, fontSize: 15, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text(
            'Follow Us',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ..._socials.map((s) => Card(
                child: ListTile(
                  title: Text(s.$1),
                  subtitle: Text(
                    s.$2,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              )),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                TextButton(
                  onPressed: () => context.push('/privacy-policy'),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(color: AppColors.navy),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/terms-conditions'),
                  child: const Text(
                    'Terms & Conditions',
                    style: TextStyle(color: AppColors.navy),
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
