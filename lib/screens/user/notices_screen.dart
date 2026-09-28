import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Notices list — mirrors app/notices.tsx.
///
/// Reads `app_notices` (newest first, `status != 'hidden'` filtered
/// client-side). Intro card shows the count + latest date; tapping a card
/// opens the detail screen with the document passed along.
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final idToken = await AuthService.getValidIdToken() ?? '';
    final rows = await FirestoreRest.listDocuments('app_notices',
        idToken: idToken, pageSize: 100);
    final items =
        rows.where((n) => (n['status'] ?? '').toString() != 'hidden').toList();
    items.sort((a, b) {
      final pa = a['publishedAt'];
      final pb = b['publishedAt'];
      final ta = pa is DateTime ? pa.millisecondsSinceEpoch : 0;
      final tb = pb is DateTime ? pb.millisecondsSinceEpoch : 0;
      return tb.compareTo(ta);
    });
    return items;
  }

  String _keyOf(Map<String, dynamic> n) {
    for (final k in ['slug', 'id']) {
      final v = (n[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _dateLabel(Map<String, dynamic> n) {
    final label = (n['dateLabel'] ?? '').toString();
    if (label.isNotEmpty) return label;
    final p = n['publishedAt'];
    if (p is DateTime) return '${p.day}/${p.month}/${p.year}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Notices'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                    Text('Failed to load notices:\n${snap.error}',
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
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  color: AppColors.navy,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.campaign,
                            color: Colors.white, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${items.length} notices',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              if (items.isNotEmpty)
                                Text(
                                  'Latest: ${_dateLabel(items.first)}',
                                  style: const TextStyle(
                                      color: Colors.white70),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No notices published yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                for (final n in items)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.article,
                          color: AppColors.navy),
                      title: Text((n['title'] ?? '').toString(),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((n['excerpt'] ?? '').toString().isNotEmpty)
                            Text((n['excerpt'] ?? '').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if ((n['kind'] ?? '').toString().isNotEmpty)
                                Chip(
                                  label: Text((n['kind'] ?? '').toString(),
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              if ((n['kind'] ?? '').toString().isNotEmpty)
                                const SizedBox(width: 6),
                              Text(_dateLabel(n),
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                      trailing:
                          const Icon(Icons.chevron_right),
                      onTap: () {
                        final key = _keyOf(n);
                        if (key.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Could not open this notice.')),
                          );
                          return;
                        }
                        context.push('/notice/$key', extra: n);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}
