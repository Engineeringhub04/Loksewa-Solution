import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Gorkhapatra Loksewa posts — mirrors app/gorkhapatra/index.tsx.
///
/// Reads the `gorkhapatra` collection (document id == slug), newest first,
/// `status != 'hidden'` filtered client-side. Intro card + source notice, and
/// client-side load-more pagination.
class GorkhapatraScreen extends StatefulWidget {
  const GorkhapatraScreen({super.key});

  @override
  State<GorkhapatraScreen> createState() => _GorkhapatraScreenState();
}

class _GorkhapatraScreenState extends State<GorkhapatraScreen> {
  static const _pageSize = 12;
  late Future<List<Map<String, dynamic>>> _future;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final idToken = await AuthService.getValidIdToken() ?? '';
    final rows = await FirestoreRest.listDocuments('gorkhapatra',
        idToken: idToken, pageSize: 100);
    final items =
        rows.where((p) => (p['status'] ?? '').toString() != 'hidden').toList();
    items.sort((a, b) {
      final pa = a['publishedAt'];
      final pb = b['publishedAt'];
      final ta = pa is DateTime ? pa.millisecondsSinceEpoch : 0;
      final tb = pb is DateTime ? pb.millisecondsSinceEpoch : 0;
      return tb.compareTo(ta);
    });
    return items;
  }

  String _slugOf(Map<String, dynamic> p) {
    for (final k in ['slug', 'id']) {
      final v = (p[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _dateLabel(Map<String, dynamic> p) {
    final label = (p['dateLabel'] ?? '').toString();
    if (label.isNotEmpty) return label;
    final d = p['publishedAt'];
    if (d is DateTime) return '${d.day}/${d.month}/${d.year}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Gorkhapatra'),
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
                    Text('Failed to load posts:\n${snap.error}',
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
          final shown = items.take(_visible).toList();
          return RefreshIndicator(
            onRefresh: () async {
              _visible = _pageSize;
              setState(() => _future = _load());
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  color: AppColors.navy,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('गोरखापत्र लोकसेवा',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('${items.length} posts',
                            style:
                                const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        const Text(
                          'Source: gorkhapatraonline.com/categories/loksewa',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No posts yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ),
                for (final p in shown)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        final slug = _slugOf(p);
                        if (slug.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Could not open this post.')),
                          );
                          return;
                        }
                        context.push('/gorkhapatra/$slug', extra: p);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((p['coverImage'] ?? '').toString().isNotEmpty)
                            Image.network(
                              (p['coverImage'] ?? '').toString(),
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    if (p['isQuestionSet'] == true)
                                      const Chip(
                                        label: Text('Question set',
                                            style:
                                                TextStyle(fontSize: 11)),
                                        visualDensity:
                                            VisualDensity.compact,
                                      )
                                    else if ((p['tag'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Chip(
                                        label: Text(
                                            (p['tag'] ?? '').toString(),
                                            style: const TextStyle(
                                                fontSize: 11)),
                                        visualDensity:
                                            VisualDensity.compact,
                                      ),
                                    if ((p['category'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Chip(
                                        label: Text(
                                            (p['category'] ?? '')
                                                .toString(),
                                            style: const TextStyle(
                                                fontSize: 11)),
                                        visualDensity:
                                            VisualDensity.compact,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text((p['title'] ?? '').toString(),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
                                if ((p['excerpt'] ?? '')
                                    .toString()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text((p['excerpt'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.grey)),
                                ],
                                const SizedBox(height: 6),
                                Text(_dateLabel(p),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_visible < items.length)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: () => setState(
                            () => _visible += _pageSize),
                        child: const Text('Load more'),
                      ),
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
