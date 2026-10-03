// DiscussionActionMenu — small context menu (NOT an AppModalShell centered
// modal; AppModalShell is for centered modals). Renders as a raw
// OverlayEntry positioned at [anchorTopRight], fading in/out over 140ms,
// with elevation 4, radius 12 and min width 160.
//
// Tapping an item starts the fade-out, removes the entry, THEN calls the
// item's onSelect. Barrier taps dismiss without selecting. (Parent screens
// show their own AppModalShell confirm dialogs for destructive items.)
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'dart:async';

import 'package:flutter/material.dart';

import 'discussion_pressed.dart';

class DiscussionMenuItem {
  final String label;
  final bool danger;
  final VoidCallback onSelect;

  const DiscussionMenuItem({
    required this.label,
    this.danger = false,
    required this.onSelect,
  });
}

class DiscussionActionMenu {
  /// Shows the menu anchored at [anchorTopRight] (global coordinates, e.g.
  /// the bottom-right of the more_vert button). Completes when the menu is
  /// fully dismissed.
  static Future<void> show({
    required BuildContext context,
    required Offset anchorTopRight,
    required List<DiscussionMenuItem> items,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ActionMenuOverlay(
        anchorTopRight: anchorTopRight,
        items: items,
        onHidden: () {
          entry.remove();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

class _ActionMenuOverlay extends StatefulWidget {
  final Offset anchorTopRight;
  final List<DiscussionMenuItem> items;
  final VoidCallback onHidden;

  const _ActionMenuOverlay({
    required this.anchorTopRight,
    required this.items,
    required this.onHidden,
  });

  @override
  State<_ActionMenuOverlay> createState() => _ActionMenuOverlayState();
}

class _ActionMenuOverlayState extends State<_ActionMenuOverlay>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFEF4444);
  static const _navy = Color(0xFF0F172A);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  bool _hiding = false;
  VoidCallback? _pendingSelect;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hide([VoidCallback? then]) {
    if (_hiding) return;
    _hiding = true;
    _pendingSelect = then;
    _controller.reverse().then((_) {
      if (!mounted) return;
      widget.onHidden();
      // The item's action runs only AFTER the menu is gone.
      _pendingSelect?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final right =
        (screenW - widget.anchorTopRight.dx).clamp(8.0, screenW - 176.0);
    return Stack(
      children: [
        // Barrier: any tap outside the menu dismisses it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _hide(),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          top: widget.anchorTopRight.dy,
          right: right,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              // IntrinsicWidth: a Positioned child with only top/right
              // gets unbounded width, which would make the stretched
              // Column explode — size to the widest row instead.
              child: IntrinsicWidth(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 160),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in widget.items)
                        DiscussionPressed(
                          onTap: () => _hide(item.onSelect),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: item.danger ? _red : _navy,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
