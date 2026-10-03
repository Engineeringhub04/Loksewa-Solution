// Discussion detail screen (/discussion/:id).
//
// BEHAVIOR mirrors app/discussion/[id].tsx exactly:
// - post + comments one-shot fetch (orderBy createdAt asc), NO listeners
// - header = shared DiscussionPostCard (full date-time, live comment count,
//   no-op onTap); image → global viewer
// - comments ascending; per-comment/reply like states (60s cache)
// - lazy replies, ONE open thread at a time; inline reply composer
// - bottom composer (signed-in only), send spinner, disabled when empty
// - pull-to-refresh (post + comments); offline queue with "Queued" chip +
//   auto-flush on reconnect
// - menus: post → edit/delete (owner/admin) else report; comment/reply →
//   delete (owner/admin) else report (reply reports use type 'comment')
// - NO comment editing; editedAt never displayed
// - deleted post → "This post has been deleted" state
//
// DESIGN is premium-modern (unique to Flutter): gradient band behind the
// floating post card, floating comment cards with soft shadows, staggered
// entrances, gradient reply rail, focus-elevating composer, 0.92 send
// micro-interaction. All animations finite.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/discussion/discussion_action_menu.dart';
import '../../widgets/discussion/discussion_comment_card.dart';
import '../../widgets/discussion/discussion_confirm_dialog.dart';
import '../../widgets/discussion/discussion_heart_like.dart';
import '../../widgets/discussion/discussion_post_card.dart';
import '../../widgets/discussion/discussion_report_dialog.dart';
import '../../widgets/discussion/discussion_signin_prompt.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import '../learn/discussion_tab.dart';

class DiscussionDetailScreen extends StatefulWidget {
  final String id;

