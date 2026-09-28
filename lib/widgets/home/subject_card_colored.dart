import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Compact premium subject card for Home's horizontal rail
/// (mirrors SubjectCardColored.tsx). 150x130, gradient with a glow accent.
class SubjectCardColored extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onPress;
  final bool premium;
  final String premiumLabel;
  final bool purchased;
  final String purchasedLabel;

  const SubjectCardColored({
    super.key,
    required this.name,
    required this.icon,
    required this.backgroundColor,
    required this.onPress,
    this.premium = false,
    this.premiumLabel = 'Premium',
    this.purchased = false,
    this.purchasedLabel = 'Purchased',
  });

  Color _darken(Color c, int amount) {
    int ch(int v) => (v - amount).clamp(0, 255);
    return Color.fromARGB(0xFF, ch((c.r * 255).round()),
        ch((c.g * 255).round()), ch((c.b * 255).round()));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 150,
          height: 130,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [backgroundColor, _darken(backgroundColor, 40)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
            ],
          ),
          child: Stack(
            children: [
              // Glow accent, top-right.
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
              ),
              // Premium / purchased tag.
              if (premium)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 76),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      color: purchased
                          ? const Color(0xFF047857)
                          : const Color(0xFF9A3412),
                      border: Border.all(
                        color: purchased
                            ? const Color(0xC7D1FAE5)
                            : const Color(0x9EFFD5A6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          purchased
                              ? Icons.check_circle
                              : Icons.lock,
                          size: 9,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            purchased ? purchasedLabel : premiumLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: Icon(icon, size: 24, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: ExpoType.bodyLarge,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
