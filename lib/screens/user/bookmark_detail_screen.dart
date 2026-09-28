import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Bookmark detail — mirrors app/bookmarks/[id].tsx.
///
/// Renders the saved snapshot payload: title, meta rows, the question with
/// its options (correct option revealed via toggle using payload.answerIndex),
/// explanation, and body text. Remove deletes the bookmark document.
class BookmarkDetailScreen extends StatefulWidget {
  final String id;
  const BookmarkDetailScreen({super.key, required this.id});

  @override
  State<BookmarkDetailScreen> createState() => _BookmarkDetailScreenState();
}

class _BookmarkDetailScreenState extends State<BookmarkDetailScreen> {
  late Future<Map<String, dynamic>?> _future;
  bool _revealAnswer = false;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    final idToken = await AuthService.getValidIdToken() ?? '';
    return FirestoreRest.getDocument('users/$uid/bookmarks/${widget.id}',
        idToken: idToken);
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove bookmark?'),
        content: const Text('This bookmark will be permanently removed.'),
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
    setState(() => _removing = true);
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      await FirestoreRest.deleteDocument(
          'users/$uid/bookmarks/${widget.id}',
          idToken: idToken);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _removing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: 'Bookmark', actions: [
          _removing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                )
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _remove,
                ),
        ]),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.hasError
                      ? 'Failed to load bookmark:\n${snap.error}'
                      : 'Bookmark not found.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final b = snap.data!;
          final payload = b['payload'];
          final Map<String, dynamic> p =
              payload is Map ? Map<String, dynamic>.from(payload) : {};
          final meta = p['meta'];
          final List metaRows = meta is List ? meta : [];
          final options = p['options'];
          final List optionList = options is List ? options : [];
          final answerIndex = p['answerIndex'] is int ? p['answerIndex'] as int : -1;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text((b['title'] ?? '').toString(),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text((b['context'] ?? 'other').toString())),
                  if ((b['sourceLabel'] ?? '').toString().isNotEmpty)
                    Chip(label: Text((b['sourceLabel'] ?? '').toString())),
                ],
              ),
              if (metaRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final m in metaRows)
                          if (m is Map)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                        (m['label'] ?? '').toString(),
                                        style: const TextStyle(
                                            color: Colors.grey)),
                                  ),
                                  Expanded(
                                      child: Text(
                                          (m['value'] ?? '').toString())),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
              if ((p['question'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text((p['question'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (var i = 0; i < optionList.length; i++)
                  _optionTile(i, optionList[i].toString(), answerIndex),
                if (answerIndex >= 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _revealAnswer = !_revealAnswer),
                      icon: Icon(_revealAnswer
                          ? Icons.visibility_off
                          : Icons.visibility),
                      label: Text(_revealAnswer
                          ? 'Hide answer'
                          : 'Reveal answer'),
                    ),
                  ),
                ],
                if ((p['explanation'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text((p['explanation'] ?? '').toString()),
                  ),
                ],
              ],
              if ((p['body'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text((p['body'] ?? '').toString(),
                    style: const TextStyle(height: 1.5)),
              ],
              if ((b['preview'] ?? '').toString().isNotEmpty &&
                  (p['question'] ?? '').toString().isEmpty) ...[
                const SizedBox(height: 16),
                Text((b['preview'] ?? '').toString(),
                    style: const TextStyle(height: 1.5)),
              ],
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _optionTile(int index, String text, int answerIndex) {
    final isCorrect = _revealAnswer && index == answerIndex;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
            color: isCorrect ? Colors.green : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: isCorrect ? Colors.green.withValues(alpha: 0.08) : null,
      ),
      child: Row(
        children: [
          Text('${String.fromCharCode(65 + index)}. ',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
          if (isCorrect)
            const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }
}
