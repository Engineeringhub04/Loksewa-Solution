// Discussion feed tab (bottom-nav "Discussion").
// Mirrors app/(tabs)/discussion.tsx:
// - latest 30 posts, orderBy createdAt desc, one-shot get (no listeners)
// - like state preloaded per post (60s-cached reaction reads)
// - client-side search across title/body/category/author/course/subcourse
// - pull-to-refresh + refetch on tab refocus
// - signed-out users browse only (no FAB, like taps → sign-in prompt)
// - guidelines auto-popup on first visit per app start
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/discussion/discussion_signin_prompt.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/discussion/discussion_action_menu.dart';
import '../../widgets/discussion/discussion_confirm_dialog.dart';
import '../../widgets/discussion/discussion_guidelines_dialog.dart';
import '../../widgets/discussion/discussion_post_card.dart';
import '../../widgets/discussion/discussion_report_dialog.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
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
  static bool _guidelinesShownThisStart = false;

  List<DiscussionPost> _posts = [];
  final Map<String, bool> _liked = {};
  bool _loading = true;
  Object? _error;
  bool _offline = false;
  String _query = '';
  bool _wasActive = false;

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
  }

  @override
  void dispose() {
    TabsScreen.tabIndex.removeListener(_onTabIndexChanged);
    DiscussionTab.refreshSignal.removeListener(_onRefreshSignal);
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
      final likes = <String, bool>{};
      if (_signedIn && posts.isNotEmpty) {
        final results = await Future.wait(
            posts.map((p) => DiscussionService.isDiscussionLiked(p.id)));
        for (var i = 0; i < posts.length; i++) {
          likes[posts[i].id] = results[i];
        }
      }
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _liked
          ..clear()
          ..addAll(likes);
        _error = null;
        _offline = false;
        _loading = false;
      });
      _maybeShowGuidelines();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _offline = e is _OfflineException;
        _loading = false;
      });
    }
  }

  Future<void> _maybeShowGuidelines() async {
    if (_guidelinesShownThisStart || !mounted) return;
    _guidelinesShownThisStart = true;
    try {
      final g = await DiscussionService.fetchDiscussionGuidelines();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            SubpageHeader(
              title: AppLanguage.tr('Discussion', 'छलफल'),
              showBack: false,
            ),
            _SearchBar(
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: _signedIn
          ? FloatingActionButton(
              onPressed: () => context.push('/discussion/create'),
              tooltip: AppLanguage.tr('New discussion', 'नयाँ छलफल'),
              child: const Icon(Icons.add),
            )
          : null,
    );
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
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: posts.length,
        itemBuilder: (context, i) {
          final post = posts[i];
          return SyllabusEntrance(
            delayMs: (i * 40).clamp(0, 400),
            child: DiscussionPostCard(
              post: post,
              liked: _liked[post.id] ?? false,
              onToggleLike: (liked) => _onToggleLike(post, liked),
              onTap: () => context.push('/discussion/${post.id}'),
              onMenu: (anchor) => _onMenu(post, anchor),
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

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: AppLanguage.tr(
              'Search discussions...', 'छलफल खोज्नुहोस्...'),
          hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              decoration: TextDecoration.none),
          prefixIcon: const Icon(Icons.search,
              size: 20, color: Color(0xFF94A3B8)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        style: const TextStyle(
            fontSize: 14, decoration: TextDecoration.none),
      ),
    );
  }
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
              color: const Color(0xFF94A3B8),
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
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
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
            const Icon(Icons.forum_outlined,
                size: 44, color: Color(0xFF94A3B8)),
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

          ],
        ),
      ),
    );
  }
}
