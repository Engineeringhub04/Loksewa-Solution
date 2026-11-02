import 'dart:async';
import 'package:flutter/material.dart';
import 'developer_card.dart';

/// Auto-sliding "About Developer" carousel (NOTE-17) — mirrors the
/// BannerCarousel pattern in banner_carousel.dart: autoplay every 3.5s,
/// pauses 3s after a manual touch, then resumes; dot indicators below.
/// Renders one DeveloperCard per developer row (GET /developers order
/// preserved); a single row renders as a plain card with no dots.
class DeveloperCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> developers;

  const DeveloperCarousel({super.key, required this.developers});

  @override
  State<DeveloperCarousel> createState() => _DeveloperCarouselState();
}

class _DeveloperCarouselState extends State<DeveloperCarousel> {
  static const _autoplayMs = 3500;
  static const _resumeAfterTouchMs = 3000;

  /// Fixed page height: DeveloperCard's tallest shape (name + 3-line
  /// description + portfolio button, plus its 18px vertical padding).
  static const _cardHeight = 164.0;

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
    if (widget.developers.length <= 1 || !mounted) return;
    _autoplayTimer = Timer.periodic(
      const Duration(milliseconds: _autoplayMs),
      (_) {
        if (!mounted) return;
        final next = (_index + 1) % widget.developers.length;
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

  Widget _cardFor(Map<String, dynamic> d) => DeveloperCard(
        name: '${d['name'] ?? 'Developer'}',
        description: d['description'] as String?,
        photoUrl: (d['photoUrl'] ?? d['photo']) as String?,
        viewUrl: d['viewUrl'] as String?,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.developers.isEmpty) return const SizedBox.shrink();
    if (widget.developers.length == 1) {
      return _cardFor(widget.developers.first);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _cardHeight,
          child: GestureDetector(
            onTapDown: (_) => _pauseThenResume(),
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.developers.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _cardFor(widget.developers[i]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < widget.developers.length; i++)
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
      ],
    );
  }
}
