import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Solid-tinted tile for the 3x3 grids (mirrors GridButton.tsx):
/// icon on a soft chip + label, filled with the section accent at low opacity.
class GridButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final double width;
  final VoidCallback onPress;

  const GridButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.width,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: accentColor.withValues(alpha: 0x17 / 0xFF),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
        child: InkWell(
          onTap: onPress,
          borderRadius: BorderRadius.circular(ExpoRadius.md),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: ExpoType.caption,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Responsive 3-column grid (mirrors Grid3.tsx): measures its own width and
/// derives the tile width so 3 columns always fit exactly.
class HomeGrid3<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T) keyOf;
  final Widget Function(T item, double width) itemBuilder;
  final double gap;

  const HomeGrid3({
    super.key,
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width - 32;
        final tileWidth =
            ((containerWidth - gap * 2) / 3).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              KeyedSubtree(
                key: ValueKey(keyOf(item)),
                child: itemBuilder(item, tileWidth),
              ),
          ],
        );
      },
    );
  }
}
