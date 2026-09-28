import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Notice detail — mirrors app/notice/[id].tsx.
///
/// Renders the document's `blocks` (heading/text/image), honours `[img:KEY]`
/// inline tokens via the `images` map, parses `**bold**` spans and tappable
/// URLs in paragraphs, and shows the optional download CTA. Without a URL
/// launcher dependency, links are shown in a dialog with the full URL.
class NoticeDetailScreen extends StatefulWidget {
  final String id;
  const NoticeDetailScreen({super.key, required this.id});

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
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
    return FirestoreRest.getDocument('app_notices/${widget.id}',
        idToken: idToken);
  }

  void _showLinkDialog(String url) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Link'),
        content: SelectableText(url),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
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

  /// Builds a paragraph with `**bold**` spans, `[img:KEY]` inline tokens and
  /// tappable URLs — mirrors the Expo renderer.
  List<InlineSpan> _richSpans(
      String text, Map<String, dynamic> images, TextStyle base) {
    final spans = <InlineSpan>[];
    final tokenRe = RegExp(r'\[img:([^\]]+)\]');
    int i = 0;
    // First split out [img:KEY] tokens; images render as widgets below.
    final parts = <Object>[];
    for (final m in tokenRe.allMatches(text)) {
      if (m.start > i) parts.add(text.substring(i, m.start));
      parts.add(_InlineImage(key: m.group(1)!));
      i = m.end;
    }
    if (i < text.length) parts.add(text.substring(i));

    for (final part in parts) {
      if (part is _InlineImage) {
        spans.add(WidgetSpan(
          child: _inlineImageWidget(part.key, images),
          alignment: PlaceholderAlignment.middle,
        ));
        continue;
      }
      final seg = part as String;
      int j = 0;
      final combined = RegExp(r'(\*\*.+?\*\*|https?://[^\s\)\]]+)');
      for (final m in combined.allMatches(seg)) {
        if (m.start > j) {
          spans.add(TextSpan(text: seg.substring(j, m.start), style: base));
        }
        final tok = m.group(0)!;
        if (tok.startsWith('**')) {
          spans.add(TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: base.copyWith(fontWeight: FontWeight.bold),
          ));
        } else {
          spans.add(WidgetSpan(
            child: GestureDetector(
              onTap: () => _showLinkDialog(tok),
              child: Text(tok,
                  style: base.copyWith(
                      color: AppColors.accent,
                      decoration: TextDecoration.underline)),
            ),
          ));
        }
        j = m.end;
      }
      if (j < seg.length) {
        spans.add(TextSpan(text: seg.substring(j), style: base));
      }
    }
    return spans;
  }

  Widget _inlineImageWidget(String key, Map<String, dynamic> images) {
    final entry = images[key];
    final url = entry is Map ? (entry['url'] ?? '').toString() : '';
    if (url.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _showImage(
          url, entry is Map ? (entry['caption'] ?? '').toString() : ''),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notice'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
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
                      ? 'Failed to load notice:\n${snap.error}'
                      : 'Notice not found.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final n = snap.data!;
          final blocks = n['blocks'];
          final List blockList = blocks is List ? blocks : [];
          final images = n['images'];
          final Map<String, dynamic> imageMap =
              images is Map ? Map<String, dynamic>.from(images) : {};
          final base = const TextStyle(height: 1.6, fontSize: 15);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text((n['title'] ?? '').toString(),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final label = (n['dateLabel'] ?? '').toString();
                final p = n['publishedAt'];
                final date = label.isNotEmpty
                    ? label
                    : (p is DateTime
                        ? '${p.day}/${p.month}/${p.year}'
                        : '');
                return Wrap(
                  spacing: 8,
                  children: [
                    if ((n['kind'] ?? '').toString().isNotEmpty)
                      Chip(label: Text((n['kind'] ?? '').toString())),
                    if (date.isNotEmpty) Chip(label: Text(date)),
                  ],
                );
              }),
              const SizedBox(height: 12),
              for (final b in blockList)
                if (b is Map) _block(b, imageMap, base),
              if (n['downloadEnabled'] == true &&
                  (n['downloadUrl'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showLinkDialog(
                        (n['downloadUrl'] ?? '').toString()),
                    icon: const Icon(Icons.download),
                    label: Text((n['downloadLabel'] ?? 'Download')
                        .toString()
                        .isEmpty
                        ? 'Download'
                        : (n['downloadLabel'] ?? 'Download').toString()),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _block(
      Map b, Map<String, dynamic> images, TextStyle base) {
    final type = (b['type'] ?? 'text').toString();
    switch (type) {
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text((b['text'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
        );
      case 'image':
        {
          final url = (b['url'] ?? '').toString();
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RichText(
            text: TextSpan(
              style: base.copyWith(color: Colors.black87),
              children:
                  _richSpans((b['text'] ?? '').toString(), images, base),
            ),
          ),
        );
    }
  }
}

class _InlineImage {
  final String key;
  _InlineImage({required this.key});
}
