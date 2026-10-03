// Discussion feed tab (bottom-nav "Discussion").
// Mirrors app/(tabs)/discussion.tsx same-to-same:
// - gradient header (icon box + title + subtitle, info/theme/avatar actions)
//   with the search box INSIDE the header, full-bleed under the status bar
// - latest 30 posts, orderBy createdAt desc, one-shot get (no listeners)
// - like state preloaded per post (60s-cached reaction reads)
// - client-side search across title/body/category/author/course/subcourse
// - pull-to-refresh + refetch on tab refocus
// - signed-out users browse only (no FAB, like taps → sign-in prompt)
// - guidelines auto-popup once per user ever (persisted), only when the
//   Discussion tab is actually opened
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/prefs_service.dart';
import '../../services/profile_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/discussion/discussion_signin_prompt.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/discussion/discussion_action_menu.dart';
import '../../widgets/discussion/discussion_avatar.dart';
import '../../widgets/discussion/discussion_confirm_dialog.dart';
import '../../widgets/discussion/discussion_guidelines_dialog.dart';
import '../../widgets/discussion/discussion_post_card.dart';
import '../../widgets/discussion/discussion_report_dialog.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/preloading.dart';
import '../tabs_screen.dart';

class DiscussionTab extends StatefulWidget {
  const DiscussionTab({super.key});

  /// Increment to force the feed to reload (e.g. after posting).
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  static void requestRefresh() => refreshSignal.value++;

  @override
  State<DiscussionTab> createState() => _DiscussionTabState();
}

class _DiscussionTabState extends State<DiscussionTab> {
  List<DiscussionPost> _posts = [];
  final Map<String, bool> _liked = {};
  bool _loading = true;
  Object? _error;
  bool _offline = false;
  String _query = '';
  bool _wasActive = false;
  final TextEditingController _searchCtrl = TextEditingController();

  bool get _signedIn => AuthService.currentUser != null;
  bool get _isAdmin => ProfileStore.instance.profile?.isAdmin ?? false;

  List<DiscussionPost> get _visible =>
      filterDiscussions(_posts, _query);