  const DiscussionDetailScreen({super.key, required this.id});

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _PendingItem {
  final String body;
  final String? replyToId;
  final String? replyToName;
  final DateTime queuedAt;

  _PendingItem(
      {required this.body,
      this.replyToId,
      this.replyToName,
      DateTime? queuedAt})
      : queuedAt = queuedAt ?? DateTime.now();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  // Theme-aware (was hardcoded light): the header's theme toggle now
  // visibly switches this page between light and dark.
  Color _bg(BuildContext context) => ExpoPalette.of(context).background;
  Color _navy(BuildContext context) => ExpoPalette.of(context).textPrimary;
  static const _grey = Color(0xFF64748B);
  Color _border(BuildContext context) => ExpoPalette.of(context).border;

  DiscussionPost? _post;
  List<DiscussionComment> _comments = [];
  bool _loading = true;
  Object? _error;

  bool _postLiked = false;
  final Map<String, bool> _commentLiked = {};
  final Map<String, bool> _replyLiked = {};

  final Map<String, List<DiscussionReply>> _replies = {};
  final Set<String> _repliesLoading = {};
  String? _openReplyId;

  final List<_PendingItem> _pending = [];
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  bool _composerFocused = false;
  final Map<String, TextEditingController> _replyControllers = {};
  final Set<String> _replySending = {};
  bool _sending = false;

  bool get _signedIn => AuthService.currentUser != null;
  bool get _isAdmin => ProfileStore.instance.profile?.isAdmin ?? false;

  /// Maps a write failure to an actionable message: 403/PERMISSION_DENIED
  /// almost always means the Firebase console rules are older than the app's
  /// firebase.rules (the user pastes them manually).
  String _writeErrorMessage(Object e) {
    final s = e.toString();
    if (s.contains('403') || s.contains('PERMISSION_DENIED')) {
      return AppLanguage.tr(
        'Not allowed — please update Firebase rules from GitHub.',
        'अनुमति छैन — GitHub बाट Firebase rules अपडेट गर्नुहोस्।',
      );
    }
    return AppLanguage.tr('Something went wrong', 'केही समस्या भयो');
  }
  String get _uid => AuthService.currentUser?.uid ?? '';

  int get _liveCommentCount => _comments.length + _pending.length;

  @override
  void initState() {
    super.initState();
    _composerFocus.addListener(() {
      if (mounted) setState(() => _composerFocused = _composerFocus.hasFocus);
    });
    _composer.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none) &&
          _pending.isNotEmpty) {
        _flushPending();
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _composer.dispose();
    _composerFocus.dispose();
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> _togglePin(DiscussionPost post) async {
    final ok = await confirmDiscussionAction(
      context: context,
      title: post.isPinned
          ? AppLanguage.tr('Unpin this post?', 'यो पोस्ट अनपिन गर्ने?')
          : AppLanguage.tr('Pin this post?', 'यो पोस्ट पिन गर्ने?'),
      message: post.isPinned
          ? AppLanguage.tr('It will return to its normal position.',
              'यो सामान्य स्थानमा फर्कनेछ।')
          : AppLanguage.tr('It will stay at the top of the feed.',
              'यो फिडको सबैभन्दा माथि रहनेछ।'),
      confirmLabel: post.isPinned
          ? AppLanguage.tr('Unpin', 'अनपिन गर्नुहोस्')
          : AppLanguage.tr('Pin', 'पिन गर्नुहोस्'),
    );
    if (ok != true || !mounted) return;
    try {
      await DiscussionService.togglePinDiscussion(post.id, !post.isPinned);
      if (!mounted) return;
      setState(() => _post = post.copyWith(isPinned: !post.isPinned));
      DiscussionTab.requestRefresh();
      showToast(
          context,
          post.isPinned
              ? AppLanguage.tr('Post unpinned', 'पोस्ट अनपिन भयो')
              : AppLanguage.tr('Post pinned', 'पोस्ट पिन भयो'),
          ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      // Clear replies cache — fresh data on page refresh.
      _replies.clear();
      _repliesLoading.clear();
      _openReplyId = null;
    });
    try {
      final post = await DiscussionService.fetchDiscussion(widget.id);
      if (post == null) throw const _NotFoundException();
      final comments = await DiscussionService.fetchComments(widget.id);
      var postLiked = false;
      final commentLiked = <String, bool>{};
      if (_signedIn) {
        postLiked = await DiscussionService.isDiscussionLiked(widget.id);
        final results = await Future.wait(comments.map(
            (c) => DiscussionService.isCommentLiked(widget.id, c.id)));
        for (var i = 0; i < comments.length; i++) {
          commentLiked[comments[i].id] = results[i];
        }
      }
      if (!mounted) return;
      setState(() {
        _post = post;
        _comments = comments;
        _postLiked = postLiked;
        _commentLiked
          ..clear()
          ..addAll(commentLiked);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refreshComments() async {
    try {
      final comments = await DiscussionService.fetchComments(widget.id);
      if (!mounted) return;
      setState(() => _comments = comments);
    } catch (_) {
      // Keep the visible list on transient failures.
    }
  }

  // ---------- Likes ----------

  void _requireSignIn() {
    DiscussionSignInPrompt.show(context);
    throw const AuthRequiredException();
  }

  Future<void> _togglePostLike(bool liked) async {
    if (!_signedIn) _requireSignIn();
    try {
      await DiscussionService.toggleLikeDiscussion(widget.id, liked);
      _postLiked = liked;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> _toggleCommentLike(
      DiscussionComment c, bool liked, String? replyId) async {
    if (!_signedIn) _requireSignIn();
    try {
      await DiscussionService.toggleCommentLike(widget.id, c.id, liked, replyId);
      if (replyId == null) {
        _commentLiked[c.id] = liked;
      } else {
        _replyLiked['${c.id}__$replyId'] = liked;
      }
    } catch (_) {
      rethrow;
    }
  }

  // ---------- Replies (lazy, one open thread at a time) ----------

  Future<void> _loadReplies(DiscussionComment c) async {
    setState(() => _repliesLoading.add(c.id));
    try {
      final replies = await DiscussionService.fetchReplies(widget.id, c.id);
      final liked = <String, bool>{};
      if (_signedIn && replies.isNotEmpty) {
        final results = await Future.wait(replies.map(
            (r) => DiscussionService.isCommentLiked(widget.id, c.id, r.id)));
        for (var i = 0; i < replies.length; i++) {
          liked['${c.id}__${replies[i].id}'] = results[i];
        }
      }
      if (!mounted) return;
      setState(() {
        _replies[c.id] = replies;
        _replyLiked.addAll(liked);
        _repliesLoading.remove(c.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _repliesLoading.remove(c.id));
      showToast(
          context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    }
  }

  /// "View replies" — toggles the single open thread.
  /// Replies are cached: preloading + fetch happen ONLY the first time.
  /// Hide → View again shows cached data instantly (no preloading).
  /// Page refresh clears the cache for fresh data.
  void _toggleReplyThread(DiscussionComment c) {
    if (_openReplyId == c.id) {
      setState(() => _openReplyId = null);
      return;
    }
    setState(() => _openReplyId = c.id);
    // Only fetch if not already cached.
    if (!_replies.containsKey(c.id)) {
      _loadReplies(c);
    }
  }

  /// "Reply" — always opens the thread; fetches only if not cached.
  void _startReply(DiscussionComment c) {
    if (!_signedIn) {
      DiscussionSignInPrompt.show(context);
      return;
    }
    setState(() => _openReplyId = c.id);
    if (!_replies.containsKey(c.id)) {
      _loadReplies(c);
    }
  }

  String _authorName() {
    final profile = ProfileStore.instance.profile;
    final name = (profile?.name ?? '').trim();
    return name.isEmpty ? 'Anonymous' : name;
  }

  /// Comment/reply author photo with the signed-in fallback (Expo parity):
  /// stored photo ?? (own item ? profile photo ?? auth photo : null).
  String? _authorPhotoOf(DiscussionComment c) {
    if ((c.authorPhoto ?? '').isNotEmpty) return c.authorPhoto;
    if (_uid.isNotEmpty && c.authorId == _uid) {
      return ProfileStore.instance.profile?.photoURL ??
          AuthService.currentUser?.photoURL;
    }
    return null;
  }

  // ---------- Composers ----------

  Future<void> _submit() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_signedIn) {
      DiscussionSignInPrompt.show(context);
      return;
    }
    final profile = ProfileStore.instance.profile;

    if (!await _isOnline()) {
      setState(() {
        _pending.add(_PendingItem(body: text));
        _composer.clear();
      });
      return;
    }

    setState(() => _sending = true);
    try {
      await DiscussionService.addComment(
        widget.id,
        body: text,
        authorName: _authorName(),
        authorPhoto: profile?.photoURL,
        authorId: _uid,
      );
      await _refreshComments();
      if (!mounted) return;
      setState(() {
        _composer.clear();
        _sending = false;
      });
      showToast(
          context,
          AppLanguage.tr('Comment posted', 'कमेन्ट पोस्ट भयो'),
          ToastVariant.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast(context, _writeErrorMessage(e), ToastVariant.error);
    }
  }

  Future<void> _submitReply(DiscussionComment c) async {
    final controller = _replyControllers[c.id];
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty || _replySending.contains(c.id)) return;
    if (!_signedIn) {
      DiscussionSignInPrompt.show(context);
      return;
    }
    final profile = ProfileStore.instance.profile;

    if (!await _isOnline()) {
      setState(() {
        _pending.add(_PendingItem(
            body: text, replyToId: c.id, replyToName: c.authorName));
        controller?.clear();
      });
      return;
    }

    setState(() => _replySending.add(c.id));
    try {
      await DiscussionService.addReply(
        widget.id,
        c.id,
        body: text,
        authorName: _authorName(),
        authorPhoto: profile?.photoURL,
        authorId: _uid,
      );
      final replies = await DiscussionService.fetchReplies(widget.id, c.id);
      if (!mounted) return;
      setState(() {
        _replies[c.id] = replies;
        controller?.clear();
        _replySending.remove(c.id);
      });
      showToast(
          context,
          AppLanguage.tr('Reply posted', 'रिप्लाइ पोस्ट भयो'),
          ToastVariant.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _replySending.remove(c.id));
      showToast(context, _writeErrorMessage(e), ToastVariant.error);
    }
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty || _sending) return;
    final profile = ProfileStore.instance.profile;
    final authorName = (profile?.name ?? '').trim().isEmpty
        ? 'Anonymous'
        : profile!.name.trim();
    final items = List<_PendingItem>.from(_pending);
    for (final item in items) {
      try {
        if (item.replyToId != null) {
          await DiscussionService.addReply(
            widget.id,
            item.replyToId!,
            body: item.body,
            authorName: authorName,
            authorPhoto: profile?.photoURL,
            authorId: _uid,
          );
        } else {
          await DiscussionService.addComment(
            widget.id,
            body: item.body,
            authorName: authorName,
            authorPhoto: profile?.photoURL,
            authorId: _uid,
          );
        }
        _pending.remove(item);
      } catch (_) {
        break; // stop on first failure; retry on next trigger
      }
    }
    if (!mounted) return;
    setState(() {});
    await _refreshComments();
  }

  // ---------- Menus ----------

  bool _canModerate(String? authorId) =>
      _isAdmin || (_uid.isNotEmpty && _uid == authorId);

  void _postMenu(Offset anchor) {
    final post = _post;
    if (post == null) return;
    final items = <DiscussionMenuItem>[
      if (_isAdmin)
        DiscussionMenuItem(
          label: post.isPinned
              ? AppLanguage.tr('Unpin', 'अनपिन गर्नुहोस्')
              : AppLanguage.tr('Pin', 'पिन गर्नुहोस्'),
          onSelect: () => _togglePin(post),
        ),
      if (_canModerate(post.authorId))
        DiscussionMenuItem(
          label: AppLanguage.tr('Edit', 'सम्पादन गर्नुहोस्'),
          onSelect: () =>
              context.push('/discussion/create?editId=${post.id}').then((_) {
            if (mounted) _load();
          }),
        ),
      if (_canModerate(post.authorId))
        DiscussionMenuItem(
          label: AppLanguage.tr('Delete', 'मेट्नुहोस्'),
          danger: true,
          onSelect: () async {
            final ok = await confirmDiscussionDelete(
              context: context,
              title: AppLanguage.tr('Delete this post?', 'यो पोस्ट मेट्ने हो?'),
              message: AppLanguage.tr('This action cannot be undone.',
                  'यो काम फर्काउन मिल्दैन।'),
              onConfirm: () => DiscussionService.deleteDiscussion(post.id),
            );
            if (ok && mounted) {
              DiscussionTab.requestRefresh();
              context.pop();
            }
          },
        ),
      if (!_canModerate(post.authorId))
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
                  AppLanguage.tr('Post reported', 'पोस्ट रिपोर्ट गरियो'),
                  ToastVariant.success);
            }
          }),
        ),
    ];
    if (items.isEmpty) return;
    DiscussionActionMenu.show(
        context: context, anchorTopRight: anchor, items: items);
  }

  void _commentMenu(DiscussionComment c, String? replyId, Offset anchor) {
    final items = <DiscussionMenuItem>[
      if (_canModerate(c.authorId))
        DiscussionMenuItem(
          label: AppLanguage.tr('Delete', 'मेट्नुहोस्'),
          danger: true,
          onSelect: () async {
            final ok = await confirmDiscussionDelete(
              context: context,
              title: replyId == null
                  ? AppLanguage.tr(
                      'Delete this comment?', 'यो कमेन्ट मेट्ने हो?')
                  : AppLanguage.tr(
                      'Delete this reply?', 'यो रिप्लाइ मेट्ने हो?'),
              message: AppLanguage.tr('This action cannot be undone.',
                  'यो काम फर्काउन मिल्दैन।'),
              onConfirm: () => replyId == null
                  ? DiscussionService.deleteComment(widget.id, c.id)
                  : DiscussionService.deleteReply(widget.id, c.id, replyId),
            );
            if (ok && mounted) {
              if (replyId == null) {
                await _refreshComments();
              } else {
                final replies =
                    await DiscussionService.fetchReplies(widget.id, c.id);
                if (mounted) setState(() => _replies[c.id] = replies);
              }
            }
          },
        ),
      if (!_canModerate(c.authorId))
        DiscussionMenuItem(
          label: AppLanguage.tr('Report comment', 'कमेन्ट रिपोर्ट गर्नुहोस्'),
          onSelect: () => DiscussionReportDialog.show(
            context: context,
            // Reply reports reuse the comment path/type (Expo parity).
            targetType: 'comment',
            targetId: replyId ?? c.id,
            targetTitle: c.body.length > 60
                ? '${c.body.substring(0, 60)}…'
                : c.body,
          ).then((ok) {
            if (ok == true && mounted) {
              showToast(
                  context,
                  AppLanguage.tr('Post reported', 'पोस्ट रिपोर्ट गरियो'),
                  ToastVariant.success);
            }
          }),
        ),
    ];
    if (items.isEmpty) return;
    DiscussionActionMenu.show(
        context: context, anchorTopRight: anchor, items: items);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg(context),
      body: Column(
        children: [
          SubpageHeader(
            title: AppLanguage.tr('Comments', 'कमेन्टहरू'),
            showBack: true,
          ),
          Expanded(child: _buildBody()),
          if (_signedIn && _post != null && _error == null) _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
          child: PreloadingWidget(tinted: false,
              label: AppLanguage.tr(
                  'Loading comments...', 'कमेन्टहरू लोड हुँदैछन्...')));
    }
    if (_error != null || _post == null) {
      final notFound = _error is _NotFoundException;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _border(context)),
                  boxShadow: [
                    BoxShadow(
                      color: _navy(context).withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.forum_outlined,
                    size: 34, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              Text(
                notFound
                    ? AppLanguage.tr('This post has been deleted',
                        'यो पोस्ट मेटाइएको छ')
                    : AppLanguage.tr(
                        'Something went wrong', 'केही समस्या भयो'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _navy(context),
                    decoration: TextDecoration.none),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppLanguage.tr('Retry', 'पुन: प्रयास'),
                    style:
                        const TextStyle(decoration: TextDecoration.none)),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _flushPending();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _buildPostHeader(),
          _buildCommentsHeading(),
          ..._pending.map(_buildPendingCard),
          ..._comments.asMap().entries.map(
              (e) => _buildThread(e.value, e.key)),
          if (_comments.isEmpty && _pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 40,
                      color: _grey.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    AppLanguage.tr(
                        'No comments yet.', 'अहिलेसम्म कुनै कमेन्ट छैन।'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14,
                        color: _grey,
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Post card header — React parity: the shared post card sits directly on
  /// the page background (no extra gradient band; the SubpageHeader above
  /// is the only header).
  Widget _buildPostHeader() {
    final post = _post!;
    final imageUrl = (post.imageUrl ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DiscussionPostCard(
        post: post.copyWith(commentCount: _liveCommentCount),
        liked: _postLiked,
        onToggleLike: _togglePostLike,
        onTap: () {}, // no-op on detail (Expo parity)
        onMenu: _postMenu,
        timestampOverride:
            formatDiscussionDetailDateTime(post.createdAt),
        onImageTap: imageUrl.isNotEmpty
            ? () => showImageViewer(context, NetworkImage(imageUrl))
            : null,
      ),
    );
  }

  /// React parity: plain "Comments" heading (bodyLarge bold, top margin 24).
  /// No accent bar, no count pill.
  Widget _buildCommentsHeading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(
        AppLanguage.tr('Comments', 'कमेन्टहरू'),
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _navy(context),
            decoration: TextDecoration.none),
      ),
    );
  }

  Widget _buildPendingCard(_PendingItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Opacity(
        opacity: 0.75,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFB45309).withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: _navy(context).withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    item.replyToId != null
                        ? '${AppLanguage.tr('Reply to', 'लाई जवाफ')} ${item.replyToName ?? ''}'
                        : AppLanguage.tr('Comment', 'कमेन्ट'),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _grey,
                        decoration: TextDecoration.none),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      AppLanguage.tr('Queued', 'पर्खाइमा'),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB45309),
                          decoration: TextDecoration.none),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.body,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                    decoration: TextDecoration.none),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One comment thread: floating card + View replies/Reply buttons +
  /// gradient-railed replies + inline composer. Staggered entrance.
  /// React parity: plain comment row with a hairline bottom divider —
  /// no floating card, no entrance animation.
  Widget _buildThread(DiscussionComment c, int index) {
    final open = _openReplyId == c.id;
    final replies = _replies[c.id] ?? const <DiscussionReply>[];
    final loadingReplies = _repliesLoading.contains(c.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: _border(context), width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
              DiscussionCommentCard(
                comment: DiscussionComment(
                  id: c.id,
                  body: c.body,
                  authorName: c.authorName,
                  authorPhoto: _authorPhotoOf(c),
                  authorId: c.authorId,
                  likeCount: c.likeCount,
                  createdAt: c.createdAt,
                  editedAt: c.editedAt,
                ),
                isReply: false,
                liked: _commentLiked[c.id] ?? false,
                onToggleLike: (liked) =>
                    _toggleCommentLike(c, liked, null),
                onMenu: (anchor) => _commentMenu(c, null, anchor),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 8, bottom: 8),
                child: Row(
                  children: [
                    _TextButton(
                      label: open
                          ? AppLanguage.tr(
                              'Hide replies', 'रिप्लाइ लुकाउनुहोस्')
                          : AppLanguage.tr(
                              'View replies', 'रिप्लाइ हेर्नुहोस्'),
                      active: open,
                      onTap: () => _toggleReplyThread(c),
                    ),
                    const SizedBox(width: 8),
                    _TextButton(
                      label: AppLanguage.tr('Reply', 'रिप्लाइ'),
                      onTap: () => _startReply(c),
                    ),
                  ],
                ),
              ),
              if (open) ...[
                const SizedBox(height: 4),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // React parity: plain 2px left border (no gradient rail).
                      Container(
                        width: 2,
                        margin:
                            const EdgeInsets.only(left: 24, right: 8),
                        color: _border(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (loadingReplies)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: PreloadingWidget(
                                  tinted: false,
                                  label: AppLanguage.tr(
                                      'Loading replies...',
                                      'रिप्लाइहरू लोड हुँदैछन्...'),
                                ),
                              ),
                            for (final r in replies)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: DiscussionCommentCard(
                                  comment: DiscussionComment(
                                    id: r.id,
                                    body: r.body,
                                    authorName: r.authorName,
                                    authorPhoto: _authorPhotoOf(r),
                                    authorId: r.authorId,
                                    likeCount: r.likeCount,
                                    createdAt: r.createdAt,
                                    editedAt: r.editedAt,
                                  ),
                                  isReply: false,
                                  liked:
                                      _replyLiked['${c.id}__${r.id}'] ??
                                          false,
                                  onToggleLike: (liked) =>
                                      _toggleCommentLike(
                                          c, liked, r.id),
                                  onMenu: (anchor) =>
                                      _commentMenu(c, r.id, anchor),
                                ),
                              ),
                            if (_signedIn)
                              _buildInlineReplyComposer(c),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
  }

  Widget _buildInlineReplyComposer(DiscussionComment c) {
    final primary = Theme.of(context).colorScheme.primary;
    final controller =
        _replyControllers.putIfAbsent(c.id, () => TextEditingController());
    final sending = _replySending.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitReply(c),
              decoration: InputDecoration(
                hintText: AppLanguage.tr(
                    'Write a reply...', 'रिप्लाइ लेख्नुहोस्...'),
                hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    decoration: TextDecoration.none),
                filled: true,
                fillColor: ExpoPalette.of(context).surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                  fontSize: 13, decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(
            size: 40,
            radius: 13,
            loading: sending,
            onTap: () => _submitReply(c),
          ),
        ],
      ),
    );
  }

  /// Bottom composer — focus elevation + 0.92 send micro-interaction.
  Widget _buildComposer() {
    final primary = Theme.of(context).colorScheme.primary;
    final palette = ExpoPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: _border(context))),
        boxShadow: _composerFocused
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ]
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _composerFocused
                        ? palette.surface
                        : palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _composerFocused ? primary : Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: _composerFocused
                        ? [
                            BoxShadow(
                              color:
                                  primary.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: TextField(
                    controller: _composer,
                    focusNode: _composerFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: AppLanguage.tr(
                          'Write a comment...', 'कमेन्ट लेख्नुहोस्...'),
                      hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          decoration: TextDecoration.none),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                    ),
                    style: const TextStyle(
                        fontSize: 14,
                        decoration: TextDecoration.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(
                size: 46,
                radius: 15,
                loading: _sending,
                disabled:
                    _sending || _composer.text.trim().isEmpty,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary text button (View replies / Reply) — pill highlight when active.
class _TextButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TextButton(
      {required this.label, this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              active ? primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primary,
              decoration: TextDecoration.none),
        ),
      ),
    );
  }
}

/// Send button with a finite 0.92 press micro-interaction + loading state.
class _SendButton extends StatefulWidget {
  final double size;
  final double radius;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _SendButton({
    required this.size,
    required this.radius,
    required this.onTap,
    this.loading = false,
    this.disabled = false,
  });

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dimmed = widget.disabled || widget.loading;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: dimmed ? null : widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: dimmed ? 0.45 : 1.0),
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: dimmed
                ? null
                : [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded,
                  size: 19, color: Colors.white),
        ),
      ),
    );
  }
}

class _NotFoundException implements Exception {
  const _NotFoundException();
}
