import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:loksewa_solution/screens/tabs_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/app_link_service.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/main_leaderboard.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/services/theme_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/animated_star_rating.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import 'package:loksewa_solution/widgets/disk_cached_image.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/profile_header.dart';
import 'package:loksewa_solution/widgets/profile_rows.dart';
import 'package:loksewa_solution/widgets/profile_stats_card.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';
import 'package:loksewa_solution/widgets/trash_icon.dart';

/// Profile tab — mirrors app/(tabs)/profile.tsx.
///
/// Collapsing header (avatar ring, plan pill, language + theme toggles),
/// stats card, Account / Admin / App Settings / Support / More sections,
/// logout with a destructive confirm (550ms spinner floor + 1400ms
/// sign-out ceiling).
///
/// Everything shown here is backed by the users/{uid} Firestore document (via
/// the shared [ProfileStore]), not just the cached auth session, so the
/// values survive reinstalls and match across devices.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _scrollController = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0);
  String? _uid;

  /// True while the share link is being generated (Share App tapped, share
  /// sheet not open yet) — the profile page shows a preloading overlay so
  /// the user feels the link is being generated.
  bool _sharing = false;

  /// Guards the one-shot canonical-stats refresh per account+subcourse (see
  /// [_onStoreChanged]): the refresh ends in [ProfileStore.setScore], which
  /// notifies this same listener — without the key the refresh would loop.
  String? _canonicalKey;

  /// Minimum time the Logout button shows its spinner, so the press is visibly
  /// acknowledged even when the sign-out is instant.
  static const _logoutSpinnerFloor = Duration(milliseconds: 550);

  /// Maximum time the dialog waits on the sign-out before leaving anyway. The
  /// remaining steps are cleanup, and they complete perfectly well behind the
  /// login screen — what they must not do is hold a spinner hostage on a bad
  /// connection.
  static const _logoutWaitCeiling = Duration(milliseconds: 1400);

  /// dark theme's `palette.danger` (0xFFF87171) is a lightened tint meant for
  /// text/icons on dark surfaces — as a filled background it renders
  /// washed-out pink and white text on it fails contrast, which is why the
  /// danger styling was lost in dark mode. (Same value as
  /// `ExpoPalette.light.danger`.)
  static const _dangerFill = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final o = _scrollController.offset;
      final clamped = o < 0 ? 0.0 : o;
      if (_scrollOffset.value != clamped) _scrollOffset.value = clamped;
    });
    _uid = AuthService.currentUser?.uid;
    ProfileStore.instance.addListener(_onStoreChanged);
    // The tab widgets live in TabsScreen's `static const` list, so the
    // app-level rebuild in main.dart never reaches them (identical const
    // widgets skip element updates). Without this listener the new language
    // only appeared after an in-tab rebuild such as scrolling.
    AppLanguage.current.addListener(_onLanguageChanged);
    if (_uid != null) {
      final uid = _uid!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ProfileStore.instance.load(uid);
      });
    }
    // The store may already be loaded (e.g. coming back from Edit Profile).
    _onStoreChanged();
    // One-time share-link migration (admin only, best-effort).
    _migrateAppLinkDoc();
  }

  @override
  void dispose() {
    ProfileStore.instance.removeListener(_onStoreChanged);
    AppLanguage.current.removeListener(_onLanguageChanged);
    _scrollController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  /// Rebuilds the tab the moment the profile language converter flips the
  /// language — see the note in [initState] about the const tab list.
  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  /// Avatar URL already warmed into the disk cache — warmed once per URL so
  /// the Edit Profile header never pops the photo in late.
  String? _warmedAvatarUrl;

  void _onStoreChanged() {
    // Warm the avatar's disk cache the moment the profile lands, so the
    // Edit Profile header (and every other avatar surface) paints the photo
    // instantly instead of popping it in late. Best-effort and idempotent.
    final avatarUrl = ProfileStore.instance.profile?.photoURL;
    if (avatarUrl != null &&
        avatarUrl.isNotEmpty &&
        avatarUrl != _warmedAvatarUrl) {
      _warmedAvatarUrl = avatarUrl;
      DiskCachedImage.warm(avatarUrl);
    }
    final uid = _uid;
    final courseInfo = ProfileStore.instance.courseInfo;
    final subcourseId = courseInfo?.subcourseId;
    final profile = ProfileStore.instance.profile;
    if (uid == null ||
        uid.isEmpty ||
        subcourseId == null ||
        subcourseId.isEmpty ||
        profile == null) {
      // Profile still loading — the store reads the stored aggregate itself
      // on load; the refresh runs on the next store change.
      return;
    }
    final key = '$uid::$subcourseId';
    if (_canonicalKey == key) return;
    _canonicalKey = key;
    // Single source of truth, same as the Analytics hero and the Leaderboard
    // board: loadCanonicalStats reads the stored aggregate, refreshing it
    // first when the shared 5-minute throttle allows. The old publish-only
    // path left the card on a frozen users/{uid}.stats.points mirror whenever
    // the throttle blocked or the publish failed — the "profile says much
    // more than analytics" fossil. Never throws; a failed load simply leaves
    // the card in its honest loading/empty state.
    loadCanonicalStats(
      uid: uid,
      courseId: courseInfo?.courseId ?? '',
      subcourseId: subcourseId,
      name: profile.name,
      photoURL: profile.photoURL,
      isPro: hasActivePremium(profile),
    ).then((canonical) {
      if (!mounted || canonical == null) return;
      ProfileStore.instance.setScore(MainLeaderboardScore(
        percent: canonical.percent,
        points: canonical.points,
        activityCount: canonical.activityCount,
        breakdown: canonical.breakdown,
      ));
    }).catchError((_) => null);
  }

  /// Reload when the signed-in account changes (login/logout while mounted).
  void _syncUid(String? uid) {    if (uid == _uid) return;
    _uid = uid;
    if (uid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ProfileStore.instance.load(uid);
      });
    } else {
      ProfileStore.instance.clear();
    }
  }

  void _goToEdit() => context.push('/edit-profile');

  /// One-time migration (2026-10-02, remove in a later update): the share link
  /// One-time admin migration: the shared App Link is now the plain domain
  /// https://www.kbr.com.np (tapping it just opens / resumes the app — no
  /// in-app routing). If the seeded `app_applink_details/main` document
  /// still carries an old link (/downloadapp or /signup), an admin opening
  /// the profile flips it — no console work needed. Admin-only write per
  /// firebase.rules.
  Future<void> _migrateAppLinkDoc() async {
    try {
      final profile = ProfileStore.instance.profile;
      if (profile == null || !profile.isAdmin) return;
      final doc =
          await FirestoreRest.getDocument('app_applink_details/main');
      final link = (doc?['link'] as String?)?.trim() ?? '';
      if (link == 'https://www.kbr.com.np') return;
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.setDocument(
        'app_applink_details/main',
        {
          'link': 'https://www.kbr.com.np',
          'updatedDate': DateTime.now().toUtc(),
        },
        idToken: idToken,
        merge: true,
      );
      AppLinkService.resetForTest();
    } catch (_) {}
  }

  String? _genderLabel(String? gender) {
    switch (gender) {
      case 'male':
        return AppLanguage.tr('Male', 'पुरुष');
      case 'female':
        return AppLanguage.tr('Female', 'महिला');
      case 'other':
        return AppLanguage.tr('Other', 'अन्य');
      default:
        return null;
    }
  }

  Future<void> _toggleLanguage() async {
    final next = AppLanguage.isNepali ? AppLanguage.english : AppLanguage.nepali;
    await AppLanguage.setLanguage(next);
    if (!mounted) return;
    final languageName = next == AppLanguage.english ? 'English' : 'नेपाली';
    showToast(
      context,
      AppLanguage.tr(
        'Language changed to $languageName',
        'भाषा $languageName मा परिवर्तन भयो',
      ),
      ToastVariant.success,
    );
  }

  Future<void> _shareApp() async {
    if (_sharing) return;
    // Preloading overlay on the profile page while the link generates —
    // the user feels the link is being prepared until the share sheet opens.
    setState(() => _sharing = true);
    try {
      // The share URL comes from Firestore (app_applink_details/main) so the
      // link can change without an app update; falls back to the download page
      // until the document is seeded. Brand stays English; the tagline is the
      // app's config literal.
      await AppLinkService.ensureLoaded();
      final message =
          'Loksewa Solution — Prepare Smarter, Score Higher\n\n${AppLinkService.shareLink}';
      await Share.share(message, subject: 'Loksewa Solution');
    } catch (_) {
      // User dismissed the share sheet — nothing to report.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Rate Us — star-rating popup. "Rate Us" opens the Play Store listing via
  /// the native "loksewa_solution/media" channel (ACTION_VIEW); there is no
  /// url_launcher in this app on purpose. If the channel throws or reports
  /// failure, the link is copied to the clipboard and a toast confirms it.
  Future<void> _rateUs() async {
    const url = 'https://play.google.com/store';
    var rating = 0;
    await AppModalShell.show(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (modalContext, setModalState) => AppModalShell(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                const Icon(Icons.star, color: Color(0xFFB45309), size: 28),
          ),
          tagLabel: AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्'),
          title: Text(
            AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्'),
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLanguage.tr(
                  'How would you rate Loksewa Solution?',
                  'Loksewa Solution लाई तपाईं कति रेटिङ दिनुहुन्छ?',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              AnimatedStarRating(
                value: rating,
                onChanged: (v) => setModalState(() => rating = v),
              ),
            ],
          ),
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(modalContext).pop(),
                  child:
                      Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _openRateLink(modalContext, url),
                  child:
                      Text(AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्')),
                ),
              ),
            ],
          ),
          onClose: () => Navigator.of(modalContext).pop(),
        ),
      ),
    );
  }

  /// Opens the rating link through the native channel; falls back to copying
  /// the link + a toast when the channel throws or reports failure.
  Future<void> _openRateLink(BuildContext dialogContext, String url) async {
    var opened = false;
    try {
      final ok = await const MethodChannel('loksewa_solution/media')
          .invokeMethod<bool>('openUrl', {'url': url});
      opened = ok == true;
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      showToast(
        context,
        AppLanguage.tr('Link copied', 'लिङ्क कपी भयो'),
        ToastVariant.success,
      );
    }
  }

  Future<void> _performLogout() async {
    // Two clocks, deliberately: the spinner gets a FLOOR so a fast sign-out
    // is still visible as progress rather than a flicker, and the sign-out
    // gets a CEILING so a slow network can never bring back the frozen
    // button. Whatever is still running when the ceiling is reached is
    // cleanup behind a screen the user has already left.
    await Future.wait([
      AuthService.logout()
          .timeout(_logoutWaitCeiling, onTimeout: () {})
          .catchError((_) {}),
      Future.delayed(_logoutSpinnerFloor),
    ]);
    ProfileStore.instance.clear();
  }

  Future<void> _confirmLogout() async {
    var loggingOut = false;
    final confirmed = await AppModalShell.show<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AppModalShell(
            // White tile + strong red glyph: the old tinted tile
            // (danger @12% with a danger glyph) washed out against the
            // header gradient — in dark mode the light-red dark danger
            // made icon and chip nearly identical. The modal card is
            // white in both themes, so a solid white tile with the
            // strong-red icon reads clearly in both.
            icon: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.logout,
                  color: _dangerFill, size: 28),
            ),
            tagLabel:
                AppLanguage.tr('Please confirm', 'कृपया पुष्टि गर्नुहोस्'),
            title: Text(
              AppLanguage.tr('Logout', 'लगआउट'),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            body: Text(
              AppLanguage.tr('Are you sure you want to logout?',
                  'तपाई पक्का लगआउट गर्न चाहनुहुन्छ?'),
              style: const TextStyle(fontSize: 14),
            ),
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    // Cancel is disabled while logging out.
                    onPressed: loggingOut
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child:
                        Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _dangerFill,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: loggingOut
                        ? null
                        : () async {
                            setDialogState(() => loggingOut = true);
                            await _performLogout();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          },
                    child: loggingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(AppLanguage.tr('Logout', 'लगआउट')),
                  ),
                ),
              ],
            ),
            // Dismiss and navigate together so the app's ordinary transition
            // is what carries the user to the login screen.
            onClose: loggingOut
                ? null
                : () => Navigator.of(dialogContext).pop(false),
            // Strong red in both themes — the dark theme's lightened danger
            // would wash the header gradient out to pastel pink.
            accent: _dangerFill,
            accentMid: _dangerFill.withValues(alpha: 0.65),
            accentLight: _dangerFill.withValues(alpha: 0.25),
            tagColor: _dangerFill,
          );
        },
      ),
    );
    if (confirmed == true && mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    _syncUid(AuthService.currentUser?.uid);
    final palette = ExpoPalette.of(context);
    final store = ProfileStore.instance;

    return Container(
      color: palette.background,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final profile = store.profile;
          final courseInfo = store.courseInfo;

          // Home-style loading: while the store hasn't finished its FIRST
          // load for this user, the whole tab is the brand-navy loader —
          // no header, no text rows — exactly like HomeTab. The bottom
          // navigation stays visible because this is a tab. Background
          // preloading is untouched: when the data arrives the real header
          // + content render directly.
          // `error` counts as ready so a failed load shows the page (with
          // its retry affordances), not a spinner forever.
          // Pull-to-refresh keeps content on screen: only `loading` gates
          // this.
          final ready = profile != null || store.error;
          if (!ready) {
            return Container(
              color: const Color(0xFF03145C),
              child: PreloadingWidget(
                label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
              ),
            );
          }
          final user = AuthService.currentUser;

          // Prefer the Firestore document, fall back to the auth session
          // (which is where a Google sign-in's Gmail name/photo lands first).
          final displayName = (profile?.name.isNotEmpty ?? false)
              ? profile!.name
              : (user?.displayName ?? '');
          final photoURL = (profile?.photoURL?.isNotEmpty ?? false)
              ? profile!.photoURL
              : user?.photoURL;
          final email = (profile?.email?.isNotEmpty ?? false)
              ? profile!.email
              : user?.email;

          // Single source of truth with the Subscription Details page: once
          // the ledger lookup has settled, the active app_subscriptions
          // record's plan name wins. Before that, the mirrored users/{uid}
          // fields show (no flicker; in the common case they already agree).
          final planLabel = store.activePlanLoaded
              ? (store.activePlanName ??
                  AppLanguage.tr('Free Plan', 'निःशुल्क योजना'))
              : (profile?.isPremium == true
                  ? (profile!.premiumPlanName ??
                      (profile.premiumBillingCycle == 'yearly'
                          ? 'Premium Yearly'
                          : 'Premium Monthly'))
                  : AppLanguage.tr('Free Plan', 'निःशुल्क योजना'));

          return ValueListenableBuilder<double>(
            valueListenable: _scrollOffset,
            builder: (context, offset, __) {
              final topPad = MediaQuery.of(context).padding.top;
              final headerH = topPad + ProfileHeader.expandedHeightBase;
              final isDark =
                  Theme.of(context).brightness == Brightness.dark;

              return Stack(
                children: [
                  RefreshIndicator(
                    // Same job as progressViewOffset on the Expo side: the
                    // fixed header would otherwise cover the native spinner.
                    edgeOffset: headerH,
                    color: palette.primary,
                    onRefresh: () => _uid == null
                        ? Future.value()
                        : store.load(_uid!, refresh: true),
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: SizedBox(height: headerH + 16),
                        ),
                        SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: ProfileStatsCard(
                                // The aggregate is the ONLY source — no mirror
                                // fallback (see profile_stats_card.dart).
                                score: store.score,
                                stats: profile?.stats,
                                loading: store.scoreLoading,
                                subcourseName:
                                    courseInfo?.subcourseName,
                                onPress: () =>
                                    context.push('/analytics'),
                              ),
                            ),
                          ),
                          ..._buildSections(
                            context: context,
                            profile: profile,
                            courseInfo: courseInfo,
                            displayName: displayName,
                            email: email,
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 16, 16, 0),
                              child: SyllabusEntrance(
                                delayMs: math.min(_builtSectionCount, 8) * 60,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      // Strong red in both themes (see
                                      // _dangerFill): palette.danger is a
                                      // lightened tint in dark mode and the
                                      // button rendered washed-out pink.
                                      backgroundColor: _dangerFill,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(
                                          double.infinity, 52),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: _confirmLogout,
                                    child: Text(
                                      AppLanguage.tr(
                                          'Logout', 'लगआउट'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                  // Fixed collapsing header overlay.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ProfileHeader(
                      scrollOffset: offset,
                      displayName: displayName,
                      photoURL: photoURL,
                      subcourseName: courseInfo?.subcourseName,
                      planLabel: planLabel,
                      isPremiumPlan: profile?.isPremium == true,
                      isAdmin: profile?.isAdmin == true,
                      // Ring-only, and stricter than the pill above:
                      // hasActivePremium also checks the expiry date, so a
                      // lapsed member loses the ring the moment it runs out.
                      pro: hasActivePremium(profile),
                      languageShortLabel:
                          AppLanguage.tr('EN', 'ने'),
                      languageLabel:
                          AppLanguage.tr('ENGLISH', 'नेपाली'),
                      onToggleLanguage: _toggleLanguage,
                      onEditPress: _goToEdit,
                      isDark: isDark,
                      onToggleTheme: () =>
                          ThemeService.toggle(context),
                    ),
                  ),
                  // Share-link preloading overlay: visible from the Share App
                  // tap until the share sheet opens, so the user feels the
                  // link is being generated.
                  if (_sharing)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: Center(
                          child: PreloadingWidget(
                            tinted: true,
                            label: AppLanguage.tr(
                                'Generating link…', 'लिङ्क बनाउँदै…'),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// How many sections the last build produced (the Admin section is
  /// conditional) — used to stagger the logout button's entrance after them.
  int _builtSectionCount = 0;

  List<Widget> _buildSections({
    required BuildContext context,
    required UserProfile? profile,
    required UserCourseInfo? courseInfo,
    required String displayName,
    required String? email,
  }) {
    final slivers = <Widget>[];
    var sectionIndex = 0;

    void addSection(Widget heading, Widget card) {
      final i = sectionIndex++;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SyllabusEntrance(
              delayMs: math.min(i, 8) * 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [heading, card],
              ),
            ),
          ),
        ),
      );
    }

    // ===== Account =====
    addSection(
      ProfileSectionHeading(
        icon: Icons.person_outline,
        title: AppLanguage.tr('Account', 'खाता'),
      ),
      ProfileSectionCard(
        children: [
          ProfileInfoRow(
            icon: const Icon(Icons.person),
            label: AppLanguage.tr('Full Name', 'पूरा नाम'),
            value: displayName.isEmpty ? null : displayName,
            addLabel: AppLanguage.tr('Add your name', 'आफ्नो नाम थप्नुहोस्'),
            onAddPress: _goToEdit,
          ),
          ProfileInfoRow(
            icon: const Icon(Icons.mail),
            label: AppLanguage.tr('Email', 'इमेल'),
            value: email,
            addLabel: AppLanguage.tr('Email', 'इमेल'),
            onAddPress: _goToEdit,
          ),
          ProfileInfoRow(
            icon: const Icon(Icons.calendar_today),
            label: AppLanguage.tr('Date of Birth', 'जन्म मिति'),
            value: formatDob(profile?.dob, nepali: AppLanguage.isNepali),
            addLabel: AppLanguage.tr(
                'Add your Date of Birth', 'आफ्नो जन्म मिति थप्नुहोस्'),
            onAddPress: _goToEdit,
          ),
          ProfileInfoRow(
            icon: const Icon(Icons.wc),
            label: AppLanguage.tr('Gender', 'लिङ्ग'),
            value: _genderLabel(profile?.gender),
            addLabel:
                AppLanguage.tr('Add your Gender', 'आफ्नो लिङ्ग थप्नुहोस्'),
            onAddPress: _goToEdit,
          ),
        ],
      ),
    );

    // ===== Admin =====
    // Admin destinations live HERE and nowhere else.
    if (profile?.isAdmin == true) {
      addSection(
        const ProfileSectionHeading(
          icon: Icons.shield_outlined,
          title: 'Admin',
        ),
        ProfileSectionCard(
          children: [
            ProfileMenuRow(
              icon: const Icon(Icons.check_box_outlined),
              label: 'Answer Review',
              subtitle: AppLanguage.tr('Review submitted exam answers',
                  'पेस गरिएका परीक्षा उत्तरहरू समीक्षा गर्नुहोस्'),
              trailingText: 'Exams > Theory Desk',
              onPress: () => TabsScreen.tabIndex.value = 1,
            ),
            ProfileMenuRow(
              icon: const Icon(Icons.diamond_outlined),
              label: AppLanguage.tr(
                  'Subscription Requests', 'सदस्यता अनुरोधहरू'),
              subtitle: AppLanguage.tr('Approve or reject plan requests',
                  'योजना अनुरोधहरू स्वीकृत वा अस्वीकृत गर्नुहोस्'),
              onPress: () => context.push('/admin/subscriptions'),
            ),
            ProfileMenuRow(
              icon: const Icon(Icons.receipt_outlined),
              label: AppLanguage.tr(
                  'Purchase Request Control', 'खरिद अनुरोध नियन्त्रण'),
              subtitle: AppLanguage.tr('Verify payment proofs & purchases',
                  'भुक्तानी प्रमाण र खरिदहरू प्रमाणित गर्नुहोस्'),
              onPress: () => context.push('/admin/purchase-details'),
            ),
          ],
        ),
      );
    }

    // ===== App Settings =====
    addSection(
      ProfileSectionHeading(
        icon: Icons.tune,
        title: AppLanguage.tr('App Settings', 'एप सेटिङ'),
      ),
      ProfileSectionCard(
        children: [
          ProfileMenuRow(
            icon: const Icon(Icons.school_outlined),
            label: AppLanguage.tr('Course Details', 'कोर्स विवरण'),
            subtitle: AppLanguage.tr('Your enrolled course & subjects',
                'तपाईंको भर्ना कोर्स र विषयहरू'),
            trailingText: courseInfo?.courseName,
            onPress: () => context.push('/course-details'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.diamond_outlined),
            label: AppLanguage.tr(
                'Subscription Details', 'सदस्यता विवरण'),
            subtitle: AppLanguage.tr('Your plan, payments & request status',
                'तपाईंको योजना, भुक्तानी र अनुरोध स्थिति'),
            onPress: () => context.push('/subscription'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.receipt_outlined),
            label: AppLanguage.tr('Purchase Details', 'खरिद विवरण'),
            subtitle: AppLanguage.tr('Receipts for your purchases',
                'तपाईंका खरिदका रसिदहरू'),
            onPress: () => context.push('/purchase-details'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: 'My Answer Submissions',
            subtitle: AppLanguage.tr('Answers you sent for review',
                'समीक्षाका लागि पठाइएका तपाईंका उत्तरहरू'),
            onPress: () => context.push('/exam-answer/my-submissions'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.help_outline),
            label: AppLanguage.tr('Report Question', 'प्रश्न रिपोर्ट'),
            subtitle: AppLanguage.tr('Flag a wrong or unclear question',
                'गलत वा अस्पष्ट प्रश्न रिपोर्ट गर्नुहोस्'),
            onPress: () => context.push('/report-question'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.flag_outlined),
            label: AppLanguage.tr(
                'Your Report History', 'तपाईंका रिपोर्टहरूको इतिहास'),
            subtitle: AppLanguage.tr('Status of your past reports',
                'तपाईंका विगतका रिपोर्टहरूको स्थिति'),
            onPress: () => context.push('/report-history'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.bookmark_outline),
            label: AppLanguage.tr('Bookmarks', 'बुकमार्कहरू'),
            subtitle: AppLanguage.tr('Your saved questions & notes',
                'तपाईंले सेभ गरेका प्रश्न र नोटहरू'),
            onPress: () => context.push('/bookmarks'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.analytics_outlined),
            label: AppLanguage.tr('Analytics', 'विश्लेषण'),
            subtitle: AppLanguage.tr('Study stats, trends & progress',
                'अध्ययन तथ्याङ्क, प्रवृत्ति र प्रगति'),
            onPress: () => context.push('/analytics'),
          ),
          ProfileMenuRow(
            icon: const TrashIcon(),
            label: AppLanguage.tr('Delete Account', 'खाता मेट्नुहोस्'),
            subtitle: AppLanguage.tr('Permanently remove your account',
                'तपाईंको खाता स्थायी रूपमा हटाउनुहोस्'),
            destructive: true,
            onPress: () => context.push('/delete-account'),
          ),
        ],
      ),
    );

    // ===== Support =====
    addSection(
      ProfileSectionHeading(
        icon: Icons.contact_support_outlined,
        title: AppLanguage.tr('Support', 'सहयोग'),
      ),
      ProfileSectionCard(
        children: [
          ProfileMenuRow(
            icon: const Icon(Icons.chat_bubble_outline),
            label: AppLanguage.tr('Contact Us', 'सम्पर्क गर्नुहोस्'),
            subtitle: AppLanguage.tr('Get in touch with our team',
                'हाम्रो टोलीसँग सम्पर्क गर्नुहोस्'),
            onPress: () => context.push('/contact-us'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.warning_amber_outlined),
            label: AppLanguage.tr('Report a Problem', 'समस्या रिपोर्ट गर्नुहोस्'),
            subtitle: AppLanguage.tr('Tell us about an app issue',
                'एपको समस्या बारे हामीलाई बताउनुहोस्'),
            onPress: () => context.push('/settings/report-problem'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.verified_user_outlined),
            label: AppLanguage.tr('Privacy Policy', 'गोपनीयता नीति'),
            subtitle: AppLanguage.tr('How we handle your data',
                'हामी तपाईंको डाटा कसरी सम्हाल्छौं'),
            onPress: () => context.push('/privacy-policy'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.description_outlined),
            label: AppLanguage.tr('Terms and Conditions', 'नियम र सर्तहरू'),
            subtitle: AppLanguage.tr('Rules for using the app',
                'एप प्रयोग गर्ने नियमहरू'),
            onPress: () => context.push('/terms-conditions'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.star_outline),
            label: AppLanguage.tr('Feedback', 'प्रतिक्रिया'),
            subtitle: AppLanguage.tr('Share suggestions & ideas',
                'सुझाव र विचारहरू साझा गर्नुहोस्'),
            onPress: () => context.push('/feedback'),
          ),
        ],
      ),
    );

    // ===== More =====
    addSection(
      ProfileSectionHeading(
        icon: Icons.more_horiz,
        title: AppLanguage.tr('More', 'थप'),
      ),
      ProfileSectionCard(
        children: [
          ProfileMenuRow(
            icon: const Icon(Icons.share_outlined),
            label: AppLanguage.tr('Share App', 'एप सेयर गर्नुहोस्'),
            subtitle: AppLanguage.tr('Invite friends to join',
                'साथीहरूलाई जोइन हुन निम्तो दिनुहोस्'),
            onPress: _shareApp,
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.thumb_up_outlined),
            label: AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्'),
            subtitle: AppLanguage.tr('Leave a rating on the Play Store',
                'प्ले स्टोरमा रेटिङ दिनुहोस्'),
            onPress: _rateUs,
          ),
          // App Info moved here out of Support, as requested.
          ProfileMenuRow(
            icon: const Icon(Icons.info_outline),
            label: AppLanguage.tr('App Info', 'एप जानकारी'),
            subtitle: AppLanguage.tr('Version & app details',
                'संस्करण र एप विवरणहरू'),
            onPress: () => context.push('/app-info'),
          ),
        ],
      ),
    );

    _builtSectionCount = sectionIndex;
    return slivers;
  }
}
