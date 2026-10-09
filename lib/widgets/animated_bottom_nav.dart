import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';

/// Bottom navigation built on the proven `curved_navigation_bar` package.
///
/// Matches the reference video:
/// - unselected tabs: small GRAY icons sitting in the bar,
/// - selected tab: a WHITE circle popping UP ABOVE the bar's top edge with
///   the DARK icon inside it,
/// - the bar's top edge has a smooth concave notch at the selected tab,
///   revealing APP BLUE behind/around the circle (like the video's red),
/// - the white circle + blue notch SLIDE TOGETHER on tab switch (~350ms,
///   easeInOut); the circle dips and rises through the transition.
///
/// Colors are the app's own BLUE theme (NOT red): light 0xFF1D4ED8,
/// dark 0xFF3B82F6. Dark-mode aware and bottom-safe-area aware.
class AnimatedBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AnimatedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final barColor = theme.colorScheme.surface;
    const unselectedColor = Colors.grey;
    const circleIconColor = Color(0xFF1F2937);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    Widget item(IconData outlined, IconData rounded, String label, int i) {
      final selected = i == currentIndex;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Icon(
          selected ? rounded : outlined,
          size: 26,
          color: selected ? circleIconColor : unselectedColor,
        ),
      );
    }

    return Container(
      // Extends the bar color full-bleed under the system nav area.
      color: barColor,
      padding: EdgeInsets.only(bottom: bottomPad),
      child: CurvedNavigationBar(
        index: currentIndex,
        onTap: onTap,
        // Bar background.
        color: barColor,
        // Revealed through the concave notch around the raised circle.
        backgroundColor: blue,
        // The raised circle.
        buttonBackgroundColor: Colors.white,
        animationDuration: const Duration(milliseconds: 350),
        animationCurve: Curves.easeInOut,
        height: 75,
        items: [
          item(Icons.home_outlined, Icons.home_rounded, 'Home', 0),
          item(Icons.quiz_outlined, Icons.quiz_rounded, 'Exam', 1),
          item(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
              'Discussion', 2),
          item(Icons.person_outline_rounded, Icons.person_rounded, 'Profile',
              3),
        ],
      ),
    );
  }
}
