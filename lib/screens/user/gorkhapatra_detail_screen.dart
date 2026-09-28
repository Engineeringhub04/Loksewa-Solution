import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Gorkhapatra post detail — mirrors app/gorkhapatra/[slug].tsx.
///
/// 200px hero (tap → fullscreen viewer), date + question-set pills, title,
/// native blocks, source row. The "open original" action shows a copyable
/// URL dialog (no URL launcher dependency).
class GorkhapatraDetailScreen extends StatefulWidget {
  final String slug;

  const GorkhapatraDetailScreen({super.key, required this.slug});

  @override
  State<GorkhapatraDetailScreen> createState() =>
      _GorkhapatraDetailScreenState();
}

class _GorkhapatraDetailScreenState
    extends State<GorkhapatraDetailScreen> {
  GorkhapatraPost? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await fetchGorkhapatraPost(widget.slug);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _post = post;
        _error = post == null ? 'Post not found.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load this post. Please try again.';
      });
    }
  }

  void _showFullscreenImage(String url) {
    showDialog(
      context: context,
      builder: (c) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Image failed to load.',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(c).padding.top + 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor:
                      Colors.white.withValues(alpha: 0.15),
                ),
              ),
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
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c);
              showToast(context, 'Link copied.', ToastVariant.success);
            },
            child: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            const SubpageHeader(title: 'Gorkhapatra'),
            Expanded(child: _body(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _post == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Post not found.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    final p = _post!;
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return ListView(
      children: [
        // 200px hero — tap opens the fullscreen viewer.
        if (p.coverImage.isNotEmpty)
          GestureDetector(
            onTap: () => _showFullscreenImage(p.coverImage),
            child: Image.network(
              p.coverImage,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (p.dateLabel.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 12,
                              color: Color(0xFF2563EB)),
                          const SizedBox(width: 5),
                          Text(p.dateLabel,
                              style: const TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  if (p.isQuestionSet)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Question set',
                          style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  if (p.tag.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(p.tag,
                          style: const TextStyle(
                              color: Color(0xFF059669),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  if (p.category.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: secondary
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(p.category,
                          style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(p.title,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.35)),
              const SizedBox(height: 12),
              for (final b in p.blocks)
                _block(b, secondary),
              const SizedBox(height: 8),
              const Divider(height: 32),
              // Source row.
              Row(
                children: [
                  Icon(Icons.link, size: 16, color: secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Source: ${p.source.isNotEmpty ? p.source : 'gorkhapatraonline.com'}',
                      style: TextStyle(
                          color: secondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (p.sourceUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showOriginal(p.sourceUrl),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open original article'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(
                          color: Color(0xFF2563EB), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _block(GorkhapatraBlock b, Color secondary) {
    switch (b.type) {
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(b.text,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
        );
      case 'image':
        if (b.url.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _showFullscreenImage(b.url),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(b.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox.shrink()),
                ),
                if (b.caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(b.caption,
                        style: TextStyle(
                            color: secondary, fontSize: 12)),
                  ),
              ],
            ),
          ),
        );
      default:
        if (b.text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(b.text,
              style: const TextStyle(height: 1.6, fontSize: 15)),
        );
    }
  }
}
