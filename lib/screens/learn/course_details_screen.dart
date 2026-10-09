import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';

/// Course details — mirrors app/course-details.tsx (Profile → App Settings →
/// Course details).
///
/// Reads the user's enrolled course/subcourse from users/{uid} and resolves
/// the display names from the course catalogue collections, exactly like
/// React's `fetchUserCourseInfo`: `app_courses/{id}`,
/// `app_courses/{id}/subcourses/{sub}`, with the legacy `app_subcourses/{sub}`
/// fallback for subcourses seeded before the sub-collection restructure.
class CourseDetailsScreen extends StatefulWidget {
  const CourseDetailsScreen({super.key, this.debugUid, this.loadInfo});

  /// Test seam: when set, the screen loads info for this uid instead of the
  /// signed-in user, and never touches AuthService/Firestore.
  final String? debugUid;

  /// Test seam: replaces the whole Firestore load.
  final Future<CourseDetailsInfo> Function(String uid)? loadInfo;

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

/// Resolved course info. Null names mean "not selected" (React's
/// `courseDetails.notSelected`), not an error.
class CourseDetailsInfo {
  final String? courseId;
  final String? subcourseId;
  final String? courseName;
  final String? subcourseName;

  const CourseDetailsInfo({
    this.courseId,
    this.subcourseId,
    this.courseName,
    this.subcourseName,
  });
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  bool _loading = true;
  bool _refreshing = false;
  bool _failed = false;
  CourseDetailsInfo? _info;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final info = await _loadInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final info = await _loadInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A failed refresh keeps the last good data on screen (React's
      // useAsyncData.refresh only surfaces errors on the first load).
      setState(() => _failed = _info == null);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<CourseDetailsInfo> _loadInfo() async {
    final uid = widget.debugUid ?? AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      // Not signed in: nothing to resolve — React's fetchUserCourseInfo is
      // never called without a user either (the hook returns null).
      return const CourseDetailsInfo();
    }
    if (widget.loadInfo != null) return widget.loadInfo!(uid);
    final token = await AuthService.getValidIdToken();

    final userDoc =
        await FirestoreRest.getDocument('users/$uid', idToken: token);
    final courseId = userDoc?['courseId'] as String?;
    final subcourseId = userDoc?['subcourseId'] as String?;
    if (courseId == null || courseId.isEmpty) {
      return const CourseDetailsInfo();
    }

    String? courseName;
    String? subcourseName;
    try {
      final courseDoc = await FirestoreRest.getDocument('app_courses/$courseId',
          idToken: token);
      courseName = courseDoc?['name'] as String?;
    } catch (_) {
      // ignore — course may have been removed
    }
    if (subcourseId != null && subcourseId.isNotEmpty) {
      try {
        final subDoc = await FirestoreRest.getDocument(
            'app_courses/$courseId/subcourses/$subcourseId',
            idToken: token);
        subcourseName = subDoc?['name'] as String?;
      } catch (_) {
        // ignore
      }
      if (subcourseName == null || subcourseName.isEmpty) {
        try {
          final legacyDoc = await FirestoreRest.getDocument(
              'app_subcourses/$subcourseId',
              idToken: token);
          subcourseName = legacyDoc?['name'] as String?;
        } catch (_) {
          // ignore — subcourse may have been removed
        }
      }
    }
    return CourseDetailsInfo(
      courseId: courseId,
      subcourseId: subcourseId,
      courseName: courseName,
      subcourseName: subcourseName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          SubpageHeader(title: _Strings.title),
          Expanded(
            child: RefreshIndicator.adaptive(
              onRefresh: _refresh,
              color: colors.primary,
              child: _body(context, colors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ExpoPalette colors) {
    if (_loading && !_refreshing && _info == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: PreloadingWidget(
              tinted: false,
              label: _Strings.loading,
              hint: _Strings.loadingHint,
            ),
          ),
        ],
      );
    }
    if (_failed && _info == null) {
      // Mirrors <DataNotFound onRetry={refetch} /> — the component defaults.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _DataNotFoundGate(
              title: _Strings.errorTitle,
              description: _Strings.errorDescription,
              retryLabel: _Strings.retry,
              onRetry: _boot,
            ),
          ),
        ],
      );
    }
    final info = _info ?? const CourseDetailsInfo();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SyllabusEntrance(
          delayMs: 0,
          child: _hero(info),
        ),
        const SizedBox(height: 16),
        SyllabusEntrance(
          delayMs: 60,
          child: _infoCard(colors, info),
        ),
        const SizedBox(height: 16),
        SyllabusEntrance(
          delayMs: 120,
          child: _noteBox(colors),
        ),
        const SizedBox(height: 24),
        SyllabusEntrance(
          delayMs: 180,
          child: _changeCourseButton(context),
        ),
      ],
    );
  }

  /// Premium gradient hero: decorative rings, glass school tile, the enrolled
  /// course name as the headline and the intro copy as the subtitle.
  Widget _hero(CourseDetailsInfo info) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1D4ED8),
            Color(0xFF2563EB),
            Color(0xFF3B82F6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -36,
              top: -36,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 58,
              bottom: -48,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        child: const Icon(Icons.school,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          info.courseName ?? _Strings.notSelected,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _Strings.intro,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.55,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Premium info card with the course / sub-course rows.
  Widget _infoCard(ExpoPalette colors, CourseDetailsInfo info) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border, width: 0.5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.school_outlined,
            label: _Strings.course,
            value: info.courseName ?? _Strings.notSelected,
          ),
          Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: colors.divider),
          _InfoRow(
            icon: Icons.layers_outlined,
            label: _Strings.subcourse,
            value: info.subcourseName ?? _Strings.notSelected,
          ),
        ],
      ),
    );
  }

  /// The "changing updates content" note box.
  Widget _noteBox(ExpoPalette colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _Strings.changeNote,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gradient "Change Course" CTA.
  Widget _changeCourseButton(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1D4ED8),
            Color(0xFF2563EB),
            Color(0xFF3B82F6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/course-setup?mode=update'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: Text(
                _Strings.changeCourse,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0x17 / 0xFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
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

/// Local mirror of the shared DataNotFound feedback component defaults
/// (cloud-offline icon, title, description, primary retry pill).
class _DataNotFoundGate extends StatelessWidget {
  const _DataNotFoundGate({
    required this.title,
    required this.description,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String description;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: colors.textDisabled),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 15),
              label: Text(retryLabel),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bilingual strings for this screen (mirrors `courseDetails`, `loadHints`
/// and `profile.courseDetails` in src/core/i18n).
abstract final class _Strings {
  static String get title => AppLanguage.tr('Course Details', 'कोर्स विवरण');
  static String get loading =>
      AppLanguage.tr('Loading Course Details...', 'कोर्स विवरण लोड हुँदै...');
  static String get loadingHint => AppLanguage.tr(
      'Fetching your course information', 'कोर्स जानकारी ल्याउँदै');
  static String get course => AppLanguage.tr('Course', 'कोर्स');
  static String get subcourse => AppLanguage.tr('Sub-course', 'सब-कोर्स');
  static String get notSelected =>
      AppLanguage.tr('Not selected yet', 'अझै छानिएको छैन');
  static String get intro => AppLanguage.tr(
      'This is the course your study content, mock tests and daily questions are based on.',
      'तपाईंको अध्ययन सामग्री, मक टेस्ट र दैनिक प्रश्नहरू यही कोर्समा आधारित छन्।');
  static String get changeNote => AppLanguage.tr(
      'Changing your course updates the content shown across the app. Your progress is kept.',
      'कोर्स परिवर्तन गर्दा एपभरि देखिने सामग्री अपडेट हुन्छ। तपाईंको प्रगति सुरक्षित रहन्छ।');
  static String get changeCourse =>
      AppLanguage.tr('Change Course', 'कोर्स परिवर्तन गर्नुहोस्');
  static String get errorTitle =>
      AppLanguage.tr('Data Not Found', 'डाटा भेटिएन');
  static String get errorDescription => AppLanguage.tr(
      "We couldn't load this content. Please try again.",
      'यो सामग्री लोड हुन सकेन। पुनः प्रयास गर्नुहोस्।');
  static String get retry =>
      AppLanguage.tr('Try Again', 'पुनः प्रयास गर्नुहोस्');
}
