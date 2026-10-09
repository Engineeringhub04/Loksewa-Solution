import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Video-exact animated bottom navigation bar.
///
/// The reference video shows:
/// - unselected tabs: small GRAY icons sitting in the bar,
/// - selected tab: a WHITE circle popping UP ABOVE the bar's top edge with
///   the DARK icon inside it,
/// - behind/below the circle: an APP-BLUE shape whose top edge is a smooth
///   CURVE hugging the circle (a concave dip — the circle sits in a curved
///   valley of blue, like the video's red shape),
/// - animation: the white circle + blue curved shape SLIDE TOGETHER
///   horizontally as ONE unit (~350ms, easeInOut), never separating,
/// - icons animate: the selected icon scales UP + turns dark as it enters
///   the circle; unselected icons scale down + stay gray.
///
/// One [AnimationController] drives circle position, blue shape
/// position/curve and icon scale/color — all in sync at 60fps. Mid-flight
/// retargets restart smoothly from the current value (rapid taps are fine).
///
/// Colors are the app's own BLUE theme (NOT red): light 0xFF1D4ED8,
/// dark 0xFF3B82F6.
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
      duration: const Duration(milliseconds: 350),
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
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final barColor = theme.colorScheme.surface;
    const unselectedColor = Colors.grey;
    const circleIconColor = Color(0xFF1F2937);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Geometry. The white circle + blue mound live ABOVE the bar's top edge
    // (barTop) — like the video, the circle pops up out of the bar.
    const barTop = 48.0;
    const barContentH = 60.0;
    const aboveBar = 44.0; // room for the raised circle
    final totalH = aboveBar + barContentH + bottomPad;
    const circleR = 26.0;
    const circleY = barTop - 16.0; // circle center: above the bar top edge
    const iconY = barTop + 32.0; // unselected icons sit in the bar

    final pos = _position.value;

    return SizedBox(
      height: totalH,
      child: Stack(
        children: [
          // Bar background + blue curved mound (slides with the circle).
          Positioned.fill(
            child: CustomPaint(
              painter: _NavBarPainter(
                position: pos,
                count: _items.length,
                barColor: barColor,
                blue: blue,
                barTop: barTop,
                circleY: circleY,
                circleR: circleR,
              ),
            ),
          ),
          // White circle (slides as one unit with the blue mound).
          Positioned.fill(
            child: CustomPaint(
              painter: _CirclePainter(
                position: pos,
                count: _items.length,
                circleY: circleY,
                circleR: circleR,
              ),
            ),
          ),
          // Icons: unselected gray in the bar; the selected one rides in
          // the white circle, dark and scaled up.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotW = constraints.maxWidth / _items.length;
                final cx = slotW * (pos + 0.5);
                return Stack(
                  children: [
                    // Bar icons.
                    ...List.generate(_items.length, (i) {
                      final item = _items[i];
                      final t =
                          (1.0 - (pos - i).abs()).clamp(0.0, 1.0);
                      final te = Curves.easeOutCubic.transform(t);
                      final selected = t > 0.5;
                      return Positioned(
                        left: slotW * i,
                        width: slotW,
                        top: iconY - 13,
                        height: 26,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onTap(i),
                          child: Semantics(
                            button: true,
                            selected: selected,
                            label: item.label,
                            child: Center(
                              child: Opacity(
                                opacity: 1.0 - te,
                                child: Transform.scale(
                                  scale: 1.0 + 0.08 * te,
                                  child: Icon(
                                    item.icon,
                                    size: 26,
                                    color: unselectedColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    // Selected icon inside the white circle.
                    Positioned(
                      left: cx - 20,
                      width: 40,
                      top: circleY - 20,
                      height: 40,
                      child: Builder(
                        builder: (context) {
                          final settle = (1.0 - (pos - widget.currentIndex).abs())
                              .clamp(0.0, 1.0);
                          final se =
                              Curves.easeOutCubic.transform(settle);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                widget.onTap(widget.currentIndex),
                            child: Center(
                              child: Transform.scale(
                                scale: 0.8 + 0.3 * se,
                                child: Icon(
                                  _items[widget.currentIndex].activeIcon,
                                  size: 26,
                                  color: circleIconColor,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the bar background and the app-blue mound behind the selected tab.
///
/// The mound rises above the bar's top edge and its top edge is a smooth
/// concave circular seat hugging the white circle — the circle sits in a
/// curved valley of blue, exactly like the video's red shape.
class _NavBarPainter extends CustomPainter {
  final double position;
  final int count;
  final Color barColor;
  final Color blue;
  final double barTop;
  final double circleY;
  final double circleR;

  const _NavBarPainter({
    required this.position,
    required this.count,
    required this.barColor,
    required this.blue,
    required this.barTop,
    required this.circleY,
    required this.circleR,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slotW = size.width / count;
    final cx = slotW * (position + 0.5);

    // Bar with rounded top corners.
    const cornerR = 20.0;
    final barPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, barTop + cornerR)
      ..quadraticBezierTo(0, barTop, cornerR, barTop)
      ..lineTo(size.width - cornerR, barTop)
      ..quadraticBezierTo(size.width, barTop, size.width, barTop + cornerR)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawShadow(
        barPath, Colors.black.withValues(alpha: 0.16), 8, true);
    canvas.drawPath(barPath, Paint()..color = barColor);

    // Blue mound with a concave circular seat for the white circle.
    const moundHalfW = 56.0;
    final seatR = circleR + 7;
    // Seat arc: cradles the bottom of the circle — from 160° to 20° going
    // counter-clockwise through the bottom (90° in y-down coordinates).
    const startA = 160 * math.pi / 180;
    const sweepA = -140 * math.pi / 180;
    final lipLX = cx + seatR * math.cos(startA);
    final lipLY = circleY + seatR * math.sin(startA);

    final mound = Path()
      ..moveTo(cx - moundHalfW, barTop + 38)
      ..lineTo(cx - moundHalfW, barTop - 2)
      // Left flank rising to the seat's left lip.
      ..cubicTo(
        cx - moundHalfW + 16, barTop - 24,
        cx - seatR - 16, circleY - 12,
        lipLX, lipLY,
      )
      // Concave seat hugging the white circle.
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, circleY), radius: seatR),
        startA,
        sweepA,
        false,
      )
      // Right flank coming back down.
      ..cubicTo(
        cx + seatR + 16, circleY - 12,
        cx + moundHalfW - 16, barTop - 24,
        cx + moundHalfW, barTop - 2,
      )
      ..lineTo(cx + moundHalfW, barTop + 38)
      ..close();
    canvas.drawPath(mound, Paint()..color = blue);
  }

  @override
  bool shouldRepaint(covariant _NavBarPainter old) =>
      old.position != position ||
      old.count != count ||
      old.barColor != barColor ||
      old.blue != blue;
}

/// Paints the white circle that pops above the bar. Painted separately so it
/// always renders above the blue mound it sits in.
class _CirclePainter extends CustomPainter {
  final double position;
  final int count;
  final double circleY;
  final double circleR;

  const _CirclePainter({
    required this.position,
    required this.count,
    required this.circleY,
    required this.circleR,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slotW = size.width / count;
    final cx = slotW * (position + 0.5);
    final c = Offset(cx, circleY);
    canvas.drawCircle(
      c + const Offset(0, 3),
      circleR,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(c, circleR, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) =>
      old.position != position || old.count != count;
}
