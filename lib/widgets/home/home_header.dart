import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/theme_service.dart';

/// Collapsing curved gradient header for Home.
///
/// Mirrors src/components/home/HomeHeader.tsx: at rest it shows the profile
/// row (avatar + time-based greeting + name), action row (theme toggle +
/// notifications bell with badge), the search box, and the enrolled-course
/// card. While scrolling it shrinks in place into a small curved bar:
/// avatar + search icon + course name in the middle + theme toggle + bell.
///
/// Driven by the page's scroll offset (0..150 px collapse distance), exactly
/// like the Reanimated shared value on the Expo side.
class HomeHeader extends StatelessWidget {
  static const double collapseDistance = 150;
  static const double expandedHeightBase = 232;
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
  final bool pro;
  final int notificationCount;
  final String? courseName;
  final String? subcourseName;
  final VoidCallback onNotificationsPress;
  final VoidCallback onProfilePress;
  final VoidCallback onCoursePress;

  const HomeHeader({
    super.key,
    required this.scrollOffset,
    required this.displayName,
    required this.photoURL,
    this.pro = false,
    this.notificationCount = 0,
    required this.courseName,
    required this.subcourseName,
    required this.onNotificationsPress,
    required this.onProfilePress,
    required this.onCoursePress,
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
    final expandedOpacity = _clamp01(1 - scrollOffset / (collapseDistance * 0.6));
    final expandedShift = -14 * t;
    // Collapsed layer fades in over the last 55%.
    final collapsedT =
        _clamp01((scrollOffset - collapseDistance * 0.45) / (collapseDistance * 0.55));
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
                    pro: pro,
                    notificationCount: notificationCount,
                    courseName: courseName,
                    subcourseName: subcourseName,
                    onNotificationsPress: onNotificationsPress,
                    onProfilePress: onProfilePress,
                    onCoursePress: onCoursePress,
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
                    notificationCount: notificationCount,
                    courseName: courseName,
                    subcourseName: subcourseName,
                    onNotificationsPress: onNotificationsPress,
                    onProfilePress: onProfilePress,
                    onCoursePress: onCoursePress,
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

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Avatar shared by both header states — mirrors ProfileAvatar + Avatar in
/// the React app: photo when available, first+last initials otherwise; free
/// users wear the green glow ring (#22C55E), premium users the fixed
/// multi-colour sweep ring. Both rings occupy the same outer box so the
/// header never reflows when the subscription state changes.
class _Avatar extends StatelessWidget {
  final String? photoURL;
  final String? displayName;
  final bool pro;
  final double size;

  const _Avatar({
    required this.photoURL,
    required this.displayName,
    required this.pro,
    required this.size,
  });

  static const _ringColors = [
    Color(0xFF4C7CF0),
    Color(0xFF7B5FE8),
    Color(0xFFE257A6),
    Color(0xFFF6B94E),
  ];

  String _initials() {
    final name = (displayName ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    Widget face;
    if (photoURL != null && photoURL!.isNotEmpty) {
      face = ClipOval(
        child: Image.network(
          photoURL!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialFace(palette),
        ),
      );
    } else {
      face = _initialFace(palette);
    }

    if (pro) {
      // Fixed multi-colour sweep (conic-gradient equivalent).
      final ringWidth = size >= 36 ? 5.5 : 4.0;
      return Container(
        padding: EdgeInsets.all(ringWidth),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: _ringColors),
        ),
        child: ClipOval(child: SizedBox(width: size, height: size, child: face)),
      );
    }

    // Free-tier green glow ring.
    final border = size >= 36 ? 2.5 : 2.0;
    final padding = size >= 36 ? 3.0 : 2.0;
    final halo = size >= 36 ? 12.0 : 8.0;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x3822C55E),
        border: Border.all(
            color: const Color(0xFF22C55E), width: border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.9),
            blurRadius: halo,
          ),
        ],
      ),
      child: ClipOval(child: SizedBox(width: size, height: size, child: face)),
    );
  }

  Widget _initialFace(ExpoPalette palette) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceAlt,
        ),
        alignment: Alignment.center,
        child: Text(
          _initials(),
          style: TextStyle(
            color: palette.primary,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.38,
            height: 1.26,
          ),
        ),
      );
}

