import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Notifications inbox — mirrors app/notifications.tsx.
///
/// Merges the personal inbox (`users/{uid}/notifications`) with the global
/// feed (`app_global_notification`, excluding `segment == 'nonlogin'`
/// campaigns). Read state is tracked locally in SharedPreferences (the same
/// approach the Expo app uses for global notifications) because the REST list
/// API does not return document ids needed for server-side mark-read.
/// Tapping a row opens the detail screen with the full payload passed along.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  Set<String> _readIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String get _readKey =>
      'loksewa:notificationReadIds:${AuthService.currentUser?.uid ?? 'guest'}';

  String _itemKey(Map<String, dynamic> n) {
    final created = n['createdAt'];
    final ms = created is DateTime ? created.millisecondsSinceEpoch : 0;
    return "${n['_source']}:${n['title']}:$ms";
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final uid = AuthService.currentUser?.uid;
    final idToken = await AuthService.getValidIdToken() ?? '';

    final results = await Future.wait([
      uid == null
          ? Future.value(<Map<String, dynamic>>[])
          : FirestoreRest.listDocuments('users/$uid/notifications',
              idToken: idToken),
      FirestoreRest.listDocuments('app_global_notification',
          idToken: idToken),
    ]);

    final personal = results[0]
        .map((n) => {...n, '_source': 'personal'})
        .toList();
    final global = results[1]
        .where((n) => (n['segment'] ?? '').toString() != 'nonlogin')
        .map((n) => {
              ...n,
              '_source': 'global',
              // Mirror notifications.ts: global rows fall back through bodyLogin/body.
              'preview': (n['preview'] ?? n['bodyLogin'] ?? n['body'] ?? '')
                  .toString(),
            })
        .toList();

    final raw = await PrefsService.getString(_readKey);
    final List stored = raw == null || raw.isEmpty ? [] : json.decode(raw);
    _readIds = stored.map((e) => e.toString()).toSet();

    final all = [...personal, ...global];
    all.sort((a, b) {
      final ca = a['createdAt'];
      final cb = b['createdAt'];
      final ta = ca is DateTime ? ca.millisecondsSinceEpoch : 0;
      final tb = cb is DateTime ? cb.millisecondsSinceEpoch : 0;
      return tb.compareTo(ta);
    });
    return all;
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    final key = _itemKey(n);
    if (_readIds.contains(key)) return;
    _readIds = {..._readIds, key};
    await PrefsService.setString(_readKey, json.encode(_readIds.toList()));
    setState(() {});
  }

  Future<void> _markAllRead(List<Map<String, dynamic>> items) async {
    _readIds = {..._readIds, ...items.map(_itemKey)};
    await PrefsService.setString(_readKey, json.encode(_readIds.toList()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        actions: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) => TextButton(
              onPressed: (snap.hasData && snap.data!.isNotEmpty)
                  ? () => _markAllRead(snap.data!)
                  : null,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load notifications:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No notifications yet.\nImportant updates will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final n = items[i];
                final read = _readIds.contains(_itemKey(n));
                final created = n['createdAt'];
                return Card(
                  color: read ? null : AppColors.navy.withValues(alpha: 0.05),
                  child: ListTile(
                    leading: n['imageUrl'] != null &&
                            (n['imageUrl'] ?? '').toString().isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              (n['imageUrl'] ?? '').toString(),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.notifications,
                                  color: AppColors.navy),
                            ),
                          )
                        : const Icon(Icons.notifications,
                            color: AppColors.navy),
                    title: Text(
                      (n['title'] ?? 'Notification').toString(),
                      style: TextStyle(
                          fontWeight:
                              read ? FontWeight.normal : FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((n['preview'] ?? '').toString(),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if ((n['category'] ?? '').toString().isNotEmpty)
                              Text((n['category'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            if ((n['category'] ?? '').toString().isNotEmpty &&
                                created is DateTime)
                              const Text(' · ',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            if (created is DateTime)
                              Text(
                                  '${created.day}/${created.month}/${created.year}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            if (n['updatedNotice'] == true) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.update,
                                  size: 14, color: AppColors.accent),
                            ],
                          ],
                        ),
                      ],
                    ),
                    trailing: read
                        ? null
                        : const Icon(Icons.circle,
                            size: 10, color: AppColors.accent),
                    onTap: () {
                      _markRead(n);
                      context.push('/notification/${Uri.encodeComponent(_itemKey(n))}',
                          extra: n);
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
