import 'dart:async';
import 'package:flutter/material.dart';
import '../disk_cached_image.dart';

/// Auto-sliding hero banner carousel (mirrors BannerCarousel.tsx).
/// Autoplay every 3.5s, pauses 3s after a manual touch, then resumes.
/// Slides come from Firestore: image + color, or color + text only.
class BannerCarousel extends StatefulWidget {
  final List<HomeBanner> banners;

  const BannerCarousel({super.key, required this.banners});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class HomeBanner {
  final String id;
  final String? imageLink;
  final String backgroundColor;
  final String? heading;
  final String? subheading;
  final String? linkUrl;

  const HomeBanner({
    required this.id,
    this.imageLink,
    this.backgroundColor = '#1D4ED8',
    this.heading,
    this.subheading,
    this.linkUrl,
  });

  /// Accepts both the Expo field names and the legacy Flutter ones.
  factory HomeBanner.fromMap(Map<String, dynamic> m) => HomeBanner(
        id: '${m['id'] ?? m['heading'] ?? m['title'] ?? ''}',
        imageLink: (m['imageLink'] ?? m['imageUrl'] ?? m['image']) as String?,
        backgroundColor:
            (m['backgroundColor'] ?? m['color'] ?? '#1D4ED8') as String,
        heading: (m['heading'] ?? m['title']) as String?,
        subheading: (m['subheading'] ?? m['subtitle']) as String?,
        linkUrl: (m['linkUrl'] ?? m['url']) as String?,
      );
}

class _BannerCarouselState extends State<BannerCarousel> {
  static const _autoplayMs = 3500;
  static const _resumeAfterTouchMs = 3000;
  static const _hMargin = 16.0;

  late final PageController _controller;
  Timer? _autoplayTimer;
  Timer? _resumeTimer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startAutoplay();
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoplay() {
    _autoplayTimer?.cancel();
    if (widget.banners.length <= 1 || !mounted) return;
    _autoplayTimer = Timer.periodic(
      const Duration(milliseconds: _autoplayMs),
      (_) {
        if (!mounted) return;
        final next = (_index + 1) % widget.banners.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      },
    );
  }

  void _pauseThenResume() {
    _autoplayTimer?.cancel();
    _resumeTimer?.cancel();
    _resumeTimer = Timer(
      const Duration(milliseconds: _resumeAfterTouchMs),
      _startAutoplay,
    );
  }

  Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF1D4ED8);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - _hMargin * 2;
    final cardHeight = cardWidth * 9 / 16; // 16:9

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: cardHeight,
          child: GestureDetector(
            onTapDown: (_) => _pauseThenResume(),
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.banners.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final b = widget.banners[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _hMargin),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      color: _parseColor(b.backgroundColor),
                      child: (b.imageLink != null && b.imageLink!.isNotEmpty)
                          ? DiskCachedImage(
                              url: b.imageLink!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, _, __) =>
                                  _textContent(b),
                            )
                          : _textContent(b),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < widget.banners.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _index ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: const Color(0xFF1D4ED8)
                      .withValues(alpha: i == _index ? 1 : 0.4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _textContent(HomeBanner b) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (b.heading != null && b.heading!.isNotEmpty)
              Text(
                b.heading!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (b.subheading != null && b.subheading!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                b.subheading!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
}
