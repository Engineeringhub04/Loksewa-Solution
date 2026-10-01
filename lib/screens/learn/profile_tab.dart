import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:loksewa_solution/screens/tabs_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/services/theme_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
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

  /// Minimum time the Logout button shows its spinner, so the press is visibly
  /// acknowledged even when the sign-out is instant.
  static const _logoutSpinnerFloor = Duration(milliseconds: 550);

  /// Maximum time the dialog waits on the sign-out before leaving anyway. The
  /// remaining steps are cleanup, and they complete perfectly well behind the
  /// login screen — what they must not do is hold a spinner hostage on a bad
  /// connection.
  static const _logoutWaitCeiling = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final o = _scrollController.offset;
      final clamped = o < 0 ? 0.0 : o;
      if (_scrollOffset.value != clamped) _scrollOffset.value = clamped;
    });
    _uid = AuthService.currentUser?.uid;
    if (_uid != null) {
      final uid = _uid!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ProfileStore.instance.load(uid);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollOffset.dispose();
    super.dispose();
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
    // Brand stays English; the tagline is the app's config literal.
    const message =
        'Loksewa Solution — Prepare Smarter, Score Higher\n\nhttps://kbr.com.np';
    try {
      await Share.share(message, subject: 'Loksewa Solution');
    } catch (_) {
      // User dismissed the share sheet — nothing to report.
    }
  }

  /// No url_launcher in this app — the Play Store link is display-only with a
  /// copy affordance (mirrors the error-toast-on-failure with a toast here).
  Future<void> _rateUs() async {
    const url =
        'https://play.google.com/store/apps/details?id=com.loksewasolutionnp.hub';
    await AppModalShell.show(
      context: context,
      builder: (dialogContext) {
        final palette = ExpoPalette.of(dialogContext);
        return AppModalShell(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.star, color: Color(0xFFB45309), size: 28),
          ),
          tagLabel: AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्'),
          title: Text(
            AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्'),
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLanguage.tr(
                  'Copy the link below to open it in the Play Store and leave a rating.',
                  'प्ले स्टोरमा खोलेर रेटिङ दिन तलको लिङ्क कपी गर्नुहोस्।',
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: SelectableText(
                        url,
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: AppLanguage.tr('Copy link', 'लिङ्क कपी'),
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(
                            const ClipboardData(text: url));
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (mounted) {
                          showToast(
                            context,
                            AppLanguage.tr(
                                'Link copied', 'लिङ्क कपी भयो'),
                            ToastVariant.success,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          footer: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLanguage.tr('Close', 'बन्द गर्नुहोस्')),
            ),
          ),
          onClose: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
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
          final palette = ExpoPalette.of(dialogContext);
          return AppModalShell(
            icon: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.logout, color: palette.danger, size: 28),
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
                      backgroundColor: palette.danger,
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
            accent: palette.danger,
            accentMid: palette.danger.withValues(alpha: 0.65),
            accentLight: palette.danger.withValues(alpha: 0.25),
            tagColor: palette.danger,
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

          // The header stays; the body is replaced by the glow-ring until the
          // profile store has actually finished its FIRST load for this user.
          // `error` counts as ready so a failed load shows the page (with its
          // retry affordances), not a spinner forever. Pull-to-refresh keeps
          // content on screen: only `loading` gates this.
          final ready = profile != null || store.error;
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

          final planLabel = profile?.isPremium == true
              ? (profile!.premiumPlanName ??
                  (profile.premiumBillingCycle == 'yearly'
                      ? 'Premium Yearly'
                      : 'Premium Monthly'))
              : AppLanguage.tr('Free Plan', 'निःशुल्क योजना');

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
                        if (!ready)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: PreloadingWidget(
                                tinted: false,
                                label: AppLanguage.tr('Loading Profile...',
                                    'प्रोफाइल लोड हुँदैछ...'),
                                hint: AppLanguage.tr(
                                    'Fetching your stats and account',
                                    'तपाईंका तथ्याङ्क र खाता ल्याउँदै'),
                              ),
                            ),
                          )
                        else ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: ProfileStatsCard(
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
                                      backgroundColor: palette.danger,
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
              trailingText: 'Exams > Theory Desk',
              onPress: () => TabsScreen.tabIndex.value = 1,
            ),
            ProfileMenuRow(
              icon: const Icon(Icons.diamond_outlined),
              label: AppLanguage.tr(
                  'Subscription Requests', 'सदस्यता अनुरोधहरू'),
              onPress: () => context.push('/admin/subscriptions'),
            ),
            ProfileMenuRow(
              icon: const Icon(Icons.receipt_outlined),
              label: AppLanguage.tr(
                  'Purchase Request Control', 'खरिद अनुरोध नियन्त्रण'),
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
            trailingText: courseInfo?.courseName,
            onPress: () => context.push('/course-details'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.diamond_outlined),
            label: AppLanguage.tr(
                'Subscription Details', 'सदस्यता विवरण'),
            onPress: () => context.push('/subscription'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.receipt_outlined),
            label: AppLanguage.tr('Purchase Details', 'खरिद विवरण'),
            onPress: () => context.push('/purchase-details'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: 'My Answer Submissions',
            onPress: () => context.push('/exam-answer/my-submissions'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.help_outline),
            label: AppLanguage.tr('Report Question', 'प्रश्न रिपोर्ट'),
            onPress: () => context.push('/report-question'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.flag_outlined),
            label: AppLanguage.tr(
                'Your Report History', 'तपाईंका रिपोर्टहरूको इतिहास'),
            onPress: () => context.push('/report-history'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.bookmark_outline),
            label: AppLanguage.tr('Bookmarks', 'बुकमार्कहरू'),
            onPress: () => context.push('/bookmarks'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.analytics_outlined),
            label: AppLanguage.tr('Analytics', 'विश्लेषण'),
            onPress: () => context.push('/analytics'),
          ),
          ProfileMenuRow(
            icon: const TrashIcon(),
            label: AppLanguage.tr('Delete Account', 'खाता मेट्नुहोस्'),
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
            onPress: () => context.push('/contact-us'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.warning_amber_outlined),
            label: AppLanguage.tr('Report a Problem', 'समस्या रिपोर्ट गर्नुहोस्'),
            onPress: () => context.push('/settings/report-problem'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.verified_user_outlined),
            label: AppLanguage.tr('Privacy Policy', 'गोपनीयता नीति'),
            onPress: () => context.push('/privacy-policy'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.description_outlined),
            label: AppLanguage.tr('Terms and Conditions', 'नियम र सर्तहरू'),
            onPress: () => context.push('/terms-conditions'),
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.star_outline),
            label: AppLanguage.tr('Feedback', 'प्रतिक्रिया'),
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
            onPress: _shareApp,
          ),
          ProfileMenuRow(
            icon: const Icon(Icons.thumb_up_outlined),
            label: AppLanguage.tr('Rate Us', 'रेटिङ दिनुहोस्'),
            onPress: _rateUs,
          ),
          // App Info moved here out of Support, as requested.
          ProfileMenuRow(
            icon: const Icon(Icons.info_outline),
            label: AppLanguage.tr('App Info', 'एप जानकारी'),
            onPress: () => context.push('/app-info'),
          ),
        ],
      ),
    );

    _builtSectionCount = sectionIndex;
    return slivers;
  }
}
