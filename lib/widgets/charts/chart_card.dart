import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The container every analytics chart sits in: heading, optional action on the
/// right, a fixed-height plot area, and the loading / empty states.
///
/// Centralising the shell is what keeps many sections looking like one page
/// instead of many separately-styled boxes, and it means a chart component
/// only ever has to worry about drawing.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    this.right,
    this.height = 180,
    this.loading = false,
    this.empty = false,
    this.emptyLabel,
    this.emptyIcon = Icons.bar_chart_outlined,
    this.footer,
    this.child,
  });

  final String title;
  final String? subtitle;

  /// Rendered at the top-right — a range switcher, legend or total.
  final Widget? right;

  /// Rendered under the plot area — legends, notes, footnotes.
  final Widget? footer;

  final bool loading;
  final bool empty;
  final String? emptyLabel;
  final IconData emptyIcon;

  /// Plot-area height. Always reserved, even while loading or empty, so the
  /// page does not reflow underneath the user as each section resolves.
  final double height;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ExpoType.h3,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ExpoType.caption,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (right != null) ...[
                const SizedBox(width: ExpoSpacing.sm),
                right!,
              ],
            ],
          ),
          const SizedBox(height: ExpoSpacing.md),
          SizedBox(
            height: height,
            child: loading
                ? const _LoadingSpinner()
                : empty
                    ? _EmptyState(icon: emptyIcon, label: emptyLabel)
                    : _FadeIn(child: child ?? const SizedBox.shrink()),
          ),
          if (footer != null && !loading && !empty) ...[
            const SizedBox(height: ExpoSpacing.sm),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: colors.textDisabled),
        const SizedBox(height: ExpoSpacing.sm),
        if (label != null)
          Text(
            label!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ExpoType.bodySmall,
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// One-shot fade-in for the plot area (240ms), matching the source behaviour.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
