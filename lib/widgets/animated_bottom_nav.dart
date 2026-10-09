import 'package:flutter/material.dart';

/// Video-style animated bottom navigation bar.
///
/// When a tab is selected:
/// - a blue pill indicator SLIDES smoothly to the tab (one animation value
///   drives everything at 60fps),
/// - the selected icon LIFTS UP into the pill (translate + slight scale,
///   color lerps grey -> white),
/// - the bar background has a curved concave NOTCH hugging the pill
///   (drawn by [_NavBarPainter]).
///
/// Colors follow the app's own blue theme (NOT red): light 0xFF1D4ED8,
/// dark 0xFF3B82F6. Unselected tabs stay grey.
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

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

const _items = <_NavItem>[
  _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem(Icons.quiz_outlined, Icons.quiz_rounded, 'Exam'),
  _NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
      'Discussion'),
  _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

class _AnimatedBottomNavState extends State<AnimatedBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _position;

  double get _target => widget.currentIndex.toDouble();

  Animation<double> _makeTween(double begin, double end) =>
      Tween<double>(begin: begin, end: end).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
      );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _position = _makeTween(_target, _target);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant AnimatedBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      // Restart from the currently displayed (possibly mid-flight) value.
      _position = _makeTween(_position.value, _target);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pillColor =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final barColor = theme.colorScheme.surface;
    const unselectedColor = Colors.grey;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Geometry: pill sits in the top area, bar below it.
    const barTop = 40.0;
    const barContentH = 58.0;
    final totalH = barTop + barContentH + bottomPad;
    const pillCenterY = barTop - 10; // 30
    // Default icon center within the bar content row:
    const iconCenterY = barTop + 26;
    const lift = iconCenterY - pillCenterY; // 36

    final pos = _position.value;

    return SizedBox(
      height: totalH,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _NavBarPainter(
                position: pos,
                count: _items.length,
                barColor: barColor,
                pillColor: pillColor,
                barTop: barTop,
                pillCenterY: pillCenterY,
              ),
            ),
          ),
          Positioned(
            top: barTop,
            left: 0,
            right: 0,
            bottom: bottomPad,
            child: Row(
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                // 1 when this tab is the selected one, fading to 0 for others.
                final t = (1.0 - (pos - i).abs()).clamp(0.0, 1.0);
                final te = Curves.easeOutCubic.transform(t);
                final selected = t > 0.5;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onTap(i),
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: item.label,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform.translate(
                            offset: Offset(0, -te * lift),
                            child: Transform.scale(
                              scale: 1 + te * 0.12,
                              child: Icon(
                                te > 0.5 ? item.activeIcon : item.icon,
                                size: 26,
                                color: Color.lerp(
                                    unselectedColor, Colors.white, te),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: selected ? pillColor : unselectedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the bar background (rounded top corners + concave notch that tracks
/// the animated pill) and the pill circle itself.
class _NavBarPainter extends CustomPainter {
  final double position;
  final int count;
  final Color barColor;
  final Color pillColor;
  final double barTop;
  final double pillCenterY;

  const _NavBarPainter({
    required this.position,
    required this.count,
    required this.barColor,
    required this.pillColor,
    required this.barTop,
    required this.pillCenterY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slotW = size.width / count;
    final cx = slotW * (position + 0.5);

    const cornerR = 20.0;
    const notchHalfW = 46.0;
    const notchDepth = 20.0;
    const pillR = 26.0;

    // Bar with concave notch.
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, barTop + cornerR)
      ..quadraticBezierTo(0, barTop, cornerR, barTop)
      ..lineTo(cx - notchHalfW - 18, barTop)
      ..cubicTo(
        cx - notchHalfW + 2, barTop,
        cx - 24, barTop + notchDepth,
        cx, barTop + notchDepth,
      )
      ..cubicTo(
        cx + 24, barTop + notchDepth,
        cx + notchHalfW - 2, barTop,
        cx + notchHalfW + 18, barTop,
      )
      ..lineTo(size.width - cornerR, barTop)
      ..quadraticBezierTo(size.width, barTop, size.width, barTop + cornerR)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawShadow(
        path, Colors.black.withValues(alpha: 0.16), 8, true);
    canvas.drawPath(path, Paint()..color = barColor);

    // Pill (blue circle the selected icon lifts into).
    final pillC = Offset(cx, pillCenterY);
    canvas.drawCircle(
      pillC + const Offset(0, 4),
      pillR,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(pillC, pillR, Paint()..color = pillColor);
  }

  @override
  bool shouldRepaint(covariant _NavBarPainter old) =>
      old.position != position ||
      old.count != count ||
      old.barColor != barColor ||
      old.pillColor != pillColor;
}
