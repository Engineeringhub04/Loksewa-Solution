import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Notification detail — mirrors app/notification/[id].tsx.
///
/// Like the Expo screen, everything renders from the navigation payload
/// (passed via `extra`), not a fresh Firestore read: title, body, imageUrl
/// (tappable → viewer dialog), category, updatedNotice banner, createdAt,
/// and a deep-link button that routes through go_router.
class NotificationDetailScreen extends StatelessWidget {
  final String id;
  const NotificationDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final Map<String, dynamic> n =
        extra is Map ? Map<String, dynamic>.from(extra) : {};

    final title = (n['title'] ?? 'Notification').toString();
    final body = (n['preview'] ?? n['body'] ?? '').toString();
    final imageUrl = (n['imageUrl'] ?? '').toString();
    final category = (n['category'] ?? '').toString();
    final deepLink = (n['deepLink'] ?? '').toString();
    final updatedNotice = n['updatedNotice'] == true;
    final created = n['createdAt'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: n.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Notification details are unavailable.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (updatedNotice)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.update, color: AppColors.accent),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                'This notice has been updated. Please read it again.')),
                      ],
                    ),
                  ),
                if (imageUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (c) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(
                            imageUrl,
                            errorBuilder: (_, __, ___) => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('Image failed to load.'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(title,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (category.isNotEmpty) Chip(label: Text(category)),
                    if (created is DateTime)
                      Chip(
                          label: Text(
                              '${created.day}/${created.month}/${created.year}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (body.isNotEmpty)
                  Text(body, style: const TextStyle(height: 1.6)),
                if (deepLink.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => context.push(deepLink),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open link'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
