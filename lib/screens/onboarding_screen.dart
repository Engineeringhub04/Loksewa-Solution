import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../services/cf_api.dart';
import '../services/onboarding_cache.dart';
import '../services/prefs_service.dart';

/// Onboarding — iPhone-style modern flow (4 slides, no separate welcome page).
///
/// Cream background, illustration + title + description per slide, small dot
/// indicators, and a circular arrow button that CONTINUOUSLY morphs into a
/// full-width "Sign Up" pill while swiping onto the last slide
/// (finger-driven: the morph follows the PageView scroll position).
/// The 4 hardcoded slides always show first; any slides from the
/// Cloudflare API (GET /onboarding — the copied
/// `app_onboarding-settings` rows, ordered by `order`) append after
/// them (NOTE-19).
class _Slide {
  final String id;
  final String title;
  final String description;
  final String? assetPath;
  final String? imageUrl;

  const _Slide({
    required this.id,
    required this.title,
    required this.description,
    this.assetPath,
    this.imageUrl,
  });
}

const _hardcodedSlides = [
  _Slide(
    id: 'slide-1',
    title: 'Weekly Mock Tests',
    description:
        'Challenge yourself with timed mock tests every week and track your improvement over time.',
    assetPath: 'assets/images/ws-weeklytest.png',
  ),
  _Slide(
    id: 'slide-2',
    title: 'Leaderboard & Analytics',
    description:
        'Track your progress, compete with thousands of students across Nepal, and rise to the top.',
    assetPath: 'assets/images/ws-leaderboard_analytics.png',
  ),
  _Slide(
    id: 'slide-3',
    title: 'Daily Practice',
    description:
        'Strengthen your preparation with fresh daily questions covering all Loksewa subjects.',
    assetPath: 'assets/images/ws-dailytest.png',
  ),
  _Slide(
    id: 'slide-4',
    title: 'Discussion Forum',
    description:
        'Connect with fellow aspirants, discuss tricky questions, and learn together as a community.',
    assetPath: 'assets/images/ws-discussion.png',
  ),
];

const _localImageMap = {
  'assets/images/ws-weeklytest.png': 'assets/images/ws-weeklytest.png',
  'assets/images/ws-leaderboard_analytics.png':
      'assets/images/ws-leaderboard_analytics.png',
  'assets/images/ws-dailytest.png': 'assets/images/ws-dailytest.png',
  'assets/images/ws-discussion.png': 'assets/images/ws-discussion.png',
};