  @override
  void initState() {
    super.initState();
    TabsScreen.tabIndex.addListener(_onTabIndexChanged);
    DiscussionTab.refreshSignal.addListener(_onRefreshSignal);
    _load();
    // Edge case: the app booted straight onto the Discussion tab (deep link
    // / restored state) — no tab-change event will fire, so check once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && TabsScreen.tabIndex.value == 2) {
        _wasActive = true;
        _maybeShowGuidelines();
      }
    });
  }

  @override
  void dispose() {
    TabsScreen.tabIndex.removeListener(_onTabIndexChanged);
    DiscussionTab.refreshSignal.removeListener(_onRefreshSignal);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (mounted) _load(silent: true);
  }

  void _onTabIndexChanged() {
    final active = TabsScreen.tabIndex.value == 2;
    if (active && !_wasActive && mounted) {
      // Focus refresh — feed only (detail screens never auto-refetch).
      _load(silent: true);
      // Guidelines: only when the user actually opens the Discussion tab,
      // and only once per user ever (persisted — survives refresh/restarts).
      _maybeShowGuidelines();
    }
    _wasActive = active;
  }

  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    // Prefetch guidelines alongside the feed so the popup opens instantly
    // when the tab is opened (no network delay on the popup itself).
    DiscussionService.prefetchDiscussionGuidelines();
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (!await _isOnline()) {
        throw const _OfflineException();
      }
      final posts = await DiscussionService.fetchDiscussions(max: 30);
      if (!mounted) return;
      // Show posts IMMEDIATELY — like statuses fill in afterwards so the
      // feed never waits on up to 30 reaction reads (the lag on slow networks).
      setState(() {
        _posts = posts;
        _error = null;
        _offline = false;
        _loading = false;
      });
      if (_signedIn && posts.isNotEmpty) {
        final results = await Future.wait(
            posts.map((p) => DiscussionService.isDiscussionLiked(p.id)));
        if (!mounted) return;
        final likes = <String, bool>{};
        for (var i = 0; i < posts.length; i++) {
          likes[posts[i].id] = results[i];
        }
        setState(() {
          _liked
            ..clear()
            ..addAll(likes);
        });
      } else if (!mounted) {
        return;
      } else {
        setState(() {
          _liked.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _offline = e is _OfflineException;
        _loading = false;
      });
    }
  }

  /// Community Guidelines popup: shows ONLY when the user opens the
  /// Discussion tab, and only ONCE per user ever — the "seen" flag is
  /// persisted, so refresh / app restart never re-shows it.
  Future<void> _maybeShowGuidelines() async {
    if (!mounted) return;
    final uid = AuthService.currentUser?.uid ?? '';
    final key =
        'discussion_guidelines_seen_${uid.isEmpty ? 'guest' : uid}';
    try {
      if (await PrefsService.getBool(key) == true) return;
    } catch (_) {
      return;
    }
    try {
      // Cached-first: instant when prefetched during the feed load.
      final g = await DiscussionService.fetchDiscussionGuidelinesCached();
      if (!mounted) return;
      // Mark seen BEFORE showing: a dismiss/crash must not re-trigger it.
      await PrefsService.setBool(key, true);
      if (!mounted) return;
      final seeded = await DiscussionGuidelinesDialog.show(
        context: context,
        guidelines: g,
        showSeedButton: g.fromDefaults && _isAdmin,
        onSeed: () async {
          await DiscussionService.seedDiscussionGuidelines();
        },
      );
      if (seeded && mounted) {
        showToast(
            context,
            AppLanguage.tr(
                'Guidelines saved', 'नियमहरू सुरक्षित गरियो'),
            ToastVariant.success);
      }
    } catch (_) {
      // Guidelines are advisory — never block the feed.
    }
  }

  void _promptSignIn() {
    DiscussionSignInPrompt.show(context);
  }

  Future<void> _onToggleLike(DiscussionPost post, bool liked) async {
    if (!_signedIn) {
      _promptSignIn();
      throw const AuthRequiredException();
    }
    try {
      await DiscussionService.toggleLikeDiscussion(post.id, liked);
      _liked[post.id] = liked;
    } catch (_) {
      rethrow;
    }
  }

  void _onMenu(DiscussionPost post, Offset anchor) {
    final uid = AuthService.currentUser?.uid;
    final canModerate =
        _isAdmin || (uid != null && uid.isNotEmpty && uid == post.authorId);
    final items = <DiscussionMenuItem>[
      if (canModerate)
        DiscussionMenuItem(
          label: AppLanguage.tr('Edit', 'सम्पादन गर्नुहोस्'),
          onSelect: () =>
              context.push('/discussion/create?editId=${post.id}'),
        ),
      if (canModerate)
        DiscussionMenuItem(
          label: AppLanguage.tr('Delete', 'मेट्नुहोस्'),
          danger: true,
          onSelect: () => _confirmDelete(post),
        ),
      if (!canModerate)
        DiscussionMenuItem(
          label: AppLanguage.tr('Report post', 'पोस्ट रिपोर्ट गर्नुहोस्'),
          onSelect: () => DiscussionReportDialog.show(
            context: context,
            targetType: 'post',
            targetId: post.id,
            targetTitle: post.title,
          ).then((ok) {
            if (ok == true && mounted) {
              showToast(
                  context,
                  AppLanguage.tr(
                      'Post reported', 'पोस्ट रिपोर्ट गरियो'),
                  ToastVariant.success);
            }
          }),
        ),
    ];
    if (items.isEmpty) return;
    DiscussionActionMenu.show(
        context: context, anchorTopRight: anchor, items: items);
  }

  Future<void> _confirmDelete(DiscussionPost post) async {
    final ok = await confirmDiscussionDelete(
      context: context,
      title: AppLanguage.tr('Delete this post?', 'यो पोस्ट मेट्ने हो?'),
      message: AppLanguage.tr('This action cannot be undone.',
          'यो काम फर्काउन मिल्दैन।'),
      onConfirm: () => DiscussionService.deleteDiscussion(post.id),
    );
    if (ok) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    // No outer SafeArea: the header is full-bleed under the status bar
    // (its own internal SafeArea pads the title row) — an outer SafeArea
    // would push the header down and leave a gap above it.
    return Scaffold(
      backgroundColor: ExpoPalette.of(context).background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _signedIn
          ? FloatingActionButton(
              onPressed: () => context.push('/discussion/create'),
              tooltip: AppLanguage.tr('Create Post', 'पोस्ट बनाउनुहोस्'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add, size: 26),
            )
          : null,
    );
  }

  /// Gradient header — same-to-same with app/(tabs)/discussion.tsx:
  /// icon box + title + guidelines subtitle, info/theme/avatar actions,
  /// and the search box INSIDE the header. Full-bleed under the status bar.
  Widget _buildHeader() {
    final profile = ProfileStore.instance.profile;
    final displayName = (profile?.name.isNotEmpty ?? false)
        ? profile!.name
        : (AuthService.currentUser?.displayName ?? '');
    final photoURL = profile?.photoURL;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1D4ED8),
          gradient: LinearGradient(
            colors: [
              Color(0xFF2563EB),
              Color(0xFF1D4ED8),
              Color(0xFF0B1F5B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.17),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.forum,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLanguage.tr('Discussion', 'छलफल'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            AppLanguage.tr('Community Guidelines',
                                'समुदायका नियमहरू'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Info → guidelines on demand.
                    GestureDetector(
                      onTap: _showGuidelinesNow,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.info_outline,
                          size: 21,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => ThemeService.toggle(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => TabsScreen.tabIndex.value = 3,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: DiscussionAvatar(
                          photoUrl: photoURL,
                          name: displayName,
                          radius: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 19,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              setState(() => _query = v),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                          decoration: InputDecoration(
                            hintText: AppLanguage.tr(
                                'Search discussions...',
                                'छलफल खोज्नुहोस्...'),
                            hintStyle: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.68),
                              decoration: TextDecoration.none,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.cancel,
                              size: 18,
                              color:
                                  Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Info-button path: guidelines on demand (no once-only gate here — the
  /// user explicitly asked to see them).
  Future<void> _showGuidelinesNow() async {
    try {
      final g = await DiscussionService.fetchDiscussionGuidelinesCached();
      if (!mounted) return;
      await DiscussionGuidelinesDialog.show(
        context: context,
        guidelines: g,
        showSeedButton: g.fromDefaults && _isAdmin,
        onSeed: () async {
          await DiscussionService.seedDiscussionGuidelines();
        },
      );
    } catch (_) {
      // Advisory only.
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: PreloadingWidget(label: AppLanguage.tr('Loading discussions...', 'छलफलहरू लोड हुँदैछन्...')));
    }
    if (_error != null) {
      return _ErrorState(
        offline: _offline,
        onRetry: () => _load(),
      );
    }
    final posts = _visible;
    if (posts.isEmpty) {
      return _EmptyState(
        searching: _query.trim().isNotEmpty,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      // React parity: no list entrance animations on the feed — plain list
      // with 16px gaps, 16px horizontal padding.
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: posts.length,
        itemBuilder: (context, i) {
          final post = posts[i];
          return Padding(
            padding: EdgeInsets.only(
                bottom: i == posts.length - 1 ? 0 : 16),
            child: DiscussionPostCard(
              post: post,
              liked: _liked[post.id] ?? false,
              onToggleLike: (liked) => _onToggleLike(post, liked),
              onTap: () => context.push('/discussion/${post.id}'),
              onMenu: (anchor) => _onMenu(post, anchor),
              // Global image viewer (app-wide rule): tap the post image →
              // dimmed popup with pinch zoom.
              onImageTap: (post.imageUrl ?? '').trim().isNotEmpty
                  ? () => showImageViewer(
                      context, NetworkImage(post.imageUrl!.trim()))
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _OfflineException implements Exception {
  const _OfflineException();
}

class _ErrorState extends StatelessWidget {
  final bool offline;
  final VoidCallback onRetry;

  const _ErrorState({required this.offline, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.wifi_off_outlined : Icons.error_outline,
              size: 44,
              color: ExpoPalette.of(context).textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              offline
                  ? AppLanguage.tr('You are offline',
                      'तपाईं अफलाइन हुनुहुन्छ')
                  : AppLanguage.tr('Could not load discussions',
                      'छलफलहरू लोड हुन सकेन'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none),
            ),
            const SizedBox(height: 6),
            Text(
              AppLanguage.tr('Check your connection and try again.',
                  'आफ्नो जडान जाँचेर पुन: प्रयास गर्नुहोस्।'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: ExpoPalette.of(context).textSecondary,
                  decoration: TextDecoration.none),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(AppLanguage.tr('Retry', 'पुन: प्रयास'),
                  style: const TextStyle(decoration: TextDecoration.none)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;

  const _EmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 44, color: ExpoPalette.of(context).textSecondary),
            const SizedBox(height: 12),
            Text(
              searching
                  ? AppLanguage.tr('No discussions match your search.',
                      'तपाईंको खोजसँग मिल्ने छलफल छैन।')
                  : AppLanguage.tr('No discussions yet. Be the first to post!',
                      'अहिलेसम्म कुनै छलफल छैन। पहिलो पोस्ट गर्ने बन्नुहोस्!'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none),
            ),
            // React parity: CTA → create page (only when not searching).
            if (!searching) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.push('/discussion/create'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLanguage.tr(
                      'Create the first post', 'पहिलो पोस्ट बनाउनुहोस्'),
                  style: const TextStyle(
                      decoration: TextDecoration.none),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
