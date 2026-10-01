import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/trash_icon.dart';

/// Shared building blocks for the Profile screen's sections
/// (Account / Admin / App Settings / Support / More).
///
/// Mirrors `src/components/profile/ProfileRows.tsx`.

class ProfileSectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;

  const ProfileSectionHeading({
    super.key,
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.textPrimary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card wrapper that draws hairline dividers between its children.
class ProfileSectionCard extends StatelessWidget {
  final List<Widget> children;

  const ProfileSectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final items = children;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: palette.divider,
              ),
            items[i],
          ],
        ],
      ),
    );
  }
}

/// A single Account field. Once a value exists the row is intentionally NOT
/// pressable — only the still-empty fields invite a tap through to the edit
/// screen (no "-" placeholders anywhere).
class ProfileInfoRow extends StatelessWidget {
  final Widget icon;
  final String label;

  /// Resolved value. When null the [addLabel] placeholder is shown instead.
  final String? value;

  /// Shown (and made tappable) only when [value] is null.
  final String addLabel;
  final VoidCallback onAddPress;

  const ProfileInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.addLabel,
    required this.onAddPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final isEmpty = value == null || value!.isEmpty;

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 20,
                color: isEmpty ? palette.textSecondary : palette.textPrimary,
              ),
              child: icon,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                if (isEmpty)
                  Text(
                    addLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                  )
                else
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
          if (isEmpty)
            Icon(Icons.add_circle_outline,
                size: 20, color: palette.primary),
        ],
      ),
    );

    if (isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onAddPress,
          child: body,
        ),
      );
    }
    return body;
  }
}

/// A tappable settings/support row. Set [destructive] for Delete Account-style
/// rows; [trailingText] renders small secondary text before the chevron
/// (e.g. the current course name); [subtitle] renders a small gray
/// explainer under the bold title (the double-label pattern from the
/// reference settings design).
class ProfileMenuRow extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onPress;
  final bool destructive;
  final String? trailingText;
  final String? subtitle;

  const ProfileMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onPress,
    this.destructive = false,
    this.trailingText,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final tint = destructive ? palette.danger : palette.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0x17 / 0xFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconTheme(
                  data: IconThemeData(size: 20, color: tint),
                  child: icon,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: destructive
                            ? palette.danger
                            : palette.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingText != null && trailingText!.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    trailingText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The approved delete-icon mockup look for the Delete Account row.
/// (TrashIcon replaces Material's delete_outline everywhere.)
Widget profileTrashIcon({double size = 20, Color? color}) =>
    TrashIcon(size: size, color: color);
