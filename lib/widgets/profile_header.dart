import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/theme_service.dart';

import 'profile_avatar.dart';
import 'theme_toggle.dart';

/// Collapsing curved blue header for the Profile tab.
///
/// Mirrors `src/components/profile/ProfileHeader.tsx` (and the Home header's
/// mechanics): at rest it shows the "Profile" title, language switcher, the
/// glowing avatar with a pencil badge, the user's name (with verified tick),
/// their enrolled subcourse pill and the plan pill. While scrolling it shrinks
/// in place into a compact bar — avatar, name, an "Edit Profile" text button,
/// language switcher.
///
/// Driven by the page's scroll offset (0..150 px collapse distance), exactly
/// like the Reanimated shared value on the Expo side.
class ProfileHeader extends StatelessWidget {
  static const double collapseDistance = 150;
  static const double expandedHeightBase = 278;
  static const double collapsedHeightBase = 64;

  static const _gradientColors = [
    Color(0xFF2563EB),
    Color(0xFF1D4ED8),
    Color(0xFF0B1F5B),
  ];
  static const _fallbackColor = Color(0xFF1D4ED8);

  final double scrollOffset;
  final String? displayName;
  final String? photoURL;
  final String? subcourseName;

  /// "Free Plan" or the active premium plan's name — shown below the subcourse pill.
  final String planLabel;
  final bool isPremiumPlan;

  final bool isAdmin;

  /// Premium entitlement is active RIGHT NOW — drives the avatar ring.
  /// Stricter than [isPremiumPlan] on purpose: also respects the expiry date.
  final bool pro;

  /// Short code for the ACTIVE language, e.g. 'EN' / 'ने'.
  final String languageShortLabel;

  /// Full label for the ACTIVE language, e.g. 'ENGLISH' / 'नेपाली'.
  final String languageLabel;
  final VoidCallback onToggleLanguage;
  final VoidCallback onEditPress;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const ProfileHeader({
    super.key,
    required this.scrollOffset,
    required this.displayName,
    required this.photoURL,
    required this.subcourseName,
    required this.planLabel,
    required this.isPremiumPlan,
    this.isAdmin = false,
    required this.pro,
    required this.languageShortLabel,
    required this.languageLabel,
    required this.onToggleLanguage,
    required this.onEditPress,
    required this.isDark,
    required this.onToggleTheme,
  });

  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final expandedH = topPad + expandedHeightBase;
    final collapsedH = topPad + collapsedHeightBase;
    final t = _clamp01(scrollOffset / collapseDistance);

    final height = _lerp(expandedH, collapsedH, t);
    final radius = _lerp(30, 20, t);

