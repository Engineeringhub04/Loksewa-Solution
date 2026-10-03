// Discussion detail screen (/discussion/:id).
// Mirrors app/discussion/[id].tsx:
// - header card: title, admin accent, meta (author/course/date), image with
//   global viewer, tappable body links, heart like + live comment count +
//   share + overflow menu
// - comments ascending, like states per comment, replies lazy + expandable
// - bottom composer (signed-in only); offline comments silently queued
// - NO comment editing anywhere; editedAt is written but never displayed
// - commentCount shown = live comments length (not the doc counter)
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/discussion/discussion_action_menu.dart';
import '../../widgets/discussion/discussion_avatar.dart';
import '../../widgets/discussion/discussion_comment_card.dart';
import '../../widgets/discussion/discussion_confirm_dialog.dart';
import '../../widgets/discussion/discussion_heart_like.dart';
import '../../widgets/discussion/discussion_link_text.dart';
import '../../widgets/discussion/discussion_report_dialog.dart';
import '../../widgets/discussion/discussion_signin_prompt.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

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
  DiscussionPost? _post;
  List<DiscussionComment> _comments = [];
  bool _loading = true;
  Object? _error;

  bool _postLiked = false;
  final Map<String, bool> _commentLiked = {};
  final Map<String, bool> _replyLiked = {};

  final Map<String, List<DiscussionReply>> _replies = {};
  final Set<String> _repliesLoading = {};
  final Set<String> _expanded = {};

  final List<_PendingItem> _pending = [];
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final Map<String, TextEditingController> _replyControllers = {};
  final Set<String> _replySending = {};
  bool _sending = false;

  bool get _signedIn => AuthService.currentUser != null;
  bool get _isAdmin => ProfileStore.instance.profile?.isAdmin ?? false;
  String get _uid => AuthService.currentUser?.uid ?? '';

  int get _liveCommentCount => _comments.length + _pending.length;

  @override
  void initState() {
    super.initState();
    _load();
    _connSub =
        Connectivity().onConnectivityChanged.listen((results) {
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await DiscussionService.fetchDiscussion(widget.id);
      if (post == null) throw const _NotFoundException();
      final comments =
          await DiscussionService.fetchComments(widget.id);
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
      final comments =
          await DiscussionService.fetchComments(widget.id);
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
      await DiscussionService.toggleCommentLike(
          widget.id, c.id, liked, replyId);
      if (replyId == null) {
        _commentLiked[c.id] = liked;
      } else {
        _replyLiked['${c.id}__$replyId'] = liked;
      }
    } catch (_) {
      rethrow;
    }
  }

  // ---------- Replies ----------

  Future<void> _toggleReplies(DiscussionComment c) async {
    if (_expanded.contains(c.id)) {
      setState(() => _expanded.remove(c.id));
      return;
    }
    setState(() {
      _expanded.add(c.id);
      _repliesLoading.add(c.id);
    });
    try {
      final replies =
          await DiscussionService.fetchReplies(widget.id, c.id);
      final liked = <String, bool>{};
      if (_signedIn && replies.isNotEmpty) {
        final results = await Future.wait(replies.map((r) =>
            DiscussionService.isCommentLiked(widget.id, c.id, r.id)));
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
      setState(() {
        _expanded.remove(c.id);
        _repliesLoading.remove(c.id);
      });
      showToast(
          context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    }
  }

  // ---------- Composer ----------

  void _startReply(DiscussionComment c) {
    if (!_signedIn) {
      DiscussionSignInPrompt.show(context);
      return;
    }
    if (!_expanded.contains(c.id)) {
      _toggleReplies(c);
    }
  }

  String _authorName() {
    final profile = ProfileStore.instance.profile;
    final name = (profile?.name ?? '').trim();
    return name.isEmpty ? 'Anonymous' : name;
  }

  /// Bottom composer: top-level comments only (Expo parity).
  Future<void> _submit() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_signedIn) {
      DiscussionSignInPrompt.show(context);
      return;
    }
    final profile = ProfileStore.instance.profile;

    if (!await _isOnline()) {
      // Silently queued — flushed when connectivity returns.
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast(
          context,
          AppLanguage.tr(
              'Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    }
  }

  /// Inline per-thread reply composer (Expo parity).
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
      await _toggleRepliesRefresh(c);
      if (!mounted) return;
      setState(() {
        controller?.clear();
        _replySending.remove(c.id);
      });
      showToast(
          context,
          AppLanguage.tr('Reply posted', 'रिप्लाइ पोस्ट भयो'),
          ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _replySending.remove(c.id));
      showToast(
          context,
          AppLanguage.tr(
              'Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    }
  }

  Future<void> _toggleRepliesRefresh(DiscussionComment c) async {
    try {
      final replies =
          await DiscussionService.fetchReplies(widget.id, c.id);
      if (!mounted) return;
      setState(() => _replies[c.id] = replies);
    } catch (_) {}
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
      if (_canModerate(post.authorId))
        DiscussionMenuItem(
          label: AppLanguage.tr('Edit', 'सम्पादन गर्नुहोस्'),
          onSelect: () => context
              .push('/discussion/create?editId=${post.id}')
              .then((_) => _load()),
        ),
      if (_canModerate(post.authorId))
        DiscussionMenuItem(
          label: AppLanguage.tr('Delete', 'मेट्नुहोस्'),
          danger: true,
          onSelect: () async {
            final ok = await confirmDiscussionDelete(
              context: context,
              title: AppLanguage.tr(
                  'Delete this post?', 'यो पोस्ट मेट्ने हो?'),
              message: AppLanguage.tr('This action cannot be undone.',
                  'यो काम फर्काउन मिल्दैन।'),
              onConfirm: () =>
                  DiscussionService.deleteDiscussion(post.id),
            );
            if (ok && mounted) context.pop();
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
                  : DiscussionService.deleteReply(
                      widget.id, c.id, replyId),
            );
            if (ok) {
              if (replyId == null) {
                await _refreshComments();
              } else {
                await _toggleRepliesRefresh(c);
              }
            }
          },
        ),
      if (!_canModerate(c.authorId))
        DiscussionMenuItem(
          label:
              AppLanguage.tr('Report comment', 'कमेन्ट रिपोर्ट गर्नुहोस्'),
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

  void _share() {
    final post = _post;
    if (post == null) return;
    Share.share(
      '${post.title}\nhttps://www.kbr.com.np/discussion/${post.id}',
      subject: 'Loksewa Solution',
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            SubpageHeader(
              title: AppLanguage.tr('Discussion', 'छलफल'),
              showBack: true,
            ),
            Expanded(child: _buildBody()),
            if (_signedIn && _post != null) _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: PreloadingWidget(label: AppLanguage.tr('Loading comments...', 'कमेन्टहरू लोड हुँदैछन्...')));
    }
    if (_error != null || _post == null) {
      final notFound = _error is _NotFoundException;
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
                notFound
                    ? AppLanguage.tr('This post has been deleted',
                        'यो पोस्ट मेटाइएको छ')
                    : AppLanguage.tr(
                        'Something went wrong', 'केही समस्या भयो'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _load,
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16),
          _buildCommentsHeader(),
          const SizedBox(height: 8),
          ..._pending.map(_buildPendingCard),
          ..._comments.map(_buildCommentThread),
          if (_comments.isEmpty && _pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  AppLanguage.tr('No comments yet.',
                      'अहिलेसम्म कुनै कमेन्ट छैन।'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.none),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final post = _post!;
    final primary = Theme.of(context).colorScheme.primary;
    const grey = Color(0xFF64748B);
    final courseLabel = [
      if ((post.courseName ?? '').isNotEmpty) post.courseName!,
      if ((post.subcourseName ?? '').isNotEmpty) post.subcourseName!,
    ].join(' • ');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (post.isAdmin)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16)),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DiscussionAvatar(
                            photoUrl: post.authorPhoto,
                            name: post.authorName,
                            radius: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.authorName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: post.isAdmin
                                      ? primary
                                      : const Color(0xFF0F172A),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              Text(
                                formatDiscussionDetailDateTime(
                                    post.createdAt),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: grey,
                                    decoration: TextDecoration.none),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (courseLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        courseLabel,
                        style: const TextStyle(
                            fontSize: 11,
                            color: grey,
                            decoration: TextDecoration.none),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      post.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: post.isAdmin
                            ? primary
                            : const Color(0xFF0F172A),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (post.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DiscussionLinkText(
                        text: post.body,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF334155),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                    if ((post.imageUrl ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => showImageViewer(
                            context, NetworkImage(post.imageUrl!.trim())),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            post.imageUrl!.trim(),
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        DiscussionHeartLike(
                          initialLiked: _postLiked,
                          likeCount: post.likeCount,
                          onToggle: _togglePostLike,
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.chat_bubble_outline,
                            size: 18, color: grey),
                        const SizedBox(width: 4),
                        Text(
                          '$_liveCommentCount',
                          style: const TextStyle(
                              fontSize: 13,
                              color: grey,
                              decoration: TextDecoration.none),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.share_outlined,
                              size: 20, color: grey),
                          tooltip: AppLanguage.tr('Share', 'सेयर'),
                          onPressed: _share,
                        ),
                        Builder(
                          builder: (menuCtx) => IconButton(
                            icon: const Icon(Icons.more_vert,
                                size: 20, color: grey),
                            onPressed: () {
                              final box = menuCtx.findRenderObject()
                                  as RenderBox;
                              final pos = box.localToGlobal(
                                  Offset(box.size.width, box.size.height));
                              _postMenu(pos);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsHeader() {
    return Text(
      '${AppLanguage.tr('Comments', 'कमेन्टहरू')} ($_liveCommentCount)',
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
          decoration: TextDecoration.none),
    );
  }

  Widget _buildPendingCard(_PendingItem item) {
    return Opacity(
      opacity: 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.none),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AppLanguage.tr('Queued', 'पर्खाइमा'),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildCommentThread(DiscussionComment c) {
    final expanded = _expanded.contains(c.id);
    final replies = _replies[c.id] ?? const <DiscussionReply>[];
    final loading = _repliesLoading.contains(c.id);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiscussionCommentCard(
            comment: c,
            isReply: false,
            liked: _commentLiked[c.id] ?? false,
            onToggleLike: (liked) => _toggleCommentLike(c, liked, null),
            onMenu: (anchor) => _commentMenu(c, null, anchor),
          ),
          // Replies toggle + Reply button (rendered by the screen, Expo parity).
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggleReplies(c),
                  child: Text(
                    expanded
                        ? AppLanguage.tr(
                            'Hide replies', 'रिप्लाइ लुकाउनुहोस्')
                        : AppLanguage.tr(
                            'View replies', 'रिप्लाइ हेर्नुहोस्'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary,
                        decoration: TextDecoration.none),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _startReply(c),
                  child: Text(
                    AppLanguage.tr('Reply', 'रिप्लाइ'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary,
                        decoration: TextDecoration.none),
                  ),
                ),
              ],
            ),
          ),
          if (expanded)
            Container(
              margin: const EdgeInsets.only(left: 24, top: 8),
              padding: const EdgeInsets.only(left: 10),
              decoration: const BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: Color(0xFFE2E8F0), width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      ),
                    ),
                  for (final r in replies)
                    DiscussionCommentCard(
                      comment: r,
                      isReply: true,
                      liked:
                          _replyLiked['${c.id}__${r.id}'] ?? false,
                      onToggleLike: (liked) =>
                          _toggleCommentLike(c, liked, r.id),
                      onMenu: (anchor) =>
                          _commentMenu(c, r.id, anchor),
                    ),
                  if (_signedIn) _buildInlineReplyComposer(c),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineReplyComposer(DiscussionComment c) {
    final primary = Theme.of(context).colorScheme.primary;
    final controller = _replyControllers.putIfAbsent(
        c.id, () => TextEditingController());
    final sending = _replySending.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
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
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                  fontSize: 13, decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: sending ? null : () => _submitReply(c),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: sending ? 0.45 : 1.0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send,
                        size: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
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
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(
                    fontSize: 14, decoration: TextDecoration.none),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _submit,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send,
                          size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundException implements Exception {
  const _NotFoundException();
}
