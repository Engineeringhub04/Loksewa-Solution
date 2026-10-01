import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/subpage_header.dart';

/// Notification detail — mirrors app/notification/[id].tsx.
///
/// Everything renders from the navigation payload passed by the inbox
/// (title, body, imageUrl, category, deepLink, updatedNotice, createdAtMs):
/// category + updated-notice tags, icon + title + time-ago header row,
/// tappable image (full-screen viewer), body, and the deep-link button.
class NotificationDetailScreen extends StatelessWidget {
  final String id;
  const NotificationDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final Map<String, dynamic> n =
        extra is Map ? Map<String, dynamic>.from(extra) : {};

    final title = (n['title'] ?? 'Notification').toString();
    final body = (n['body'] ?? n['preview'] ?? '').toString();
    final category = (n['category'] ?? '').toString().trim();
    final imageUrl = (n['imageUrl'] ?? '').toString();
    final deepLink = (n['deepLink'] ?? '').toString();
    final updatedNotice = n['updatedNotice'] == true;
    final createdAtMs = (n['createdAtMs'] as num?)?.toInt() ?? 0;
    final timestamp = createdAtMs > 0
        ? _timeAgo(DateTime.fromMillisecondsSinceEpoch(createdAtMs))
        : '';

    final palette = ExpoPalette.of(context);
    final primary = palette.primary;

    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Notification details'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (category.isNotEmpty)
                        _tag(context,
                            icon: _categoryIcon(category), label: category),
                      if (updatedNotice)
                        _tag(context,
                            icon: Icons.refresh_outlined,
                            label: 'Updated Notice'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary.withValues(alpha: 0x1F / 0xFF),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_categoryIcon(category),
                            size: 26, color: primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                title,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: ExpoType.h3,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (timestamp.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 3),
                                  child: Text(
                                    timestamp,
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: ExpoType.caption,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (imageUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: GestureDetector(
                        onTap: () => _openViewer(context, imageUrl),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(ExpoRadius.lg),
                          child: Container(
                            color: palette.surfaceAlt,
                            child: Image.network(
                              imageUrl,
                              width: double.infinity,
                              height: 220,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: SelectableText(
                        body,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: ExpoType.body,
                          height: 24 / 14,
                        ),
                      ),
                    ),
                  if (deepLink.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 24),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(ExpoRadius.md),
                            ),
                          ),
                          onPressed: () => context.push(deepLink),
                          icon: const Icon(Icons.open_in_new_outlined,
                              size: 18),
                          label: const Text('Click here',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context,
      {required IconData icon, required String label}) {
    final primary = ExpoPalette.of(context).primary;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExpoRadius.pill),
        color: primary.withValues(alpha: 0x18 / 0xFF),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: primary,
              fontSize: ExpoType.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _openViewer(BuildContext context, String url) {
    showImageViewer(context, NetworkImage(url));
  }
}

IconData _categoryIcon(String category) {
  final v = category.toLowerCase();
  if (v.contains('course') || v.contains('class')) {
    return Icons.school_outlined;
  }
  if (v.contains('mcq') || v.contains('test') || v.contains('exam')) {
    return Icons.assignment_outlined;
  }
  if (v.contains('report')) return Icons.flag_outlined;
  if (v.contains('update') || v.contains('version')) {
    return Icons.cloud_download_outlined;
  }
  if (v.contains('problem') || v.contains('maintenance')) {
    return Icons.build_outlined;
  }
  if (v.contains('result') || v.contains('achievement')) {
    return Icons.emoji_events_outlined;
  }
  if (v.contains('user') || v.contains('personal')) {
    return Icons.person_outlined;
  }
  return Icons.notifications_outlined;
}

const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'
];

/// Mirrors formatTimeAgo in src/core/notifications/timeAgo.ts (English).
String _timeAgo(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.isNegative) return 'Just now';
  final mins = diff.inMinutes;
  if (mins < 1) return 'Just now';
  final hours = mins ~/ 60;
  final days = hours ~/ 24;
  if (days > 30) {
    return '${createdAt.day} ${_enMonths[createdAt.month - 1]} ${createdAt.year}';
  }
  final String time;
  if (days >= 1) {
    time = '${days}d';
  } else if (hours >= 1) {
    time = '${hours}h';
  } else {
    time = '${mins}m';
  }
  return '$time ago';
}
