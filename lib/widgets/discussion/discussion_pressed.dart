// Shared pressed-state wrapper for discussion widgets: while pressed the
// child scales to 0.97 and fades to 0.68 opacity, driven by a
// GestureDetector's onTapDown / onTapUp / onTapCancel (finite — the
// AnimatedScale / AnimatedOpacity tweens always settle, so widget tests
// are unaffected).
import 'package:flutter/material.dart';

class DiscussionPressed extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final double pressedOpacity;

  const DiscussionPressed({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.pressedOpacity = 0.68,
  });

  @override
  State<DiscussionPressed> createState() => _DiscussionPressedState();
}

class _DiscussionPressedState extends State<DiscussionPressed> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? widget.pressedOpacity : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}
