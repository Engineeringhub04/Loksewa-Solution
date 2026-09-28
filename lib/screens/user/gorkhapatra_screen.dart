import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Gorkhapatra Loksewa posts — mirrors app/gorkhapatra/index.tsx.
///
/// Reads the `gorkhapatra` collection (document id == slug),
/// orderBy publishedAt desc, 10/page with cursor pagination,
/// `status !== 'hidden'` filtered client-side.
class GorkhapatraScreen extends StatefulWidget {
  const GorkhapatraScreen({super.key});

  @override
  State<GorkhapatraScreen> createState() => _GorkhapatraScreenState();
}

const _sourceUrl = 'https://gorkhapatraonline.com/categories/loksewa';

class _GorkhapatraScreenState extends State<GorkhapatraScreen> {
  final List<GorkhapatraPost> _posts = [];
  DateTime? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(first: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasMore &&
        !_loading &&
        !_loadingMore &&
        _scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _load({bool first = false}) async {
    if (first) {
      setState(() {
        _loading = true;
        _error = null;
        _posts.clear();
        _cursor = null;
        _hasMore = true;
      });
    }
    try {
      final page = await fetchGorkhapatraPosts(before: _cursor);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _posts.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.items.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error =
            first ? 'Failed to load posts. Please try again.' : _error;
      });
      if (!first) {
        showToast(context, 'Failed to load more posts.',
            ToastVariant.error);
      }
    }
  }

  void _loadMore() {
    setState(() => _loadingMore = true);
    _load();
  }

  void _showSourceUrl() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Original source'),
        content: const SelectableText(_sourceUrl),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _sourceUrl));
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
    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _load(first: true),
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
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final border =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE5E7EB);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return RefreshIndicator(
      onRefresh: () async => _load(first: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: _posts.length + 3,
        itemBuilder: (ctx, i) {
          if (i == 0) return _introCard();
          if (i == 1) return _sourceCard(surface, border, secondary);
          if (i == _posts.length + 2) {
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_hasMore && _posts.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: _loadMore,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0xFF2563EB), width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Load more',
                      style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700)),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          if (_posts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'No Gorkhapatra posts yet. Please check back soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: secondary),
                ),
              ),
            );
          }
          final p = _posts[i - 2];
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _postCard(p, surface, border, secondary),
          );
        },
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('गोरखापत्र लोकसेवा',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text(
            'Loksewa-related articles and question sets from the Gorkhapatra national daily.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sourceCard(
      Color surface, Color border, Color secondary) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline,
                size: 20, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Content sourced from the Gorkhapatra online Loksewa section.',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ),
          TextButton(
            onPressed: _showSourceUrl,
            child: const Text('Visit source',
                style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _postCard(GorkhapatraPost p, Color surface, Color border,
      Color secondary) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/gorkhapatra/${p.slug}'),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.coverImage.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14)),
                  child: Image.network(
                    p.coverImage,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (p.isQuestionSet)
                          _pill('Question set',
                              const Color(0xFF7C3AED)),
                        if (p.tag.isNotEmpty && !p.isQuestionSet)
                          _pill(p.tag, const Color(0xFF2563EB)),
                        if (p.category.isNotEmpty)
                          _pill(p.category,
                              const Color(0xFF059669)),
                        if (p.dateLabel.isNotEmpty)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: secondary
                                  .withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 11, color: secondary),
                                const SizedBox(width: 4),
                                Text(p.dateLabel,
                                    style: TextStyle(
                                        color: secondary,
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w600)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(p.title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.4),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    if (p.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(p.excerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: secondary,
                              height: 1.45)),
                    ],
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Text('Read',
                            style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward,
                            size: 15, color: Color(0xFF2563EB)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}
