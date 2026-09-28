import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Bookmarks list — mirrors app/bookmarks/index.tsx.
///
/// Bookmarks live at `users/{uid}/bookmarks` with a deterministic document id
/// `{context}__{safeSegment(refId)}` (see bookmarks.ts), so the list can
/// recompute each id from the stored `context` + `refId` fields even though
/// the list API does not return document ids.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

/// Mirrors `safeSegment` in src/core/firebase/services/bookmarks.ts.
String _safeSegment(String value) {
  var s = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 90) s = s.substring(0, 90);
  return s.isEmpty ? 'item' : s;
}

String _bookmarkDocId(Map<String, dynamic> b) =>
    '${b['context'] ?? 'other'}__${_safeSegment((b['refId'] ?? '').toString())}';

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  String _context = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    final idToken = await AuthService.getValidIdToken() ?? '';
    final rows =
        await FirestoreRest.listDocuments('users/$uid/bookmarks', idToken: idToken);
    rows.sort((a, b) {
      final da = a['createdAt'];
      final db = b['createdAt'];
      final ta = da is DateTime ? da.millisecondsSinceEpoch : 0;
      final tb = db is DateTime ? db.millisecondsSinceEpoch : 0;
      return tb.compareTo(ta);
    });
    return rows;
  }

  Future<void> _remove(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove bookmark?'),
        content: Text('Remove "${(b['title'] ?? '').toString()}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      await FirestoreRest.deleteDocument(
          'users/$uid/bookmarks/${_bookmarkDocId(b)}',
          idToken: idToken);
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
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
                    Text('Failed to load bookmarks:\n${snap.error}',
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
          final all = snap.data ?? [];
          final contexts = <String>{
            for (final b in all) (b['context'] ?? 'other').toString()
          }.toList()
            ..sort();
          final q = _query.trim().toLowerCase();
          final items = all.where((b) {
            if (_context != 'all' &&
                (b['context'] ?? 'other').toString() != _context) {
              return false;
            }
            if (q.isEmpty) return true;
            final title = (b['title'] ?? '').toString().toLowerCase();
            final preview = (b['preview'] ?? '').toString().toLowerCase();
            return title.contains(q) || preview.contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search bookmarks…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (contexts.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _chip('all', 'All'),
                      for (final c in contexts) _chip(c, c),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            all.isEmpty
                                ? 'No bookmarks yet.\nBookmark questions, notes and articles to find them here.'
                                : 'No bookmarks match your search.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            setState(() => _future = _load()),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final b = items[i];
                            final created = b['createdAt'];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.bookmark,
                                    color: AppColors.accent),
                                title: Text(
                                    (b['title'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if ((b['preview'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(
                                          (b['preview'] ?? '').toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        Chip(
                                          label: Text(
                                              (b['context'] ?? 'other')
                                                  .toString(),
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                        if ((b['sourceLabel'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Chip(
                                            label: Text(
                                                (b['sourceLabel'] ?? '')
                                                    .toString(),
                                                style: const TextStyle(
                                                    fontSize: 11)),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        if (created is DateTime)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                              '${created.day}/${created.month}/${created.year}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _remove(b),
                                ),
                                onTap: () => context.push(
                                    '/bookmarks/${_bookmarkDocId(b)}'),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _context == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _context = value),
      ),
    );
  }
}
