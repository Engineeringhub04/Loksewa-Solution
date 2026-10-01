import 'package:flutter/material.dart';
import 'dart:async';

/// Animated star-rating row shared by the Feedback page and the Rate Us popup.
///
/// Tapping a star plays a scale-pop: the tapped star scales to ~1.25x then
/// settles back with a snappy easeOut curve (matches the user's reference video).
class AnimatedStarRating extends StatefulWidget {
  /// Currently selected rating, 0..[starCount] (0 = nothing selected).
  final int value;
  final ValueChanged<int> onChanged;
  final int starCount;
  final double size;
  final Color color;

  const AnimatedStarRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.starCount = 5,
    this.size = 36,
    this.color = const Color(0xFFFBBF24),
  });

  @override
  State<AnimatedStarRating> createState() => _AnimatedStarRatingState();
}

class _AnimatedStarRatingState extends State<AnimatedStarRating> {
  int? _popping;
  Timer? _popReset;

  @override
  void dispose() {
    _popReset?.cancel();
    super.dispose();
  }

  void _tap(int index) {
    widget.onChanged(index);
    _popReset?.cancel();
    setState(() => _popping = index);
    _popReset = Timer(const Duration(milliseconds: 340), () {
      if (mounted) setState(() => _popping = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= widget.starCount; i++)
          GestureDetector(
            onTap: () => _tap(i),
            behavior: HitTestBehavior.opaque,
            child: _PopStar(
              play: _popping == i,
              filled: i <= widget.value,
              size: widget.size,
              color: widget.color,
            ),
          ),
      ],
    );
  }
}

class _PopStar extends StatefulWidget {
  final bool play;
  final bool filled;
  final double size;
  final Color color;

  const _PopStar({
    required this.play,
    required this.filled,
    required this.size,
    required this.color,
  });

  @override
  State<_PopStar> createState() => _PopStarState();
}

class _PopStarState extends State<_PopStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.25)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.25, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(_PopStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
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
    return ScaleTransition(
      scale: _scale,
      child: Padding(
        padding: EdgeInsets.all(widget.size * 0.08),
        child: Icon(
          widget.filled ? Icons.star : Icons.star_border,
          size: widget.size,
          color: widget.filled
              ? widget.color
              : Theme.of(context).disabledColor,
        ),
      ),
    );
  }
}
