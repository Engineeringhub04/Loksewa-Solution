import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Quick Links button — colored tile with white icon (mirrors
/// QuickLinkButton.tsx). Used for the 4 primary shortcuts.
class QuickLinkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPress;

  const QuickLinkButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return SizedBox(
      width: 78,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: color,
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Icon(icon, size: 24, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
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
    );
  }
}
