import 'package:flutter/material.dart';

import '../../services/analytics/analytics_strings.dart';

import '../../theme/app_theme.dart';
import 'analytics_shared.dart';

/// One subcourse the user can switch the analytics view to.
class SubcourseOption {
  const SubcourseOption({
    required this.subcourseId,
    required this.courseId,
    required this.name,
    required this.percent,
    required this.points,
  });

  final String subcourseId;
  final String courseId;

  /// Resolved display name; falls back to the course name upstream, never the id.
  final String name;
  final double percent;
  final int points;
}

/// Switches which subcourse the analytics page is describing.
///
/// Mirrors SubcoursePicker.tsx. Only shown when the user actually has more than
/// one subcourse with recorded history — offering a picker with a single
/// entry is noise, and the hero card hides its affordance in that case for the
/// same reason.
class SubcoursePicker extends StatefulWidget {
  const SubcoursePicker({
    super.key,
    required this.visible,
    required this.onClose,
    required this.options,
    required this.selectedId,
    required this.onSelect,
  });

  final bool visible;
  final VoidCallback onClose;
  final List<SubcourseOption> options;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<SubcoursePicker> createState() => _SubcoursePickerState();
}

class _SubcoursePickerState extends State<SubcoursePicker> {
  bool _sheetOpen = false;

  @override
  void didUpdateWidget(SubcoursePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible && !_sheetOpen) {
      _sheetOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _sheetOpen = false;
          return;
        }
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: false,
          backgroundColor: Colors.transparent,
          builder: (_) => _Sheet(
            options: widget.options,
            selectedId: widget.selectedId,
            onSelect: (id) {
              Navigator.of(context).pop();
              widget.onSelect(id);
            },
          ),
        ).then((_) {
          _sheetOpen = false;
          // A swipe-down dismiss leaves `visible` true — tell the parent to
          // close. Tapping an option already flipped it via onSelect.
          if (mounted && widget.visible) widget.onClose();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.options,
    required this.selectedId,
    required this.onSelect,
  });

  final List<SubcourseOption> options;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: ExpoSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: colors.border,
              ),
            ),
            Text(
              AnalyticsStrings.pickerTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              AnalyticsStrings.pickerSubtitle,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: ExpoSpacing.md),
            // Capped rather than unbounded: a user with many subcourses
            // should get a scrolling list, not a sheet taller than the
            // screen.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: ExpoSpacing.sm),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final selected =
                      option.subcourseId == selectedId;
                  return GestureDetector(
                    onTap: () => onSelect(option.subcourseId),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(ExpoSpacing.md),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ExpoRadius.md),
                        border: Border.all(
                          color: selected
                              ? colors.primary
                              : colors.border,
                        ),
                        color: selected
                            ? colors.primary.withValues(alpha: 0.08)
                            : colors.surfaceAlt,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: selected
                                ? colors.primary
                                : colors.textDisabled,
                          ),
                          const SizedBox(width: ExpoSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  option.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: ExpoType.body,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${formatPercent(option.percent)} · ${option.points} pts',
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
