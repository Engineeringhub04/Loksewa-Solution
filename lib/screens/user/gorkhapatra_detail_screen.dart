import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Gorkhapatra post detail — mirrors app/gorkhapatra/[slug].tsx.
///
/// 200px hero (tap → fullscreen viewer), date + question-set pills (date
/// chip is the signature dark-orange, question-set is the purple accent),
/// bold h2 title, native blocks, source row. The "open original" action
/// shows a copyable URL dialog (no URL launcher dependency).
class GorkhapatraDetailScreen extends StatefulWidget {
  final String slug;

  const GorkhapatraDetailScreen({super.key, required this.slug});

  @override
  State<GorkhapatraDetailScreen> createState() =>
      _GorkhapatraDetailScreenState();
}

class _GorkhapatraDetailScreenState extends State<GorkhapatraDetailScreen> {
  bool _loading = true;
  GorkhapatraPost? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final post = await fetchGorkhapatraPost(widget.slug);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _post = post;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openFullscreen(String url, {String? caption}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      builder: (_) => _FullscreenImage(url: url, caption: caption),
    );
  }

  void _showSourceDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('View on Gorkhapatra'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(ctx).pop();
              showToast(context, 'Link copied to clipboard',
                  ToastVariant.success);
            },
            child: const Text('Copy link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA);
    final accent =
        isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final surfaceAlt =
        isDark ? const Color(0xFF1A2338) : const Color(0xFFF8FAFC);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF141B2D);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final post = _post;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
        child: Column(
          children: [
            SubpageHeader(
                title: post?.title.isNotEmpty == true
                    ? post!.title
                    : 'Gorkhapatra Loksewa'),
            Expanded(
              child: _loading
                  ? const PreloadingWidget(
                      tinted: false,
                      label: 'Loading Gorkhapatra...',
                      hint: "Fetching today's edition",
                    )
                  : post == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.newspaper_outlined,
                                    size: 46,
                                    color: secondary),
                                const SizedBox(height: 14),
                                Text('Post not found',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight:
                                            FontWeight.bold,
                                        color: textPrimary)),
                              ],
                            ),
                          ),
                        )
                      : _article(post, accent, surface, surfaceAlt,
                          textPrimary, secondary, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _article(
      GorkhapatraPost post,
      Color accent,
      Color surface,
      Color surfaceAlt,
      Color textPrimary,
      Color secondary,
      bool isDark) {
    final dateLabel = post.dateLabel.isNotEmpty
        ? post.dateLabel
        : (post.publishedAt != null
            ? '${post.publishedAt!.day}/${post.publishedAt!.month}/${post.publishedAt!.year}'
            : '');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // Hero — 200px, tap → fullscreen viewer.
        if (post.coverImage.isNotEmpty)
          GestureDetector(
            onTap: () => _openFullscreen(post.coverImage),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(post.coverImage,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox.shrink()),
            ),
          ),
        if (post.coverImage.isNotEmpty) const SizedBox(height: 16),
        // Meta row: date pill + question-set pill.
        Row(
          children: [
            if (dateLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: secondary),
                    const SizedBox(width: 6),
                    Text(dateLabel,
                        style: TextStyle(
                            fontSize: 12, color: secondary)),
                  ],
                ),
              ),
            if (post.isQuestionSet) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.help_outline,
                        size: 13, color: accent),
                    const SizedBox(width: 6),
                    Text('Question Set',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accent)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // Title — h2 bold, generous line height.
        Text(post.title,
            style: TextStyle(
                fontSize: 20,
                height: 32 / 20,
                fontWeight: FontWeight.bold,
                color: textPrimary)),
        const SizedBox(height: 12),
        // Native blocks.
        for (final b in post.blocks) _block(b, textPrimary, secondary),
        // Source row — only when a source URL exists.
        if (post.sourceUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: GestureDetector(
              onTap: () => _showSourceDialog(post.sourceUrl),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new,
                        size: 17,
                        color: isDark
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF1D4ED8)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Source: Gorkhapatra Online',
                          style: TextStyle(
                              fontSize: 12,
                              color: secondary)),
                    ),
                    const SizedBox(width: 8),
                    Text('View on Gorkhapatra',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF1D4ED8))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _block(
      GorkhapatraBlock b, Color textPrimary, Color secondary) {
    if (b.type == 'heading') {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(b.text,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary)),
      );
    }
    if (b.type == 'image' && b.url.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: GestureDetector(
          onTap: () => _openFullscreen(b.url, caption: b.caption),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(b.url,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink()),
              ),
              if (b.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(b.caption,
                      style: TextStyle(
                          fontSize: 12, color: secondary)),
                ),
            ],
          ),
        ),
      );
    }
    // Paragraph.
    if (b.text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(b.text,
          style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: textPrimary)),
    );
  }
}

class _FullscreenImage extends StatelessWidget {
  final String url;
  final String? caption;

  const _FullscreenImage({required this.url, this.caption});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.white54)),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xD9000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    size: 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
