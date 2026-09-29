import 'package:flutter/material.dart';

/// Compact premium subject card — exact port of SubjectCardColored.tsx.
/// Default 150x130 (Home's horizontal rail); the Subjects grid passes a
/// measured width + height 150 so two cards fill the row.
///
/// The glow bubble is positioned relative to the CARD edges (like React's
/// absolute positioning on the card itself) and clipped by the card's rounded
/// border via ClipRRect — so it tucks under the card edge instead of showing
/// a hard straight cut inside the card.
class SubjectCardColored extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onPress;
  final bool premium;
  final String premiumLabel;
  final bool purchased;
  final String purchasedLabel;
  final String? footerLabel;
  final VoidCallback? onFooterPress;
  final double? width;
  final double? height;

  const SubjectCardColored({
    super.key,
    required this.name,
    required this.icon,
    required this.backgroundColor,
    required this.onPress,
    this.premium = false,
    this.premiumLabel = 'Premium',
    this.purchased = false,
    this.purchasedLabel = 'Purchased (Active)',
    this.footerLabel,
    this.onFooterPress,
    this.width,
    this.height,
  });

  Color _darken(Color c, int amount) {
    int ch(int v) => (v - amount).clamp(0, 255);
    return Color.fromARGB(0xFF, ch((c.r * 255).round()),
        ch((c.g * 255).round()), ch((c.b * 255).round()));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 8,
              offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPress,
          borderRadius: BorderRadius.circular(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: width ?? 150,
              height: height ?? 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [backgroundColor, _darken(backgroundColor, 40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                // The glow bubble bleeds past the card edges on purpose —
                // ClipRRect (not the Stack) clips it, so it tucks under the
                // rounded border instead of showing a hard straight cut.
                clipBehavior: Clip.none,
                children: [
                // Glow accent, top-right — relative to the card edges.
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
                // Premium / purchased tag (React: absolute top:8 right:8 of the card).
                if (premium)
                  Positioned(
                    top: 8,
                    right: 8,
                    // No maxWidth cap: the tag is right-anchored so it grows
                    // leftward and sizes to its content — capping it made the
                    // Row overflow (RenderFlex 17px) when the label ran wide.
                    child: Container(
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
                            purchased ? Icons.check_circle : Icons.lock,
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
                // Content fills the card; React's padding applied here.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 40,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                child:
                                    Icon(icon, size: 24, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (footerLabel != null) ...[
                          const Spacer(),
                          InkWell(
                            onTap: onFooterPress ?? onPress,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      footerLabel!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward,
                                      size: 14, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
