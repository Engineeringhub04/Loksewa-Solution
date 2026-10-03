// DiscussionHeartLike — optimistic heart toggle with a FINITE heart-pop
// animation (scale up, then back to 1.0 — never an infinite loop).
//
// Post-card usage: default pop (scale 1.22, 120ms up / 120ms down).
// Comment/reply usage: pass popScale: 1.24, popUpMs: 110, popDownMs: 150.
//
// The widget flips its local liked state and bumps the count immediately,
// then awaits [onToggle]. A failed future (throw or error) reverts the
// local flip and surfaces nothing — the parent owns any toast.
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'package:flutter/material.dart';

import 'discussion_pressed.dart';

class DiscussionHeartLike extends StatefulWidget {
  final bool initialLiked;
  final int likeCount;

  /// Fired AFTER the optimistic local flip. Return a failed future to
  /// revert the flip locally (the parent surfaces any toast).
  final Future<void> Function(bool newLiked) onToggle;

  final double heartSize;
  final bool compact;

  /// Heart-pop tuning: peak scale, ms up, ms back down.
  final double popScale;
  final int popUpMs;
  final int popDownMs;

  const DiscussionHeartLike({
    super.key,
    required this.initialLiked,
    required this.likeCount,
    required this.onToggle,
    this.heartSize = 20,
    this.compact = false,
    this.popScale = 1.22,
    this.popUpMs = 120,
    this.popDownMs = 120,
  });

  @override
  State<DiscussionHeartLike> createState() => _DiscussionHeartLikeState();
}

class _DiscussionHeartLikeState extends State<DiscussionHeartLike>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFEF4444);
  static const _grey = Color(0xFF94A3B8);
  static const _countGrey = Color(0xFF64748B);

  late bool _liked;
  late int _count;
  late bool _externalLiked;
  late int _externalCount;
  bool _busy = false;

  late final AnimationController _popController;
  late final Animation<double> _pop;

  @override
  void initState() {
    super.initState();
    _liked = widget.initialLiked;
    _externalLiked = widget.initialLiked;
    _count = widget.likeCount;
    _externalCount = widget.likeCount;
    _popController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.popUpMs),
    );
    _pop = Tween<double>(begin: 1.0, end: widget.popScale).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(DiscussionHeartLike oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt fresh parent state (e.g. after the parent's own toggle round-
    // trip), but never clobber an in-flight optimistic flip.
    if ((widget.initialLiked != _externalLiked ||
            widget.likeCount != _externalCount) &&
        !_busy) {
      _externalLiked = widget.initialLiked;
      _externalCount = widget.likeCount;
      _liked = _externalLiked;
      _count = _externalCount;
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  void _firePop() {
    _popController
      ..reset()
      ..duration = Duration(milliseconds: widget.popUpMs);
    _popController.forward().then((_) {
      if (!mounted) return;
      _popController.duration = Duration(milliseconds: widget.popDownMs);
      _popController.reverse();
    });
  }

  Future<void> _settle(bool newLiked) async {
    try {
      await widget.onToggle(newLiked);
    } catch (_) {
      // Revert the optimistic flip; the parent surfaces any toast.
      if (!mounted) return;
      setState(() {
        _liked = !_liked;
        _count += _liked ? 1 : -1;
      });
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  void _onTap() {
    if (_busy) return;
    _busy = true;
    final newLiked = !_liked;
    setState(() {
      _liked = newLiked;
      _count += newLiked ? 1 : -1;
    });
    _firePop();
    _settle(newLiked);
  }

  @override
  Widget build(BuildContext context) {
    return DiscussionPressed(
      onTap: _onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: widget.compact ? 2 : 4,
          horizontal: widget.compact ? 2 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pop,
              child: Icon(
                _liked ? Icons.favorite : Icons.favorite_border,
                size: widget.heartSize,
                color: _liked ? _red : _grey,
              ),
            ),
            SizedBox(width: widget.compact ? 2 : 4),
            Text(
              '$_count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _countGrey,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
