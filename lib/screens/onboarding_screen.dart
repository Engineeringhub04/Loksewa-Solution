import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/firestore_rest.dart';
import '../services/onboarding_cache.dart';
import '../services/prefs_service.dart';

/// Onboarding — iPhone-style modern flow (4 slides, no separate welcome page).
///
/// Cream background, illustration + title + description per slide, small dot
/// indicators, and a circular arrow button that CONTINUOUSLY morphs into a
/// full-width "Sign Up" pill while swiping from slide 3 to slide 4
/// (finger-driven: the morph follows the PageView scroll position).
/// Slides come from Firestore `app_onboarding-settings` (ordered by `order`);
/// the 4 hardcoded slides are the fallback.
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

  /// 0 on slides 1-3, easing to 1 as the user swipes onto slide 4.
  double get _morphT =>
      Curves.easeOutCubic.transform((_page - 2).clamp(0.0, 1.0));

  Future<void> _loadRemoteSlides() async {
    try {
      final idToken = await AuthService.getValidIdToken();
      final docs = await FirestoreRest.listDocuments(
        'app_onboarding-settings',
        idToken: idToken,
        pageSize: 20,
      );
      if (docs.length >= 4) {
        docs.sort((a, b) =>
            ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
        final slides = docs.map((d) {
          final imageLink = d['imageLink'] as String? ?? '';
          final isLocal = d['isLocal'] as bool? ?? false;
          return _Slide(
            id: '${d['id']}',
            title: d['title'] as String? ?? '',
            description: d['description'] as String? ?? '',
            assetPath: isLocal ? _localImageMap[imageLink] : null,
            imageUrl:
                isLocal ? null : (imageLink.isEmpty ? null : imageLink),
          );
        }).toList();
        if (mounted) setState(() => _slides = slides);
      }
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

    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: back chevron (from slide 2) + Skip (slides 1-3).
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
                      onPressed: morphT < 0.5 ? () => _goTo(3) : null,
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