    // Expanded layer fades out over the first 60% of the collapse.
    final expandedOpacity =
        _clamp01(1 - scrollOffset / (collapseDistance * 0.6));
    final expandedShift = -14 * t;
    // Collapsed layer fades in over the last 55%.
    final collapsedT = _clamp01(
        (scrollOffset - collapseDistance * 0.45) / (collapseDistance * 0.55));
    final collapsedShift = 8 * (1 - collapsedT);
    final isCollapsed = scrollOffset > collapseDistance * 0.55;

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        ),
        child: Stack(
          children: [
            // Gradient background (solid fallback underneath, like Expo).
            Container(color: _fallbackColor),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            // Expanded content.
            IgnorePointer(
              ignoring: isCollapsed,
              child: Opacity(
                opacity: expandedOpacity,
                child: Transform.translate(
                  offset: Offset(0, expandedShift),
                  child: _ExpandedContent(
                    topPad: topPad,
                    displayName: displayName,
                    photoURL: photoURL,
                    subcourseName: subcourseName,
                    planLabel: planLabel,
                    isPremiumPlan: isPremiumPlan,
                    pro: pro,
                    isAdmin: isAdmin,
                    languageLabel: languageLabel,
                    onToggleLanguage: onToggleLanguage,
                    onEditPress: onEditPress,
                    isDark: isDark,
                    onToggleTheme: onToggleTheme,
                  ),
                ),
              ),
            ),
            // Collapsed content.
            IgnorePointer(
              ignoring: !isCollapsed,
              child: Opacity(
                opacity: collapsedT,
                child: Transform.translate(
                  offset: Offset(0, collapsedShift),
                  child: _CollapsedContent(
                    topPad: topPad,
                    displayName: displayName,
                    photoURL: photoURL,
                    pro: pro,
                    languageShortLabel: languageShortLabel,
                    languageLabel: languageLabel,
                    onToggleLanguage: onToggleLanguage,
                    onEditPress: onEditPress,
                    isDark: isDark,
                    onToggleTheme: onToggleTheme,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lucide "Pencil" glyph (user-requested), drawn with the same path data —
/// no new dependency.
class _PencilPainter extends CustomPainter {
  const _PencilPainter();

  static final Path _body = SvgPathParser.parse(
      'M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z');
  static final Path _tip = SvgPathParser.parse('m15 5 4 4');

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s);
    final paint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_body, paint);
    canvas.drawPath(_tip, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LanguagePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final String semanticsLabel;

  const _LanguagePill({
    required this.label,
    required this.onTap,
    required this.padding,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.white.withValues(alpha: 0.22),
        shape: StadiumBorder(
          side: BorderSide(
              color: Colors.white.withValues(alpha: 0.28), width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: padding,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  final double topPad;
  final String? displayName;
  final String? photoURL;
  final String? subcourseName;
  final String planLabel;
  final bool isPremiumPlan;
  final bool pro;
  final bool isAdmin;
  final String languageLabel;
  final VoidCallback onToggleLanguage;
  final VoidCallback onEditPress;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const _ExpandedContent({
    required this.topPad,
    required this.displayName,
    required this.photoURL,
    required this.subcourseName,
    required this.planLabel,
    required this.isPremiumPlan,
    required this.pro,
    this.isAdmin = false,
    required this.languageLabel,
    required this.onToggleLanguage,
    required this.onEditPress,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(left: 16, right: 16, top: topPad + 6, bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLanguage.tr('Profile', 'प्रोफाइल'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Theme toggle sits to the LEFT of the language switcher.
              ThemeToggle(
                  size: 36, isDark: isDark, onToggle: onToggleTheme),
              const SizedBox(width: 8),
              _LanguagePill(
                label: languageLabel,
                onTap: onToggleLanguage,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                semanticsLabel: 'Change language, currently $languageLabel',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Avatar with the edit pencil on the lower-right rim for EVERY tier.
          Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileAvatar(
                  uri: photoURL, name: displayName, size: 88, pro: pro),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                  child: InkWell(
                    onTap: onEditPress,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 30,
                      height: 30,
                      child: Center(
                        child: SizedBox(
                          width: 15,
                          height: 15,
                          child: CustomPaint(painter: _PencilPainter()),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The verified tick sits BESIDE THE NAME (Facebook style).
          Center(
            child: NameWithTick(
              name: displayName ?? '',
              pro: pro,
              tickSize: 16,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (subcourseName != null && subcourseName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                subcourseName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isPremiumPlan
                  ? const Color(0xFFFBBF24)
                  : Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPremiumPlan) ...[
                  const Icon(Icons.diamond,
                      size: 11, color: Color(0xFF7C2D12)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    planLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isPremiumPlan
                          ? const Color(0xFF7C2D12)
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedContent extends StatelessWidget {
  final double topPad;
  final String? displayName;
  final String? photoURL;
  final bool pro;
  final String languageShortLabel;
  final String languageLabel;
  final VoidCallback onToggleLanguage;
  final VoidCallback onEditPress;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const _CollapsedContent({
    required this.topPad,
    required this.displayName,
    required this.photoURL,
    required this.pro,
    required this.languageShortLabel,
    required this.languageLabel,
    required this.onToggleLanguage,
    required this.onEditPress,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: topPad),
      child: Center(
        child: Row(
          children: [
            // Same ring, scaled down — whichever one the account earns has to
            // survive the collapse, not just be visible at rest.
            ProfileAvatar(
                uri: photoURL, name: displayName, size: 30, pro: pro),
            const SizedBox(width: 8),
            // THE NAME IS THE LOWEST-PRIORITY element: it shrinks and
            // ellipsises from its tail first. Expanded (not Flexible) pins
            // the Edit Profile button and the toggles to the trailing edge
            // in a FIXED position — a short name must not shift them around.
            // NameWithTick keeps the verified tick visible beside the name.
            Expanded(
              child: NameWithTick(
                name: displayName ?? '',
                pro: pro,
                tickSize: 12,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // The Edit Profile button never shrinks.
            Material(
              color: Colors.white.withValues(alpha: 0.18),
              shape: StadiumBorder(
                side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.35), width: 1),
              ),
              child: InkWell(
                onTap: onEditPress,
                customBorder: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  child: Text(
                    AppLanguage.tr('Edit Profile', 'प्रोफाइल सम्पादन गर्नुहोस्'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Same order once collapsed: theme toggle, then language.
            ThemeToggle(
                size: 32, isDark: isDark, onToggle: onToggleTheme),
            const SizedBox(width: 8),
            _LanguagePill(
              label: languageShortLabel,
              onTap: onToggleLanguage,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              semanticsLabel: 'Change language, currently $languageLabel',
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience: flip the app theme from a header toggle.
void toggleAppTheme(BuildContext context) => ThemeService.toggle(context);
