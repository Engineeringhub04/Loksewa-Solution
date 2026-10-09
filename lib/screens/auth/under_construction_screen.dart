import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Fallback destination for feature buttons that don't have a real page yet —
/// mirrors app/under-construction.tsx. Pass ?page=Feature Name to customize
/// the title. The progress percent is a stable FNV-1a hash of the page name
/// (20–70% in 5-point steps), exactly like the original.
///
/// Premium animated port: breathing halo behind the brand disc, progress bar
/// animating 0→percent with easeOutCubic on mount (replayable via
/// pull-to-refresh), and a FadeInDown entrance for the card — matching React.
class UnderConstructionScreen extends StatefulWidget {
  const UnderConstructionScreen({super.key});

  static int progressForPage(String page) {
    var hash = 0x811c9dc5;
    final key = page.trim().toLowerCase();
    for (var i = 0; i < key.length; i++) {
      hash ^= key.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 20 + (hash % 11) * 5;
  }

  @override
  State<UnderConstructionScreen> createState() =>
      _UnderConstructionScreenState();
}

class _UnderConstructionScreenState extends State<UnderConstructionScreen>
    // Two controllers (_haloController + _progressController), so this must be
    // the multi-ticker mixin — SingleTicker throws on the second createTicker.
    with TickerProviderStateMixin {
  /// Breathing halo behind the disc: 1600ms in-out, repeated forever.
  /// Deliberately a slow pulse, not a spinner (matches React).
  late final AnimationController _haloController;

  /// Progress bar animation: 0→percent over 1200ms easeOutCubic, on mount
  /// and on pull-to-refresh (matches React).
  late final AnimationController _progressController;
  Animation<double>? _progressAnim;

  String _pageName = 'This Feature';
  int _percent = 20;
  bool _progressStarted = false;
  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // GoRouterState is an inherited lookup — read it here, not in initState.
    if (_progressStarted) return;
    _progressStarted = true;
    final params = GoRouterState.of(context).uri.queryParameters;
    _pageName = params['page'] ?? 'This Feature';
    _percent = UnderConstructionScreen.progressForPage(_pageName);
    _progressAnim = _progressController.drive(
      Tween<double>(begin: 0, end: _percent / 100)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    _progressController.forward();
  }

  @override
  void dispose() {
    _haloController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    // Replay the progress animation from 0, like React's refresh behavior.
    _progressController.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  /// 1s preloading shimmer shown on first build before the page content.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeBg = palette.accent.withValues(alpha: isDark ? 0.18 : 0.14);

    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: _pageName),
          Expanded(
            child: _preloading
                ? _preloadingBody()
                : RefreshIndicator.adaptive(
                    color: palette.primary,
                    onRefresh: _onRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: _Entrance(
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Breathing halo stacked behind the brand disc.
                                SizedBox(
                                  width: 112,
                                  height: 112,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      AnimatedBuilder(
                                        animation: _haloController,
                                        builder: (context, _) =>
                                            Transform.scale(
                                          scale:
                                              1 + _haloController.value * 0.16,
                                          child: Opacity(
                                            opacity: 0.3 -
                                                _haloController.value * 0.18,
                                            child: Container(
                                              width: 96,
                                              height: 96,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: palette.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 88,
                                        height: 88,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              AppColors.navy,
                                              Color(0xFF2D5BFF)
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: const Icon(Icons.construction,
                                            size: 40, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 11, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: badgeBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.handyman,
                                          size: 12, color: palette.accent),
                                      const SizedBox(width: 5),
                                      Text(
                                        'IN PROGRESS',
                                        style: TextStyle(
                                          color: palette.accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  _pageName,
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: palette.textPrimary),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Under construction',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: palette.primary),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  "We're building this feature right now. It will be available in an upcoming update.",
                                  style: TextStyle(
                                      color: palette.textSecondary,
                                      height: 1.5),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 15),
                                // Animated progress track: 10px ClipRRect(999),
                                // fill sweeps 0→percent via FractionallySizedBox.
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    height: 10,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.grey.shade200,
                                    child: AnimatedBuilder(
                                      animation: _progressController,
                                      builder: (context, _) =>
                                          FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: _progressAnim?.value ?? 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                palette.primary,
                                                palette.accent,
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '$_percent% complete',
                                    style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 30),
                                Text(
                                  'Thanks for your patience.',
                                  style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 15),
                                ElevatedButton.icon(
                                  onPressed: () => context.pop(),
                                  icon: const Icon(Icons.arrow_back, size: 16),
                                  label: const Text('Go Back'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: palette.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// FadeInDown entrance for the card (React: 420ms easeOut).
class _Entrance extends StatelessWidget {
  final Widget child;
  const _Entrance({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
