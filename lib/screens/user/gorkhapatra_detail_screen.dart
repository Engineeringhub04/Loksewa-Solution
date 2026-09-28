import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Gorkhapatra post detail — mirrors app/gorkhapatra/[slug].tsx.
///
/// Hero image, date/question-set pills, title, ordered article blocks
/// (heading/text/image), source attribution and an "open original" action.
/// Without a URL launcher dependency the original URL is shown in a dialog.
class GorkhapatraDetailScreen extends StatefulWidget {
  final String slug;
  const GorkhapatraDetailScreen({super.key, required this.slug});

  @override
  State<GorkhapatraDetailScreen> createState() =>
      _GorkhapatraDetailScreenState();
}

class _GorkhapatraDetailScreenState extends State<GorkhapatraDetailScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    final extra = GoRouterState.of(context).extra;
    if (extra is Map && extra.isNotEmpty) {
      _future = Future.value(Map<String, dynamic>.from(extra));
    } else {
      _future = _load();
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    final idToken = await AuthService.getValidIdToken() ?? '';
    return FirestoreRest.getDocument('gorkhapatra/${widget.slug}',
        idToken: idToken);
  }

  void _showImage(String url, String caption) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Image failed to load.'),
                ),
              ),
            ),
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(caption,
                    style: const TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  void _showOriginal(String url) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Original article'),
        content: SelectableText(url),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Gorkhapatra'),
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
                      ? 'Failed to load post:\n${snap.error}'
                      : 'Post not found.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final p = snap.data!;
          final blocks = p['blocks'];
          final List blockList = blocks is List ? blocks : [];
          final dateLabel = (p['dateLabel'] ?? '').toString();
          final published = p['publishedAt'];
          final date = dateLabel.isNotEmpty
              ? dateLabel
              : (published is DateTime
                  ? '${published.day}/${published.month}/${published.year}'
                  : '');
          final sourceUrl = (p['sourceUrl'] ?? '').toString();
          final source = (p['source'] ?? 'gorkhapatraonline.com').toString();

          return ListView(
            children: [
              if ((p['coverImage'] ?? '').toString().isNotEmpty)
                Image.network(
                  (p['coverImage'] ?? '').toString(),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        if (date.isNotEmpty) Chip(label: Text(date)),
                        if (p['isQuestionSet'] == true)
                          const Chip(
                              label: Text('Question set'),
                              backgroundColor: AppColors.accent,
                              labelStyle:
                                  TextStyle(color: Colors.white)),
                        if ((p['category'] ?? '').toString().isNotEmpty)
                          Chip(
                              label: Text(
                                  (p['category'] ?? '').toString())),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text((p['title'] ?? '').toString(),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    for (final b in blockList)
                      if (b is Map) _block(b),
                    const Divider(height: 32),
                    Text('Source: $source',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                    if (sourceUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showOriginal(sourceUrl),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open original article'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _block(Map b) {
    final type = (b['type'] ?? 'text').toString();
    final text = (b['text'] ?? '').toString();
    switch (type) {
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
        );
      case 'image':
        {
          final url = (b['url'] ?? b['src'] ?? '').toString();
          final caption = (b['caption'] ?? '').toString();
          if (url.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => _showImage(url, caption),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink()),
                  ),
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(caption,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ),
                ],
              ),
            ),
          );
        }
      default:
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text,
              style: const TextStyle(height: 1.6, fontSize: 15)),
        );
    }
  }
}