class _ThemeToggle extends StatelessWidget {
  final double size;
  const _ThemeToggle({required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _IconBox(
      size: size,
      onTap: () => ThemeService.toggle(context),
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: size * 0.52,
        color: Colors.white,
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final double size;
  final Widget icon;
  final VoidCallback onTap;

  const _IconBox({required this.size, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(size * 0.32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size * 0.32),
        child: SizedBox(width: size, height: size, child: Center(child: icon)),
      ),
    );
  }
}

class _Bell extends StatelessWidget {
  final double size;
  final double iconSize;
  final int count;
  final VoidCallback onTap;

  const _Bell({
    required this.size,
    required this.iconSize,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _IconBox(
          size: size,
          onTap: onTap,
          icon: Icon(Icons.notifications_outlined,
              size: iconSize, color: Colors.white),
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  final double topPad;
  final String? displayName;
  final String? photoURL;
  final bool pro;
  final int notificationCount;
  final String? courseName;
  final String? subcourseName;
  final VoidCallback onNotificationsPress;
  final VoidCallback onProfilePress;
  final VoidCallback onCoursePress;

  const _ExpandedContent({
    required this.topPad,
    required this.displayName,
    required this.photoURL,
    required this.pro,
    required this.notificationCount,
    required this.courseName,
    required this.subcourseName,
    required this.onNotificationsPress,
    required this.onProfilePress,
    required this.onCoursePress,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim().split(RegExp(r'\s+')).first
        : 'there';
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: topPad + 12, bottom: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onProfilePress,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      _Avatar(
                          photoURL: photoURL,
                          displayName: displayName,
                          pro: pro,
                          size: 44),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_greeting()},',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: ExpoType.bodySmall,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    firstName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (pro) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified,
                                      size: 16, color: Color(0xFF38BDF8)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _ThemeToggle(size: 38),
              const SizedBox(width: 10),
              _Bell(
                size: 38,
                iconSize: 20,
                count: notificationCount,
                onTap: onNotificationsPress,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Search box.
          Material(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => context.push('/search'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.75)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Search subjects, notes, exams...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: ExpoType.body,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CourseInfoCard(
            courseName: courseName,
            subcourseName: subcourseName,
            onPress: onCoursePress,
          ),
        ],
      ),
    );
  }
}

/// Premium dark-gradient enrolled-course card (mirrors CourseInfoCard.tsx).
class _CourseInfoCard extends StatelessWidget {
  final String? courseName;
  final String? subcourseName;
  final VoidCallback onPress;

  const _CourseInfoCard({
    required this.courseName,
    required this.subcourseName,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasCourse = courseName != null && courseName!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.school,
                        size: 20, color: Color(0xFF38BDF8)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'ENROLLED COURSE',
                              style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasCourse ? courseName! : 'Tap to select a course',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: ExpoType.body,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasCourse &&
                            subcourseName != null &&
                            subcourseName!.isNotEmpty)
                          Text(
                            subcourseName!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: ExpoType.bodySmall,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.chevron_right,
                        size: 16, color: Color(0xFF38BDF8)),
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

class _CollapsedContent extends StatelessWidget {
  final double topPad;
  final String? displayName;
  final String? photoURL;
  final bool pro;
  final int notificationCount;
  final String? courseName;
  final String? subcourseName;
  final VoidCallback onNotificationsPress;
  final VoidCallback onProfilePress;
  final VoidCallback onCoursePress;

  const _CollapsedContent({
    required this.topPad,
    required this.displayName,
    required this.photoURL,
    required this.pro,
    required this.notificationCount,
    required this.courseName,
    required this.subcourseName,
    required this.onNotificationsPress,
    required this.onProfilePress,
    required this.onCoursePress,
  });

  @override
  Widget build(BuildContext context) {
    final courseLabel = (courseName != null && courseName!.isNotEmpty)
        ? (subcourseName != null && subcourseName!.isNotEmpty
            ? '${courseName!} \u2022 ${subcourseName!}'
            : courseName!)
        : 'Select your course';
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: topPad),
      child: Center(
        child: Row(
          children: [
            InkWell(
              onTap: onProfilePress,
              customBorder: const CircleBorder(),
              child: _Avatar(
                  photoURL: photoURL,
                  displayName: displayName,
                  pro: pro,
                  size: 30),
            ),
            const SizedBox(width: 10),
            _IconBox(
              size: 32,
              onTap: () => context.push('/search'),
              icon: const Icon(Icons.search, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onCoursePress,
                borderRadius: BorderRadius.circular(8),
                child: Text(
                  courseLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: ExpoType.bodySmall,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const _ThemeToggle(size: 32),
            const SizedBox(width: 10),
            _Bell(
              size: 32,
              iconSize: 17,
              count: notificationCount,
              onTap: onNotificationsPress,
            ),
          ],
        ),
      ),
    );
  }
}
