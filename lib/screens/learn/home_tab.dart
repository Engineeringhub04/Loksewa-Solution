import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/notification_badge.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/widgets/home/home_header.dart';
import 'package:loksewa_solution/widgets/home/banner_carousel.dart';
import 'package:loksewa_solution/widgets/home/question_of_day_card.dart';
import 'package:loksewa_solution/widgets/home/subject_card_colored.dart';
import 'package:loksewa_solution/widgets/home/quick_link_button.dart';
import 'package:loksewa_solution/widgets/home/grid_button.dart';
import 'package:loksewa_solution/widgets/home/notice_card.dart';
import 'package:loksewa_solution/widgets/home/notice_date.dart';
import 'package:loksewa_solution/widgets/home/developer_card.dart';
import 'package:loksewa_solution/widgets/preloading.dart';

/// Home tab — faithful port of app/(tabs)/index.tsx:
/// collapsing HomeHeader, BannerCarousel, QuestionOfDayCard, Subjects rail,
/// Quick Links, Additional Feature 3x3, Recent Notices, App Guide 3x3,
/// About Developer. Follows the app theme (Expo light/dark tokens).
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  late Future<_HomeData> _future;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);

  // One-time splash→home entrance: header + content fade in with a gentle
  // rise the first time home data arrives. HomeTab mounts exactly once per
  // app launch (it stays alive in the tab IndexedStack), so this plays only
  // for the splash→home landing — never on tab switches or refreshes.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _entranceOpacity =
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  late final Animation<Offset> _entranceSlide =
      Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(
    CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
  );
  bool _entranceFired = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _scrollController.addListener(() {
      _scrollOffset.value = _scrollController.offset;
    });
    // Warm the shared profile store (like the root layout does on the Expo
    // side) so the header below can read name/photo from it — and so a save
    // in Edit Profile updates this header in real time. Deduplicated inside
    // the store, so racing the Profile tab's own warm-up is harmless.
    final uid = AuthService.currentUser?.uid;
    if (uid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ProfileStore.instance.load(uid);
      });
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _scrollController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  Future<_HomeData> _load() async {
    final token = await AuthService.getValidIdToken();
    final user = AuthService.currentUser;

    String? courseId;
    String? subcourseId;
    String? courseName;
    String? subcourseName;
    String? photoURL;
    bool isPremium = false;
    if (user != null) {
      try {
        final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
        courseId = userDoc?['courseId'] as String?;
        subcourseId = userDoc?['subcourseId'] as String?;
        isPremium = _isPremiumActive(userDoc);
        // React passes `storeProfile?.photoURL ?? user?.photoURL` — the
        // Firestore user doc photo wins over the auth photoURL.
        final docPhoto = userDoc?['photoURL'] as String?;
        photoURL = (docPhoto != null && docPhoto.isNotEmpty)
            ? docPhoto
            : user.photoURL;
      } catch (_) {}
      // Resolve human-readable course names for the header.
      // Collection is `app_courses` (mirrors courses.ts COURSES_COLLECTION).
      if (courseId != null) {
        try {
          final c = await FirestoreRest.getDocument('app_courses/$courseId',
              idToken: token);
          courseName = ((c?['name'] ?? c?['nameNe']) as String?)?.trim();
        } catch (_) {}
        if (subcourseId != null) {
          try {
            final sc = await FirestoreRest.getDocument(
                'app_courses/$courseId/subcourses/$subcourseId',
                idToken: token);
            subcourseName = ((sc?['name'] ?? sc?['nameNe']) as String?)?.trim();
          } catch (_) {}
          subcourseName ??= await _legacySubcourseName(token, subcourseId);
        }
      }
    }

    List<Map<String, dynamic>> banners = [];
    List<Map<String, dynamic>> notices = [];
    QotdCardStatus qotdStatus = QotdCardStatus.empty;
    Map<String, dynamic>? developer;
    int notificationCount = 0;
    try {
      banners = await FirestoreRest.listDocuments('app_home_banners',
          idToken: token, pageSize: 20);
    } catch (_) {}
    try {
      // Mirrors fetchNotices (services/notices.ts): pageSize 30, drop
      // `status == 'hidden'`, apply the subcourse targeting client-side,
      // then sort newest-first by publishedAt; Home shows the first 3.
      final allNotices = await FirestoreRest.listDocuments('app_notices',
          idToken: token, pageSize: 30);
      final visible = allNotices.where((n) {
        if ((n['status'] ?? '').toString() == 'hidden') return false;
        final targets = n['targetSubcourseIds'];
        final List list = targets is List ? targets : const [];
        if (list.isEmpty) return true;
        if (subcourseId == null || subcourseId.isEmpty) return false;
        return list.map((e) => e.toString()).contains(subcourseId);
      }).toList();
      visible.sort((a, b) {
        final pa = a['publishedAt'];
        final pb = b['publishedAt'];
        final ta = pa is DateTime ? pa.millisecondsSinceEpoch : 0;
        final tb = pb is DateTime ? pb.millisecondsSinceEpoch : 0;
        return tb.compareTo(ta);
      });
      notices = visible.take(3).toList();
    } catch (_) {}
    // QOTD status from the same source React uses: the qotd store's
    // `app_qotd_daily/{dateKey}__{courseId}__{subcourseId}` doc + today's
    // result (NOT `app_question_of_the_day/today`, which doesn't exist).
    try {
      final uid = user?.uid ?? '';
      if (uid.isNotEmpty && courseId != null && subcourseId != null) {
        final day = await fetchQotdDay(uid, courseId, subcourseId);
        if (day.courseId == courseId && day.subcourseId == subcourseId) {
          qotdStatus = day.result != null
              ? QotdCardStatus.completed
              : day.question != null
                  ? QotdCardStatus.live
                  : QotdCardStatus.empty;
        }
      }
    } catch (_) {}
    try {
      final devs = await FirestoreRest.listDocuments('app_developers',
          idToken: token, pageSize: 5);
      if (devs.isNotEmpty) developer = devs.first;
    } catch (_) {}
    try {
      notificationCount = await _unreadNotificationCount(token, user?.uid);
      // Publish to the shared badge so the header bell stays live even
      // when the count changes elsewhere (notifications page mark-all-read).
      NotificationBadge.set(notificationCount);
    } catch (_) {}

    // Subjects — mirrors loadSubjectDetails() in subjectDetails.ts: deterministic
    // document reads (`app_subjects_details/{course}__{subcourse}__{slug}`),
    // no collection scan. Falls back to the default learning scope exactly
    // like the Expo side (DEFAULT_LEARNING_COURSE_ID/SUBCOURSE_ID).
    List<Map<String, dynamic>> subjects = [];
    try {
      const subjectSlugs = [
        'general-awareness',
        'public-management',
        'technical-subject',
      ];
      final scopeCourse = courseId ?? 'civil-engineering';
      final scopeSubcourse = subcourseId ?? 'civil-assistant-sub-engineer';
      for (final slug in subjectSlugs) {
        final doc = await FirestoreRest.getDocument(
            'app_subjects_details/${scopeCourse}__${scopeSubcourse}__$slug',
            idToken: token);
        if (doc != null) {
          doc['id'] = '${scopeCourse}__${scopeSubcourse}__$slug';
          subjects.add(doc);
        }
      }
      subjects.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    } catch (_) {}

    return _HomeData(
      courseId: courseId,
      subcourseId: subcourseId,
      courseName: courseName,
      subcourseName: subcourseName,
      photoURL: photoURL ?? user?.photoURL,
      isPremium: isPremium,
      notificationCount: notificationCount,
      banners: banners,
      notices: notices,
      qotdStatus: qotdStatus,
      subjects: subjects,
      developer: developer,
    );
  }

  static bool _isPremiumActive(Map<String, dynamic>? userDoc) {
    if (userDoc == null || userDoc['isPremium'] != true) return false;
    final expiry = userDoc['premiumExpiryDate'];
    if (expiry == null) return true;
    DateTime? dt;
    if (expiry is DateTime) {
      dt = expiry;
    } else {
      dt = DateTime.tryParse('$expiry');
    }
    return dt == null || dt.isAfter(DateTime.now());
  }

  /// Legacy fallback: subcourses seeded BEFORE the sub-collection restructure
  /// live as direct documents in the flat `app_subcourses` collection —
  /// mirrors fetchUserCourseInfo() in courses.ts (direct document read,
  /// not a collection scan).
  Future<String?> _legacySubcourseName(String token, String subcourseId) async {
    try {
      final legacy = await FirestoreRest.getDocument(
          'app_subcourses/$subcourseId',
          idToken: token);
      return ((legacy?['name'] ?? legacy?['nameNe']) as String?)?.trim();
    } catch (_) {}
    return null;
  }

  /// Parses Firestore timestamp-ish values to DateTime. Best-effort.
  static DateTime? _asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// Batch-fetch exam set durations for badge expiry filtering.
  /// Returns setId → durationMinutes (60-min fallback). Never throws.
  static Future<Map<String, int>> _fetchExamDurationsForBadge(
      List<Map<String, dynamic>> examRows, String token) async {
    final result = <String, int>{};
    final setIds = <String>{};
    for (final n in examRows) {
      if ((n['type'] ?? '').toString() != 'exam') continue;
      final ids = n['examSetIds'];
      if (ids is List && ids.isNotEmpty) {
        setIds.add(ids.first.toString());
      }
    }
    if (setIds.isEmpty) return result;
    await Future.wait(setIds.map((setId) async {
      try {
        final doc = await FirestoreRest.getDocument(
          'app_exam_sets/$setId',
          idToken: token,
        );
        final dur = doc?['durationMinutes'];
        result[setId] = dur is num ? dur.toInt() : int.tryParse('$dur') ?? 60;
      } catch (_) {
        result[setId] = 60;
      }
    }));
    return result;
  }

  /// Mirrors the read-tracking in notifications_screen.dart so the header
  /// badge matches what the Notifications page considers unread.
  Future<int> _unreadNotificationCount(String token, String? uid) async {
    final results = await Future.wait([
      uid == null
          ? Future.value(<Map<String, dynamic>>[])
          : FirestoreRest.listDocuments('users/$uid/notifications',
              idToken: token),
      FirestoreRest.listDocuments('app_global_notification', idToken: token),
      // Exam-push rows: count non-expired ones so the badge matches the
      // inbox. Expiry = createdAt + the exam set's durationMinutes (same
      // logic as notifications_screen.dart). Expired rows are hidden
      // silently everywhere.
      uid == null
          ? Future.value(<Map<String, dynamic>>[])
          : FirestoreRest.listDocuments('app_exam_notifications',
              idToken: token),
    ]);
    final personal =
        results[0].map((n) => {...n, '_source': 'personal'}).toList();
    final global = results[1]
        .where((n) => (n['segment'] ?? '').toString() != 'nonlogin')
        .map((n) => {...n, '_source': 'global'})
        .toList();
    final now = DateTime.now();
    // Batch-fetch durations for exam rows (best effort; 60-min fallback).
    final Map<String, int> durations = await _fetchExamDurationsForBadge(
        results[2], token);
    final exams = results[2]
        .where((n) => (n['type'] ?? '').toString() == 'exam')
        .where((n) {
          final created = _asDateTime(n['createdAt']);
          if (created == null) return true; // can't compute → keep (safe)
          int durationMin = 60;
          final ids = n['examSetIds'];
          if (ids is List && ids.isNotEmpty) {
            durationMin = durations[ids.first.toString()] ?? 60;
          }
          return !now.isAfter(
              created.add(Duration(minutes: durationMin)));
        })
        .map((n) => {...n, '_source': 'exam'})
        .toList();
    final raw = await PrefsService.getString(
        'loksewa:notificationReadIds:${uid ?? 'guest'}');
    final Set<String> readIds = raw == null || raw.isEmpty
        ? <String>{}
        : (json.decode(raw) as List).map((e) => e.toString()).toSet();
    var count = 0;
    for (final n in [...personal, ...global, ...exams]) {
      final created = n['createdAt'];
      final ms = created is DateTime
          ? created.millisecondsSinceEpoch
          : created is num
              ? created.toInt()
              : int.tryParse('$created') ?? 0;
      final key = "${n['_source']}:${n['title']}:$ms";
      if (!readIds.contains(key)) count++;
    }
    return count;
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Container(
      color: palette.background,
      child: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            // Brand-navy loading body, exactly like React (`ready ? … : '#03145C'`):
            // splash → home reads as one continuous moment instead of a
            // stark flash, and the header never renders half-faded over it.
            return Container(
              color: const Color(0xFF03145C),
              child: const PreloadingWidget(
                label: 'Loading...',
              ),
            );
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Failed to load home.',
                      style: TextStyle(color: palette.textSecondary)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final d = snap.data!;
          final user = AuthService.currentUser;
          final topPad = MediaQuery.of(context).padding.top;
          final bottomPad = MediaQuery.of(context).padding.bottom;
          final expandedH = topPad + HomeHeader.expandedHeightBase;

          // First data arrival: play the one-time splash→home entrance so
          // header + content settle in together instead of popping.
          if (!_entranceFired) {
            _entranceFired = true;
            _entrance.forward();
          }

          return FadeTransition(
            opacity: _entranceOpacity,
            child: SlideTransition(
              position: _entranceSlide,
              child: Stack(
                children: [
                  RefreshIndicator.adaptive(
                    // The header overlays the top of the list (Stack), so the
                    // spinner would hide behind it — shift the trigger edge
                    // below the header like the profile page does. (A large
                    // `displacement` was used before; it forced a much longer
                    // drag before the spinner appeared.)
                    edgeOffset: expandedH,
                    onRefresh: () async {
                      setState(() => _future = _load());
                      // Keep the shared store fresh too, so the header (and
                      // Profile) shows the same data — mirrors index.tsx.
                      final refreshUid = AuthService.currentUser?.uid;
                      if (refreshUid != null) {
                        unawaited(ProfileStore.instance
                            .load(refreshUid, refresh: true));
                      }
                      await _future;
                    },
                    child: ListView(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                          top: expandedH, bottom: bottomPad + 96),
                      children: [
                        // Banner carousel.
                        if (d.banners.isNotEmpty) ...[
                          const SizedBox(height: ExpoSpacing.md),
                          BannerCarousel(
                            banners: d.banners.map(HomeBanner.fromMap).toList(),
                          ),
                        ],
                        // Question of the Day.
                        const SizedBox(height: ExpoSpacing.sm),
                        QuestionOfDayCard(
                          status: d.qotdStatus,
                          onPress: () => context.push('/question-of-the-day'),
                        ),
                        // Subjects.
                        _sectionHeaderRow(context, 'Subjects', '/subjects'),
                        _subjectsRail(d),
                        const SizedBox(height: ExpoSpacing.lg),
                        // Quick Links.
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ExpoSpacing.screenPadding),
                          child: _sectionTitle(context, 'Quick Links'),
                        ),
                        const SizedBox(height: ExpoSpacing.md),
                        _quickLinksRow(),
                        const SizedBox(height: ExpoSpacing.lg),
                        // Additional Feature — 3x3.
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ExpoSpacing.screenPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(context, 'Additional Feature'),
                              const SizedBox(height: ExpoSpacing.md),
                              HomeGrid3<_LinkItem>(
                                items: _additionalFeatures,
                                keyOf: (e) => e.key,
                                itemBuilder: (e, w) => GridButton(
                                  label: e.label,
                                  icon: e.icon,
                                  accentColor: const Color(0xFF7C3AED),
                                  width: w,
                                  onPress: () => context.push(e.route),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ExpoSpacing.lg),
                        // Recent Notices.
                        _sectionHeaderRow(
                            context, 'Recent Notices', '/notices'),
                        _noticesList(d),
                        const SizedBox(height: ExpoSpacing.lg),
                        // App Guide — 3x3.
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ExpoSpacing.screenPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(context, 'App Guide'),
                              const SizedBox(height: ExpoSpacing.md),
                              HomeGrid3<_LinkItem>(
                                items: _appGuide,
                                keyOf: (e) => e.key,
                                itemBuilder: (e, w) => GridButton(
                                  label: e.label,
                                  icon: e.icon,
                                  accentColor: const Color(0xFF059669),
                                  width: w,
                                  onPress: () => context.push(e.route),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ExpoSpacing.lg),
                        // About Developer.
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ExpoSpacing.screenPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(context, 'About Developer'),
                              const SizedBox(height: ExpoSpacing.md),
                              d.developer != null
                                  ? DeveloperCard(
                                      name:
                                          '${d.developer!['name'] ?? 'Developer'}',
                                      description: d.developer!['description']
                                          as String?,
                                      photoUrl: (d.developer!['photoUrl'] ??
                                          d.developer!['photo']) as String?,
                                      viewUrl:
                                          d.developer!['viewUrl'] as String?,
                                    )
                                  : _emptyState(
                                      context, 'Developer info coming soon'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Fixed collapsing header overlay. Sourced from the shared
                  // profile store first, so a photo/name change saved in Edit
                  // Profile shows up here immediately — no refresh needed
                  // (mirrors index.tsx's storeProfile-first header).
                  ValueListenableBuilder<double>(
                    valueListenable: _scrollOffset,
                    builder: (context, offset, _) => ListenableBuilder(
                      listenable: ProfileStore.instance,
                      builder: (context, _) {
                        final storeProfile = ProfileStore.instance.profile;
                        final storeName = storeProfile?.name.trim() ?? '';
                        final storePhoto = storeProfile?.photoURL;
                        // Live badge: the bell count follows the shared
                        // notifier so mark-all-read on the notifications
                        // page updates it instantly, no home reload needed.
                        return ValueListenableBuilder<int>(
                          valueListenable: NotificationBadge.unreadCount,
                          builder: (context, liveCount, _) => HomeHeader(
                            scrollOffset: offset < 0 ? 0 : offset,
                            displayName: storeName.isNotEmpty
                                ? storeName
                                : (user?.displayName ?? user?.email),
                            photoURL:
                                (storePhoto != null && storePhoto.isNotEmpty)
                                    ? storePhoto
                                    : d.photoURL,
                            pro: storeProfile != null
                                ? hasActivePremium(storeProfile)
                                : d.isPremium,
                            notificationCount: liveCount,
                            courseName: d.courseName,
                            subcourseName: d.subcourseName,
                            onNotificationsPress: () =>
                                context.push('/notifications'),
                            onProfilePress: () => context.push('/profile'),
                            onCoursePress: () =>
                                context.push('/course-setup?mode=update'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Section header row: h3 title left + "See all" pill right.
  Widget _sectionHeaderRow(
      BuildContext context, String title, String seeAllRoute) {
    final palette = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: ExpoSpacing.screenPadding,
          right: ExpoSpacing.screenPadding,
          bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: ExpoType.h3,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          Material(
            color: palette.surfaceAlt,
            borderRadius: BorderRadius.circular(ExpoRadius.pill),
            child: InkWell(
              onTap: () => context.push(seeAllRoute),
              borderRadius: BorderRadius.circular(ExpoRadius.pill),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'See all',
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: ExpoType.bodySmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final palette = ExpoPalette.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: ExpoType.h3,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
    );
  }

  Widget _emptyState(BuildContext context, String message) {
    final palette = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(message,
            style: TextStyle(color: palette.textSecondary, fontSize: 13)),
      ),
    );
  }

  Widget _subjectsRail(_HomeData d) {
    if (d.subjects.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: ExpoSpacing.screenPadding),
        child: _emptyState(context, 'No subjects yet.'),
      );
    }
    final subjects = d.subjects.take(6).toList();
    const icons = [
      Icons.public_outlined,
      Icons.work_outline,
      Icons.build_outlined,
    ];
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFFEA580C),
    ];
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: ExpoSpacing.screenPadding),
        itemCount: subjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = subjects[i];
          final name = '${s['nameNe'] ?? s['name'] ?? 'Subject'}';
          final id = '${s['id']}';
          final isPro = s['pro'] == true;
          return SubjectCardColored(
            name: name,
            icon: icons[i % icons.length],
            backgroundColor: colors[i % colors.length],
            premium: isPro,
            purchased: isPro && d.isPremium,
            onPress: () {
              final subjectKey = '$id $name'.toLowerCase();
              final hasUnits = subjectKey.contains('technical') ||
                  subjectKey.contains('प्राविधिक');
              if (isPro && !hasUnits) {
                context.push('/subjects');
                return;
              }
              context.push(
                  hasUnits ? '/subjects/units/$id' : '/subjects/chapters/$id');
            },
          );
        },
      ),
    );
  }

  Widget _quickLinksRow() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: ExpoSpacing.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final item in _quickLinks)
            QuickLinkButton(
              label: item.label,
              icon: item.icon,
              color: item.color!,
              onPress: () => context.push(item.route),
            ),
        ],
      ),
    );
  }

  Widget _noticesList(_HomeData d) {
    if (d.notices.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: ExpoSpacing.screenPadding),
        child: _emptyState(context, 'No notices yet.'),
      );
    }
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: ExpoSpacing.screenPadding),
      child: Column(
        children: [
          for (int i = 0; i < d.notices.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(builder: (context) {
              final n = d.notices[i];
              // Mirrors formatLatest: admin-typed Nepali date wins; blank
              // falls back to the publish instant rendered in English.
              final dateLabel = (n['dateLabel'] ?? '').toString().trim();
              String date = dateLabel;
              if (date.isEmpty) {
                final p = n['publishedAt'];
                if (p is DateTime) {
                  date = noticeNeDate(p);
                }
              }
              return NoticeCard(
                title: '${n['title'] ?? 'Notice'}',
                date: date,
                kind: n['kind'] as String?,
                description: (n['excerpt'] ?? n['description']) as String?,
                onPress: () => context.push('/notice/${n['id']}', extra: n),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _HomeData {
  final String? courseId;
  final String? subcourseId;
  final String? courseName;
  final String? subcourseName;
  final String? photoURL;
  final bool isPremium;
  final int notificationCount;
  final List<Map<String, dynamic>> banners;
  final List<Map<String, dynamic>> notices;
  final QotdCardStatus qotdStatus;
  final List<Map<String, dynamic>> subjects;
  final Map<String, dynamic>? developer;

  const _HomeData({
    this.courseId,
    this.subcourseId,
    this.courseName,
    this.subcourseName,
    this.photoURL,
    this.isPremium = false,
    this.notificationCount = 0,
    this.banners = const [],
    this.notices = const [],
    this.qotdStatus = QotdCardStatus.empty,
    this.subjects = const [],
    this.developer,
  });
}

class _LinkItem {
  final String key;
  final String label;
  final IconData icon;
  final String route;
  final Color? color;

  const _LinkItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.route,
    this.color,
  });
}

// Quick Links (mirrors index.tsx).
const _quickLinks = [
  _LinkItem(
      key: 'daily-test',
      label: 'Daily Test',
      icon: Icons.timer,
      route: '/daily-test',
      color: Color(0xFF1D4ED8)),
  _LinkItem(
      key: 'current-affairs',
      label: 'Current Affairs',
      icon: Icons.newspaper,
      route: '/under-construction?page=Current%20Affairs',
      color: Color(0xFF059669)),
  _LinkItem(
      key: 'syllabus',
      label: 'Syllabus',
      icon: Icons.description,
      route: '/syllabus',
      color: Color(0xFFEA580C)),
  _LinkItem(
      key: 'gorkhapatra',
      label: 'Gorkhapatra',
      icon: Icons.article,
      route: '/gorkhapatra',
      color: Color(0xFF7C3AED)),
];

// Additional Feature — 3x3 (mirrors index.tsx).
const _additionalFeatures = [
  _LinkItem(
      key: 'historical-question',
      label: 'Historical Questions',
      icon: Icons.access_time,
      route: '/exam-history'),
  _LinkItem(
      key: 'constitution',
      label: 'Nepal Constitution',
      icon: Icons.account_balance,
      route: '/constitution'),
  _LinkItem(
      key: 'practice', label: 'Practice', icon: Icons.edit, route: '/subjects'),
  _LinkItem(
      key: 'gk',
      label: 'GK',
      icon: Icons.lightbulb_outline,
      route: '/additional-features/gk'),
  _LinkItem(
      key: 'pm',
      label: 'PM',
      icon: Icons.work_outline,
      route: '/additional-features/pm'),
  _LinkItem(
      key: 'nepal-details',
      label: 'Nepal Details',
      icon: Icons.flag_outlined,
      route: '/under-construction?page=Nepal%20Details'),
  _LinkItem(
      key: 'notes',
      label: 'Keep Notes',
      icon: Icons.description_outlined,
      route: '/keep-notes'),
  _LinkItem(
      key: 'upcoming-exam',
      label: 'Upcoming Exam',
      icon: Icons.calendar_today_outlined,
      route: '/under-construction?page=Upcoming%20Exam'),
  _LinkItem(
      key: 'others',
      label: 'Others',
      icon: Icons.apps,
      route: '/under-construction?page=Others'),
];

// App Guide — 3x3 (mirrors index.tsx).
const _appGuide = [
  _LinkItem(
      key: 'download',
      label: 'Downloads',
      icon: Icons.download_outlined,
      route: '/downloads'),
  _LinkItem(
      key: 'report',
      label: 'Report Problem',
      icon: Icons.flag_outlined,
      route: '/settings/report-problem'),
  _LinkItem(
      key: 'leaderboard',
      label: 'Leaderboard',
      icon: Icons.emoji_events_outlined,
      route: '/leaderboard'),
  _LinkItem(
      key: 'bookmark',
      label: 'Bookmarks',
      icon: Icons.bookmark_outline,
      route: '/bookmarks'),
  _LinkItem(
      key: 'achievements',
      label: 'Achievements',
      icon: Icons.military_tech_outlined,
      route: '/under-construction?page=Achievements'),
  _LinkItem(
      key: 'analytics',
      label: 'Analytics',
      icon: Icons.bar_chart_outlined,
      route: '/analytics'),
  _LinkItem(
      key: 'help',
      label: 'Help Center',
      icon: Icons.help_outline,
      route: '/settings/help-center'),
  _LinkItem(
      key: 'subscription',
      label: 'Subscription Details',
      icon: Icons.diamond_outlined,
      route: '/subscription'),
  _LinkItem(
      key: 'about',
      label: 'App Info',
      icon: Icons.info_outline,
      route: '/app-info'),
];
