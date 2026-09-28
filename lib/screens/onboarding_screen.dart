import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/firestore_rest.dart';
import '../services/prefs_service.dart';

/// Onboarding — mirrors app/onboarding.tsx.
/// Slides come from Firestore `app_onboarding-settings` (ordered by `order`);
/// the 4 hardcoded slides are the fallback.
class _Slide {
  final String id;
  final String title;
  final String description;
  final String? assetPath;
  final String? imageUrl;
  final Color backgroundColor;
  final Color accentColor;
  final String? tag;

  const _Slide({
    required this.id,
    required this.title,
    required this.description,
    this.assetPath,
    this.imageUrl,
    required this.backgroundColor,
    required this.accentColor,
    this.tag,
  });
}

Color _hex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

const _hardcodedSlides = [
  _Slide(
    id: 'slide-1',
    title: 'Weekly Mock Tests',
    description:
        'Challenge yourself with timed mock tests every week and track your improvement over time.',
    assetPath: 'assets/images/ws-weeklytest.png',
    backgroundColor: Color(0xFF0F172A),
    accentColor: Color(0xFF3B82F6),
    tag: 'Practice',
  ),
  _Slide(
    id: 'slide-2',
    title: 'Leaderboard & Analytics',
    description:
        'Track your progress, compete with thousands of students across Nepal, and rise to the top.',
    assetPath: 'assets/images/ws-leaderboard_analytics.png',
    backgroundColor: Color(0xFF0B1F28),
    accentColor: Color(0xFF10B981),
    tag: 'Compete',
  ),
  _Slide(
    id: 'slide-3',
    title: 'Daily Practice',
    description:
        'Strengthen your preparation with fresh daily questions covering all Loksewa subjects.',
    imageUrl: 'https://i.ibb.co/hN8gtSc/dailytest-wlc.png',
    backgroundColor: Color(0xFF1E1510),
    accentColor: Color(0xFFF97316),
    tag: 'Daily',
  ),
  _Slide(
    id: 'slide-4',
    title: 'Discussion Forum',
    description:
        'Connect with fellow aspirants, discuss tricky questions, and learn together as a community.',
    imageUrl: 'https://i.ibb.co/9HYXh3nr/discussion-wlc.png',
    backgroundColor: Color(0xFF1B1B3D),
    accentColor: Color(0xFF8B5CF6),
    tag: 'Community',
  ),
];

const _localImageMap = {
  'assets/images/ws-weeklytest.png': 'assets/images/ws-weeklytest.png',
  'assets/images/ws-leaderboard_analytics.png':
      'assets/images/ws-leaderboard_analytics.png',
};

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
    _loadRemoteSlides();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
            imageUrl: isLocal ? null : imageLink,
            backgroundColor: _hex(d['backgroundColor'] as String? ?? '#0B1330'),
            accentColor: const Color(0xFF3B82F6),
          );
        }).toList();
        if (mounted) setState(() => _slides = slides);
      }
    } catch (_) {
      // hardcoded fallback stays
    }
  }

  Future<void> _finish() async {
    await PrefsService.setBool(PrefsService.onboardingSeen, true);
    if (mounted) context.go('/login');
  }

  void _goTo(int i) {
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    final isFirst = _index == 0;
    final slide = _slides[_index];

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: slide.backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: Skip
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 80),
                    const Spacer(),
                    if (!isLast)
                      TextButton(
                        onPressed: () => _goTo(_slides.length - 1),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Skip',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right,
                                size: 14, color: Colors.white70),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Slides
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
                ),
              ),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _index
                          ? slide.accentColor
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Bottom nav
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: isLast
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _finish,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Get Started',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          if (!isFirst)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _goTo(_index - 1),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white30),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.arrow_back, size: 18),
                                    SizedBox(width: 6),
                                    Text('Back'),
                                  ],
                                ),
                              ),
                            ),
                          if (!isFirst) const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _goTo(_index + 1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: slide.accentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text('Next',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                            ),
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
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (slide.assetPath != null) {
      image = Image.asset(slide.assetPath!, fit: BoxFit.contain);
    } else if (slide.imageUrl != null) {
      image = Image.network(
        slide.imageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.image, size: 120, color: Colors.white24),
      );
    } else {
      image = const Icon(Icons.image, size: 120, color: Colors.white24);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (slide.tag != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: slide.accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: slide.accentColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                slide.tag!,
                style: TextStyle(
                  color: slide.accentColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(height: 220, child: image),
          const SizedBox(height: 32),
          Text(
            slide.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            slide.description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 15,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
