import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Bottom navigation: the user's 4 animated Lordicon icons (bundled Lottie
/// JSON assets, `assets/icons/nav_*.json`) on the proven
/// `curved_navigation_bar` package.
///
/// Matches the user's spec:
/// - bar background: app BLUE (light 0xFF1D4ED8 / dark 0xFF3B82F6),
/// - the concave notch is TRANSPARENT — the page behind shows through
///   (the Scaffold uses `extendBody: true`),
/// - selected tab: a WHITE circle popping UP ABOVE the bar with the BLUE
///   animated Lordicon icon inside it,
/// - unselected tabs: small GRAY Lordicon icons, static first frame,
/// - tap: the tapped icon's animation plays from the beginning; the white
///   circle + blue notch slide together (~350ms, easeInOut).
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
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    Widget item(int i) {
      final selected = i == widget.currentIndex;
      final tint = selected ? blue : Colors.grey;
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
          width: selected ? 30 : 26,
          height: selected ? 30 : 26,
          delegates: LottieDelegates(
            values: [
              ValueDelegate.color(const ['**'], value: tint),
              ValueDelegate.strokeColor(const ['**'], value: tint),
            ],
          ),
        ),
      );
    }

    // No opaque wrapper: the notch stays transparent so the page body
    // (extendBody: true) shows through. Only bottom safe-area padding.
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: CurvedNavigationBar(
        index: widget.currentIndex,
        onTap: _handleTap,
        // Bar background: app blue.
        color: blue,
        // Transparent notch: page content shows through.
        backgroundColor: Colors.transparent,
        // The raised circle.
        buttonBackgroundColor: Colors.white,
        animationDuration: const Duration(milliseconds: 350),
        animationCurve: Curves.easeInOut,
        height: 75,
        items: [item(0), item(1), item(2), item(3)],
      ),
    );
  }
}