// Video palette.
const _cream = Color(0xFFFDF4EF);
const _navy = Color(0xFF232A3B);
const _ink = Color(0xFF1F2937);
const _grey = Color(0xFF6B7280);
const _dotIdle = Color(0xFFD1D5DB);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  var _slides = _hardcodedSlides;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadRemoteSlides();
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// Rebuilds every frame while scrolling so the morph button, dots and
  /// top-bar fades track the finger continuously.
  void _onScroll() {
    if (mounted) setState(() {});
  }

  /// Fractional page position; falls back to the settled index before the
  /// controller has laid out.
  double get _page => _controller.hasClients && _controller.page != null
      ? _controller.page!
      : _index.toDouble();

  /// 0 until the second-to-last slide, easing to 1 as the user swipes
  /// onto the last slide (index `_slides.length - 1`) — the morph follows
  /// the real slide count, so appended database slides become the last
  /// slide the CTA morphs onto.
  double get _morphT => Curves.easeOutCubic
      .transform((_page - (_slides.length - 2)).clamp(0.0, 1.0));

  Future<void> _loadRemoteSlides() async {
    try {
      // NOTE-19: slides come from the Cloudflare API (GET /onboarding)
      // as plain-JSON rows with the same field names as the Firestore
      // docs (the worker already filters enabled=false rows). The 4
      // hardcoded built-ins ALWAYS stay first (orders 1-4, bundled,
      // fast); database slides (orders 5+) APPEND after them in order —
      // any count, including 0-3 which the old >=4 replace rule hid.
      final docs = await CfApi.getOnboarding();
      if (docs.isEmpty) return;
      docs.sort((a, b) =>
          CfJson.asInt(a['order']).compareTo(CfJson.asInt(b['order'])));
      final remoteSlides = docs.map((d) {
        final imageLink = d['imageLink']?.toString() ?? '';
        final isLocal = CfJson.asBool(d['isLocal']);
        return _Slide(
          id: '${d['id']}',
          title: d['title']?.toString() ?? '',
          description: d['description']?.toString() ?? '',
          assetPath: isLocal ? _localImageMap[imageLink] : null,
          imageUrl: isLocal ? null : (imageLink.isEmpty ? null : imageLink),
        );
      }).toList();
      if (remoteSlides.isEmpty || !mounted) return;
      setState(() => _slides = [..._hardcodedSlides, ...remoteSlides]);
      // Background-prefetch + disk-cache the appended slides' images
      // while the built-ins are on screen — fire-and-forget, deadline-
      // guarded inside OnboardingCache, never blocks the built-ins.
      // The trailing rebuild lets already-built appended slides swap
      // from NetworkImage to the cached FileImage once downloads land.
      unawaited(OnboardingCache.prefetchRemote(
        remoteSlides.map((s) => s.imageUrl).whereType<String>(),
      ).then((_) {
        if (mounted) setState(() {});
      }));
    } catch (_) {
      // hardcoded fallback stays
    }
  }

  Future<void> _finishSignup() async {
    await PrefsService.setBool(PrefsService.onboardingSeen, true);
    if (mounted) context.go('/signup');
  }

  Future<void> _finishLogin() async {
    await PrefsService.setBool(PrefsService.onboardingSeen, true);
    if (mounted) context.go('/login');
  }

  void _goTo(int i) {
    _controller.animateToPage(
      i.clamp(0, _slides.length - 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onMorphTap() {
    if (_morphT < 0.5) {
      _goTo(_index + 1);
    } else {
      _finishSignup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final morphT = _morphT;
    final screenW = MediaQuery.of(context).size.width;
    final fullW = screenW - 48; // 24px margins, like the video's pill

    // Button geometry, driven by the swipe.
    final btnW = 56 + (fullW - 56) * morphT;
    final btnR = 28 + (16 - 28) * morphT;
    final showText = morphT > 0.4;

    // Transparent status bar with dark icons so the cream background flows
    // under the clock — same edge-to-edge treatment as home pages; kills
    // the dark band that used to sit above onboarding.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _cream,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar: back chevron (from slide 2) + Skip (all but the
              // last slide).
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    Opacity(
                      opacity: _page.clamp(0.0, 1.0),
                      child: IconButton(
                        onPressed: _page > 0.5 ? () => _goTo(_index - 1) : null,
                        icon: const Icon(Icons.chevron_left,
                            size: 28, color: _ink),
                      ),
                    ),
                    const Spacer(),
                    Opacity(
                      opacity: 1 - morphT,
                      child: TextButton(
                        onPressed: morphT < 0.5
                            ? () => _goTo(_slides.length - 1)
                            : null,
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Slides.
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _SlideView(
                    slide: _slides[i],
                    controller: _controller,
                    index: i,
                  ),
                ),
              ),
              // Dots (fade out while morphing into the CTA).
              Opacity(
                opacity: 1 - morphT,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _index ? _ink : _dotIdle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // Morphing CTA: circle arrow -> full-width "Sign Up" pill.
              Center(
                child: GestureDetector(
                  onTap: _onMorphTap,
                  child: Container(
                    width: btnW,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(btnR),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showText) ...[
                          const SizedBox(width: 24),
                          Opacity(
                            opacity: morphT,
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_forward,
                              size: 20, color: Colors.white),
                          const SizedBox(width: 24),
                        ] else
                          const Icon(Icons.arrow_forward,
                              size: 20, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              // Login row (reserved space so the button never jumps).
              SizedBox(
                height: 40,
                child: Opacity(
                  opacity: morphT,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Already have an account? ',
                          style: TextStyle(color: _grey, fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: morphT > 0.5 ? _finishLogin : null,
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// One onboarding page. Drag-driven staggered parallax: the illustration
/// moves MORE with the swipe (t * 110) so it visually lags behind the
/// text block (t * 36), which appears first and sharp — like the reference
/// video. Both fade gently while off-centre.
class _SlideView extends StatelessWidget {
  final _Slide slide;
  final PageController controller;
  final int index;

  const _SlideView({
    required this.slide,
    required this.controller,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // 0 when centred, +/-1 when fully adjacent.
        final page = controller.hasClients && controller.page != null
            ? controller.page!
            : index.toDouble();
        final t = page - index;
        final fade = (0.35 + 0.65 * (1 - t.abs())).clamp(0.0, 1.0);

        final provider =
            OnboardingCache.resolve(slide.assetPath, slide.imageUrl);
        final illustration = SizedBox(
          height: 260,
          child: provider != null
              ? Image(
                  image: provider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_outlined,
                    size: 120,
                    color: _dotIdle,
                  ),
                )
              : const Icon(
                  Icons.image_outlined,
                  size: 120,
                  color: _dotIdle,
                ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(t * 110, 0),
                  child: illustration,
                ),
              ),
              const SizedBox(height: 36),
              Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(t * 36, 0),
                  child: Column(
                    children: [
                      Text(
                        slide.title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        slide.description,
                        style: const TextStyle(
                          color: _grey,
                          fontSize: 15,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
