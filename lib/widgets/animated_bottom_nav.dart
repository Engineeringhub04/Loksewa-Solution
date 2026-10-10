import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Bottom navigation: the user's 4 animated Lordicon icons (bundled Lottie
/// JSON assets, `assets/icons/nav_*.json`) on the proven
/// `curved_navigation_bar` package.
///
/// Matches the user's spec:
/// - bar background follows the app theme (very light in light mode,
///   dark in dark mode) — NOT fixed blue,
/// - a SOFT UPWARD SHADOW (Tarika 2) separates the bar from the page
///   above — subtle floating feel like the reference app; isolated in one
///   Container so it is trivial to remove if the user dislikes it,
/// - the bar is slightly shorter than the package default (65 vs 75),
/// - the concave notch is TRANSPARENT — the page behind shows through
///   (the Scaffold uses `extendBody: true`),
/// - selected tab: a THEME-AWARE circle popping UP ABOVE the bar — dark
///   navy in light mode, white in dark mode — with the BLUE animated
///   Lordicon icon inside it, BOLD label below the circle in app blue,
/// - unselected tabs: BOLD fully-visible Lordicon icons (dark in light
///   mode, white in dark mode — never dim gray), static fully-revealed
///   frame, BOLD label under each icon in a theme-aware color,
/// - labels (Home/Exam/Discussion/Profile) are always visible on all tabs,
/// - tap: the tapped icon's animation plays from the beginning; the white
///   circle + notch slide together (~350ms, easeInOut).
///
/// Label note: the package fades the selected item in the bar row to
/// opacity 0 (it lives in the floating circle instead), so labels cannot be
/// part of the items — they are overlaid in a Stack, pointer-transparent so
/// taps still reach the bar.
///
/// Implementation note: the official `lordicon` package was tried first, but
/// its `IconViewer` caches `colorize` in `initState` (selected/unselected tint
/// switches need a remount) and disposes the controller on unmount — fragile
/// for per-tab tint switching. `lottie` (the same engine lordicon wraps) is
/// used directly instead: this widget owns the 4 `AnimationController`s, and
/// `LottieDelegates` re-tints fills + strokes on every build.
class AnimatedBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AnimatedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<AnimatedBottomNav> createState() => _AnimatedBottomNavState();
}

class _AnimatedBottomNavState extends State<AnimatedBottomNav>
    with TickerProviderStateMixin {
  static const _assets = <String>[
    'assets/icons/nav_home.json',
    'assets/icons/nav_exam.json',
    'assets/icons/nav_discussion.json',
    'assets/icons/nav_profile.json',
  ];
  static const _labels = <String>[
    'Home',
    'Exam',
    'Discussion',
    'Profile',
  ];

  /// Slightly shorter than the package default (75).
  static const double _barHeight = 65;

  late final List<AnimationController> _controllers = List.generate(
    _assets.length,
    (_) => AnimationController(vsync: this),
  );

  @override
  void initState() {
    super.initState();
    // Park every icon on its fully-revealed final frame: the "in-reveal"
    // animations start empty at frame 0, so unselected tabs must show the
    // last frame statically instead of an invisible first frame.
    for (final c in _controllers) {
      c.value = 1.0;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _handleTap(int i) {
    // The tapped icon's reveal animation plays from the beginning; every
    // tab otherwise rests on its fully-revealed frame (see initState).
    _playFromBeginning(i);
    widget.onTap(i);
  }

  void _playFromBeginning(int i) {
    final c = _controllers[i];
    if (c.duration != null) {
      c.forward(from: 0);
    } else {
      // Composition not loaded yet (first milliseconds) — retry next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controllers[i].duration != null) {
          _controllers[i].forward(from: 0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    // Theme-aware bar: very light in light mode (a hair off-white so the
    // white circle still reads against it); in dark mode a step lighter
    // than the page bg (#1E293B) so the bar reads as a distinct surface.
    final barColor =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    // Unselected icons are BOLD, never dim: near-black in light mode,
    // white in dark mode.
    final unselectedTint =
        isDark ? Colors.white : const Color(0xFF0F172A);
    // Labels: readable on the bar in both themes.
    final labelColor =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    Widget icon(int i) {
      final selected = i == widget.currentIndex;
      final tint = selected ? blue : unselectedTint;
      return Semantics(
        button: true,
        selected: selected,
        label: _labels[i],
        child: Lottie.asset(
          _assets[i],
          controller: _controllers[i],
          onLoaded: (composition) {
            _controllers[i].duration = composition.duration;
          },
          width: selected ? 28 : 26,
          height: selected ? 28 : 26,
          delegates: LottieDelegates(
            values: [
              ValueDelegate.color(const ['**'], value: tint),
              ValueDelegate.strokeColor(const ['**'], value: tint),
            ],
          ),
        ),
      );
    }

    final labelStyle = TextStyle(
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: labelColor,
    );
    // Selected circle: dark navy in light mode (user: "white circle lai
    // dark mode ko color ko circle"), white in dark mode.
    final circleColor =
        isDark ? Colors.white : const Color(0xFF0F172A);

    // No opaque wrapper: the notch stays transparent so the page body
    // (extendBody: true) shows through. Only bottom safe-area padding.
    // Tarika 2 shadow: a soft upward shadow for subtle separation between
    // the bar and the white page above (reference-app feel). Isolated in
    // this one Container — delete it to revert. Light mode: faint black;
    // dark mode: faint white glow (black would be invisible on dark).
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SizedBox(
          height: _barHeight,
          child: Stack(
            children: [
              CurvedNavigationBar(
                index: widget.currentIndex,
                onTap: _handleTap,
                // Bar background follows the app theme.
                color: barColor,
                // Transparent notch: page content shows through.
                backgroundColor: Colors.transparent,
                // The raised circle: dark navy in light mode, white in
                // dark mode — contrast with the blue selected icon.
                buttonBackgroundColor: circleColor,
                animationDuration: const Duration(milliseconds: 350),
                animationCurve: Curves.easeInOut,
                height: _barHeight,
                items: [icon(0), icon(1), icon(2), icon(3)],
              ),
              // Labels for all 4 tabs, on one baseline below the icons (and
              // below the selected circle). The package fades the selected
              // row item out, so labels live here instead of in the items.
              // Pointer-transparent: taps must reach the bar's buttons.
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      for (int i = 0; i < _labels.length; i++)
                        Expanded(
                          child: Text(
                            _labels[i],
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle.copyWith(
                              color: i == widget.currentIndex
                                  ? blue
                                  : labelColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
