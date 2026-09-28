import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Gorkhapatra Loksewa posts — mirrors app/gorkhapatra/index.tsx.
///
/// Brand colour is the purple accent (#7C3AED / dark #A78BFA): intro card,
/// icon tiles, load-more and press states all key off it. The date chip is
/// intentionally dark-orange (#C2410C light / #FDBA74 dark). Cards carry the
/// signature left accent spine — a 26px nub at rest that grows on press.
class GorkhapatraScreen extends StatefulWidget {
  const GorkhapatraScreen({super.key});

  @override
  State<GorkhapatraScreen> createState() => _GorkhapatraScreenState();
}

class _GorkhapatraScreenState extends State<GorkhapatraScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<GorkhapatraPost> _items = const [];
  DateTime? _nextCursor;

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
      final page = await fetchGorkhapatraPosts();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = page.items;
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'error';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await fetchGorkhapatraPosts(before: cursor);
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _items = [..._items, ...page.items];
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showToast(context, 'Could not load more posts. Please try again.',
          ToastVariant.error);
    }
  }

  void _copyLink(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, 'Link copied to clipboard', ToastVariant.success);
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
    final hairline =
        isDark ? const Color(0xFF223052) : const Color(0xFFE5EAF4);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF141B2D);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const SubpageHeader(title: 'Gorkhapatra Loksewa'),
            Expanded(child: _body(accent, surface, surfaceAlt, hairline,
                textPrimary, secondary, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _body(
      Color accent,
      Color surface,
      Color surfaceAlt,
      Color hairline,
      Color textPrimary,
      Color secondary,
      bool isDark) {
    if (_loading) {
      return const PreloadingWidget(
        tinted: false,
        label: 'Loading Gorkhapatra...',
        hint: "Fetching today's edition",
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.newspaper_outlined, size: 46, color: secondary),
              const SizedBox(height: 14),
              Text('No posts available yet',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textPrimary)),
              const SizedBox(height: 16),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _introCard(accent, textPrimary, secondary, isDark),
        const SizedBox(height: 12),
        _sourceNotice(accent, surfaceAlt, hairline, secondary),
        const SizedBox(height: 14),
        if (_items.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text('No posts available yet',
                  style: TextStyle(fontSize: 13, color: secondary)),
            ),
          )
        else
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: EdgeInsets.only(
                  bottom: i == _items.length - 1 ? 0 : 12),
              child: _card(_items[i], accent, surface, surfaceAlt,
                  hairline, textPrimary, secondary, isDark),
            ),
        _footer(accent, surfaceAlt, secondary),
      ],
    );
  }

  /// Intro card — mirrors React introCard / introIcon.
  Widget _introCard(
      Color accent, Color textPrimary, Color secondary, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? accent.withValues(alpha: 0.16)
            : const Color(0xFFF3EEFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.menu_book_outlined,
                size: 22, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gorkhapatra Loksewa',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textPrimary)),
                const SizedBox(height: 2),
                Text("Gorkhapatra's Loksewa material, in the app",
                    style: TextStyle(
                        fontSize: 13, color: secondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Source notice — surface-alt banner with an inline tappable link.
  Widget _sourceNotice(
      Color accent, Color surfaceAlt, Color hairline, Color secondary) {
    const linkLabel = 'Gorkhapatra Loksewa';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceAlt,
        border: Border.all(color: hairline, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: secondary),
                children: [
                  const TextSpan(
                      text:
                          'All the content shown here is collected from the official '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () => _copyLink(
                          'https://lokeswa.gorkhapatraonline.com'),
                      child: Text(linkLabel,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: accent)),
                    ),
                  ),
                  const TextSpan(text: ' website.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// GorkhapatraCard — rounded surface tile, hairline border, accent spine.
  Widget _card(
      GorkhapatraPost item,
      Color accent,
      Color surface,
      Color surfaceAlt,
      Color hairline,
      Color textPrimary,
      Color secondary,
      bool isDark) {
    final iconBg =
        accent.withValues(alpha: isDark ? 0.18 : 0.12);
    final dateBg = isDark
        ? const Color(0x29FB923C)
        : const Color(0x1FEA580C);
    final dateFg =
        isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C);
    final badge = item.tag.isNotEmpty
        ? item.tag
        : (item.isQuestionSet ? 'Question Set' : '');
    return _SpineCard(
      accent: accent,
      surface: surface,
      surfaceAlt: surfaceAlt,
      hairline: hairline,
      onTap: () => context.push(
          '/gorkhapatra/${Uri.encodeComponent(item.slug)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    item.isQuestionSet
                        ? Icons.help_outline
                        : Icons.description_outlined,
                    size: 20,
                    color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textPrimary)),
                    if (item.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(item.excerpt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.38,
                              color: secondary)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (item.dateLabel.isNotEmpty)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4),
                            decoration: BoxDecoration(
                              color: dateBg,
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today_outlined,
                                    size: 12, color: dateFg),
                                const SizedBox(width: 4),
                                Text(item.dateLabel,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            FontWeight.w600,
                                        color: dateFg)),
                              ],
                            ),
                          ),
                        if (badge.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: accent)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.coverImage.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(item.coverImage,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox.shrink()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(Color accent, Color surfaceAlt, Color secondary) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Color(0xFF2563EB)),
          ),
        ),
      );
    }
    if (_nextCursor != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: surfaceAlt,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _loadMore,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Load more',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accent)),
                    const SizedBox(width: 6),
                    Icon(Icons.keyboard_arrow_down,
                        size: 16, color: accent),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Text("You're all caught up",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: secondary)),
    );
  }
}

/// Card with the signature left accent spine: a 26px nub at rest that fills
/// the full height (scaleY from centre) while pressed.
class _SpineCard extends StatefulWidget {
  final Color accent;
  final Color surface;
  final Color surfaceAlt;
  final Color hairline;
  final VoidCallback onTap;
  final Widget child;

  const _SpineCard({
    required this.accent,
    required this.surface,
    required this.surfaceAlt,
    required this.hairline,
    required this.onTap,
    required this.child,
  });

  @override
  State<_SpineCard> createState() => _SpineCardState();
}

class _SpineCardState extends State<_SpineCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
            decoration: BoxDecoration(
              color: _pressed ? widget.surfaceAlt : widget.surface,
              border: Border.all(
                  color: _pressed
                      ? widget.accent.withValues(alpha: 0.33)
                      : widget.hairline,
                  width: 0.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: widget.child,
          ),
          // Accent spine: 26px nub at rest, fills on press (scaleY from centre).
          Positioned(
            left: 6,
            top: 12,
            bottom: 12,
            width: 4,
            child: LayoutBuilder(
              builder: (context, c) {
                final trackH = c.maxHeight;
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                      begin: 0, end: _pressed ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  builder: (context, t, _) => Center(
                    child: Container(
                      width: 4,
                      height: math.max(26, trackH * t),
                      decoration: BoxDecoration(
                        color: widget.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
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
