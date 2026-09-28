import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decaying horizontal shake — mirrors the reanimated withSequence shakes in
/// login.tsx / signup.tsx (-8, 8, -6, 0). Drive with an AnimationController
/// (400ms) and call `controller.forward(from: 0.0)` to trigger.
class Shake extends StatelessWidget {
  final AnimationController controller;
  final Widget child;

  const Shake({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 4) * 8 * (1 - t);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: child,
    );
  }
}
