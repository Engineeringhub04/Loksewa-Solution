import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/analytics/analytics_derive.dart';
import '../../theme/app_theme.dart';
import 'analytics_shared.dart';

/// How the number at the top of the page was arrived at, and when.
///
/// Mirrors MethodFooter.tsx. Two jobs in one footer, both about trust: the
/// weights table exists because a score nobody can audit is a score nobody
/// believes — every figure here is read from the real `PERCENT_WEIGHTS`
/// mirrors via [weightRows], so the explanation cannot drift away from the
/// scoring code the way a hand-written paragraph would.
///
/// Collapsed by default: this is reference material — the answer to a question
/// the user only asks once — and it does not deserve permanent screen space.
class MethodFooter extends StatefulWidget {
  const MethodFooter({
    super.key,
    required this.title,
    required this.intro,
    required this.weightsTitle,
    required this.labelFor,
    required this.timeNote,
    required this.estimateNote,
    required this.privacyNote,
    required this.expandLabel,
    required this.collapseLabel,
    required this.fetchedAt,
    required this.updatedLabel,
  });

  final String title;

  /// One line on what the page is measuring, above the weights.
  final String intro;

  /// Heading for the weights table.
  final String weightsTitle;

  /// Resolves a source's display name from its label key.
  final String Function(String labelKey) labelFor;

  /// Sentence about the time cap; receives the real cap in hours.
  final String Function(int hours) timeNote;

  /// Sentence about reconstructed days.
  final String estimateNote;

  /// Sentence about the data being private to this account.
  final String privacyNote;
  final String expandLabel;
  final String collapseLabel;

  /// Epoch ms the payload on screen was fetched at.
  final int fetchedAt;

  /// Renders "just now" / "5 min ago" from a key and a number.
  final String Function(String key, int value) updatedLabel;

  @override
  State<MethodFooter> createState() => _MethodFooterState();
}

class _MethodFooterState extends State<MethodFooter> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final rows = weightRows();

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(ExpoSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(ExpoRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.help_outline,
                        size: 19, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ExpoType.bodySmall,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          _open ? widget.collapseLabel : widget.expandLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ExpoType.caption,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 17,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        ExpoSpacing.md, 0, ExpoSpacing.md, ExpoSpacing.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(height: 1, color: colors.border),
                        const SizedBox(height: ExpoSpacing.sm),
                        Text(
                          widget.intro,
                          style: TextStyle(
                            fontSize: ExpoType.caption,
                            height: 17 / 11,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: ExpoSpacing.sm),
                        Text(
                          widget.weightsTitle,
                          style: TextStyle(
                            fontSize: ExpoType.caption,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // One row per source, the bar length being its share of
                        // the total weight — the table and the picture are the
                        // same object.
                        for (final row in rows)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: analyticsHex(row.color),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.labelFor(row.labelKey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: ExpoType.caption,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 74,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        ExpoRadius.pill),
                                    color: colors.surfaceAlt,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor:
                                        (row.share / 100).clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(
                                                ExpoRadius.pill),
                                        color:
                                            analyticsHex(row.color),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    '×${row.weight % 1 == 0 ? row.weight.toInt() : row.weight}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: ExpoType.caption,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: ExpoSpacing.sm),
                        Container(height: 1, color: colors.border),
                        const SizedBox(height: ExpoSpacing.sm),
                        _Note(
                            icon: Icons.schedule_outlined,
                            text: widget.timeNote(TIME_POINTS_CAP_HOURS)),
                        const SizedBox(height: 6),
                        _Note(
                            icon: Icons.analytics_outlined,
                            text: widget.estimateNote),
                        const SizedBox(height: 6),
                        _Note(
                            icon: Icons.lock_outline,
                            text: widget.privacyNote,
                            color: colors.success),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Container(height: 1, color: colors.border),
          _UpdatedLine(
              fetchedAt: widget.fetchedAt, render: widget.updatedLabel),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final iconColor = color ?? colors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 13, color: iconColor),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: ExpoType.caption,
              height: 17 / 11,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The ticking clock, isolated on purpose.
///
/// A timer at page level would re-render every chart above twice a minute for
/// the sake of one line of text. Keeping the interval down here means the
/// re-render costs exactly this row.
class _UpdatedLine extends StatefulWidget {
  const _UpdatedLine({required this.fetchedAt, required this.render});

  final int fetchedAt;
  final String Function(String key, int value) render;

  @override
  State<_UpdatedLine> createState() => _UpdatedLineState();
}

class _UpdatedLineState extends State<_UpdatedLine> {
  late int _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void didUpdateWidget(_UpdatedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fetchedAt != widget.fetchedAt) {
      setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    final rel = relativeTime(widget.fetchedAt, _now);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: ExpoSpacing.md, vertical: ExpoSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync, size: 12, color: colors.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              widget.render(rel.key, rel.value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
