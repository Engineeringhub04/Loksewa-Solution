import 'package:flutter/material.dart';

/// Mirrors React Native Reanimated's `FadeInDown.delay(ms).springify()` used
/// for staggered list entrances (daily-test history + all-models rows).
///
/// Fades in while sliding up from below with a slight spring overshoot.
/// [delayMs] staggers siblings; pass `min(index, 8) * 60` for the capped
/// stagger the React lists use.
class StaggerEntrance extends StatefulWidget {
  final int delayMs;
  final Widget child;

  const StaggerEntrance({
    super.key,
    required this.delayMs,
    required this.child,
  });

  @override
  State<StaggerEntrance> createState() => _StaggerEntranceState();
}

class _StaggerEntranceState extends State<StaggerEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _opacity = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    // easeOutBack ≈ springify's overshoot: rises from below, settles.
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
