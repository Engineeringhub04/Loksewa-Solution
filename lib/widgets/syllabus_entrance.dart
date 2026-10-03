import 'package:flutter/material.dart';

/// Syllabus-style entrance — the motion the user holds as the gold standard.
///
/// Faithful copy of syllabus_screen.dart's `_Entrance`: 380ms controller,
/// opacity with [Curves.easeOut], and a 24px→0 rise with [Curves.easeOut]
/// (no spring overshoot). [delayMs] staggers siblings; pass
/// `min(index, 8) * 60` for the capped stagger the syllabus lists use.
///
/// Use this on the Help, App Info, and Subscription pages. Do NOT replace
/// the shared `StaggerEntrance` (stagger_entrance.dart) elsewhere — its
/// easeOutBack spring is the approved motion for the other pages that use it.
///
/// OVERRIDDEN 2026-10-03 by explicit user request (12-point exam round): the
/// user wants this exact motion on exam quiz/review options, subject
/// chapters, subject units, and practice-mode options. subject_chapters,
/// subject_units (local _StaggeredReveal deleted), subject_read now use this;
/// practice _OptionStagger retuned to 380ms/24px/60ms to match.
class SyllabusEntrance extends StatefulWidget {
  final int delayMs;
  final Widget child;

  const SyllabusEntrance({
    super.key,
    required this.delayMs,
    required this.child,
  });

  @override
  State<SyllabusEntrance> createState() => _SyllabusEntranceState();
}

class _SyllabusEntranceState extends State<SyllabusEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<double> _dy;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _opacity = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _dy = Tween<double>(begin: 24, end: 0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOut));
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
            offset: Offset(0, _dy.value), child: child),
      ),
      child: widget.child,
    );
  }
}
