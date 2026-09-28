import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Discussion detail — mirrors app/discussion/[id].tsx.
///
/// Post card (author, category, title, body, image, link, like, delete for
/// author/admin, report), comments with expandable replies, reply composers,
/// and a comment composer. Likes use the deterministic per-user reaction
/// documents (`discussions/{id}/reactions/{uid}`) with a read-then-write
/// likeCount, mirroring discussions.ts.
class DiscussionDetailScreen extends StatefulWidget {
  final String id;
  const DiscussionDetailScreen({super.key, required this.id});

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  late Future<_DiscussionData> _future;
  final _commentCtrl = TextEditingController();
  final Map<String, TextEditingController> _replyCtrls = {};
  final Set<String> _expanded = {};
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    for (final c in _replyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch}${(AuthService.currentUser?.uid ?? 'x').hashCode.abs() % 1000}';

  Future<_DiscussionData> _load() async {
    final uid = AuthService.currentUser?.uid;
    final idToken = await AuthService.getValidIdToken() ?? '';
    final post = await FirestoreRest.getDocument('discussions/${widget.id}',
        idToken: idToken);
    if (post == null) throw Exception('Discussion not found.');

    final comments = await FirestoreRest.listDocuments(
        'discussions/${widget.id}/comments',
        idToken: idToken,
        pageSize: 100);
    comments.sort((a, b) {
      final ca = a['createdAt'];
      final cb = b['createdAt'];
      final ta = ca is DateTime ? ca.millisecondsSinceEpoch : 0;
      final tb = cb is DateTime ? cb.millisecondsSinceEpoch : 0;
      return ta.compareTo(tb);
    });

    bool liked = false;
    bool isAdmin = false;
    if (uid != null) {
      final reaction = await FirestoreRest.getDocument(
          'discussions/${widget.id}/reactions/$uid',
          idToken: idToken);
      liked = reaction != null;
      final me = await FirestoreRest.getDocument('users/$uid',
          idToken: idToken);
      isAdmin = (me?['role'] ?? '').toString() == 'admin';
    }
    return _DiscussionData(
        post: post, comments: comments, liked: liked, isAdmin: isAdmin);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _toggleLike(_DiscussionData d) async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    final idToken = await AuthService.getValidIdToken() ?? '';
    final path = 'discussions/${widget.id}';
    try {
      if (d.liked) {
        await FirestoreRest.deleteDocument('$path/reactions/$uid',
            idToken: idToken);
        final count = ((d.post['likeCount'] ?? 0) as int) - 1;
        await FirestoreRest.setDocument(path, {'likeCount': count < 0 ? 0 : count},
            idToken: idToken, merge: true);
      } else {
        await FirestoreRest.setDocument('$path/reactions/$uid',
            {'liked': true, 'createdAt': FirestoreRest.serverTimestamp()},
            idToken: idToken);
        final count = ((d.post['likeCount'] ?? 0) as int) + 1;
        await FirestoreRest.setDocument(path, {'likeCount': count},
            idToken: idToken, merge: true);
      }
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Like failed: $e')));
      }
    }
  }

  Future<void> _postComment() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty) return;
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() => _posting = true);
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      final me = await FirestoreRest.getDocument('users/${user.uid}',
          idToken: idToken);
      await FirestoreRest.setDocument(
        'discussions/${widget.id}/comments/${_genId()}',
        {
          'body': body,
          'authorId': user.uid,
          'authorName': _displayName(me, user),
          'authorPhoto': (me?['photoURL'] ?? '').toString(),
          'likeCount': 0,
          'createdAt': FirestoreRest.serverTimestamp(),
        },
        idToken: idToken,
      );
      _commentCtrl.clear();
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _postReply(String commentKey) async {
    final ctrl = _replyCtrls[commentKey];
    final body = ctrl?.text.trim() ?? '';
    if (body.isEmpty) return;
    final user = AuthService.currentUser;
    if (user == null) return;
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      final me = await FirestoreRest.getDocument('users/${user.uid}',
          idToken: idToken);
      await FirestoreRest.setDocument(
        'discussions/${widget.id}/comments/$commentKey/replies/${_genId()}',
        {
          'body': body,
          'parentCommentId': commentKey,
          'authorId': user.uid,
          'authorName': _displayName(me, user),
          'authorPhoto': (me?['photoURL'] ?? '').toString(),
          'likeCount': 0,
          'createdAt': FirestoreRest.serverTimestamp(),
        },
        idToken: idToken,
      );
      ctrl?.clear();
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to reply: $e')));
      }
    }
  }

  String _displayName(Map<String, dynamic>? me, dynamic user) {
    final first = (me?['firstName'] ?? '').toString();
    final last = (me?['lastName'] ?? '').toString();
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    try {
      final dn = (user.displayName ?? '').toString();
      if (dn.isNotEmpty) return dn;
    } catch (_) {}
    return 'Anonymous';
  }

  Future<void> _deletePost(_DiscussionData d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete discussion?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      await FirestoreRest.deleteDocument('discussions/${widget.id}',
          idToken: idToken);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _report(String targetType, String targetId,
      Map<String, dynamic> ctx) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Report'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
              hintText: 'Reason for reporting…', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, reasonCtrl.text.trim()),
              child: const Text('Submit')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      await FirestoreRest.setDocument(
        'app_report_history/${_genId()}',
        {
          'source': 'discussion',
          'targetType': targetType,
          'targetId': targetId,
          'targetTitle': (ctx['title'] ?? '').toString(),
          'targetPreview': (ctx['body'] ?? '').toString(),
          'targetAuthorName': (ctx['authorName'] ?? '').toString(),
          'reason': reason,
          'reporterUid': AuthService.currentUser?.uid ?? '',
          'createdAt': FirestoreRest.serverTimestamp(),
        },
        idToken: idToken,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Report failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discussion'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_DiscussionData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load discussion:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _reload,
                        child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }
          final d = snap.data!;
          final post = d.post;
          final uid = AuthService.currentUser?.uid;
          final canDelete = d.isAdmin ||
              ((post['authorId'] ?? '').toString() == (uid ?? ''));

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _postCard(d, canDelete),
                      const SizedBox(height: 12),
                      Text('Comments (${d.comments.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy)),
                      const SizedBox(height: 8),
                      for (final c in d.comments)
                        _commentCard(c, d.isAdmin, uid),
                    ],
                  ),
                ),
              ),
              _composer(),
            ],
          );
        },
      ),
    );
  }

  Widget _postCard(_DiscussionData d, bool canDelete) {
    final post = d.post;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar((post['authorPhoto'] ?? '').toString(),
                    (post['authorName'] ?? 'A').toString()),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                                (post['authorName'] ?? 'Anonymous')
                                    .toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (post['isAdmin'] == true) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified,
                                size: 16, color: AppColors.accent),
                          ],
                        ],
                      ),
                      if ((post['category'] ?? '').toString().isNotEmpty)
                        Text((post['category'] ?? '').toString(),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') _deletePost(d);
                    if (v == 'report') {
                      _report('post', widget.id, post);
                    }
                  },
                  itemBuilder: (_) => [
                    if (canDelete)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    const PopupMenuItem(
                        value: 'report', child: Text('Report')),
                  ],
                ),
              ],
            ),
            if ((post['title'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text((post['title'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 8),
            Text((post['body'] ?? '').toString(),
                style: const TextStyle(height: 1.5)),
            if ((post['imageUrl'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                    (post['imageUrl'] ?? '').toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink()),
              ),
            ],
            if ((post['linkUrl'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText((post['linkUrl'] ?? '').toString(),
                  style: const TextStyle(
                      color: AppColors.accent,
                      decoration: TextDecoration.underline)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _toggleLike(d),
                  icon: Icon(
                      d.liked ? Icons.favorite : Icons.favorite_border,
                      color: d.liked ? Colors.red : null),
                  label: Text('${(post['likeCount'] ?? 0)}'),
                ),
                const Spacer(),
                if ((post['courseName'] ?? '').toString().isNotEmpty)
                  Text((post['courseName'] ?? '').toString(),
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentCard(
      Map<String, dynamic> c, bool isAdmin, String? uid) {
    final commentKey = _commentKeyOf(c);
    final expanded = _expanded.contains(commentKey);
    final canDelete =
        isAdmin || ((c['authorId'] ?? '').toString() == (uid ?? ''));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar((c['authorPhoto'] ?? '').toString(),
                    (c['authorName'] ?? 'A').toString()),
                const SizedBox(width: 8),
                Expanded(
                  child: Text((c['authorName'] ?? 'Anonymous').toString(),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (x) => AlertDialog(
                          title: const Text('Delete comment?'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(x, false),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(x, true),
                                child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          final idToken =
                              await AuthService.getValidIdToken() ??
                                  '';
                          await FirestoreRest.deleteDocument(
                              'discussions/${widget.id}/comments/$commentKey',
                              idToken: idToken);
                          _reload();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Delete failed: $e')));
                          }
                        }
                      }
                    }
                    if (v == 'report') {
                      _report('comment', commentKey, c);
                    }
                  },
                  itemBuilder: (_) => [
                    if (canDelete)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    const PopupMenuItem(
                        value: 'report', child: Text('Report')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text((c['body'] ?? '').toString()),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                setState(() {
                  if (expanded) {
                    _expanded.remove(commentKey);
                  } else {
                    _expanded.add(commentKey);
                  }
                });
              },
              child: Text(expanded ? 'Hide replies' : 'Replies'),
            ),
            if (expanded)
              _RepliesView(
                discussionId: widget.id,
                commentKey: commentKey,
                isAdmin: isAdmin,
                uid: uid,
                onReport: (id, ctx) => _report('comment', id, ctx),
                onChanged: _reload,
              ),
            if (expanded)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrls.putIfAbsent(
                          commentKey, () => TextEditingController()),
                      decoration: const InputDecoration(
                        hintText: 'Write a reply…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send,
                        color: AppColors.navy),
                    onPressed: () => _postReply(commentKey),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _commentKeyOf(Map<String, dynamic> c) {
    // Prefer a real document id when the list API provides one; otherwise
    // fall back to a content-derived key (replies then can't load — the REST
    // list API does not return doc ids).
    for (final k in ['docId', 'id']) {
      final v = (c[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    final created = c['createdAt'];
    final ms = created is DateTime ? created.millisecondsSinceEpoch : 0;
    return "local:${c['authorId']}:$ms:${(c['body'] ?? '').toString().hashCode}";
  }

  Widget _avatar(String photo, String name) {
    if (photo.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(photo));
    }
    return CircleAvatar(
      backgroundColor: AppColors.navy.withValues(alpha: 0.1),
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'A',
          style: const TextStyle(color: AppColors.navy)),
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                decoration: const InputDecoration(
                  hintText: 'Write a comment…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 4,
              ),
            ),
            const SizedBox(width: 8),
            _posting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.send,
                        color: AppColors.navy),
                    onPressed: _postComment,
                  ),
          ],
        ),
      ),
    );
  }
}

class _DiscussionData {
  final Map<String, dynamic> post;
  final List<Map<String, dynamic>> comments;
  final bool liked;
  final bool isAdmin;
  _DiscussionData(
      {required this.post,
      required this.comments,
      required this.liked,
      required this.isAdmin});
}

/// Replies under one comment, loaded lazily when expanded.
class _RepliesView extends StatefulWidget {
  final String discussionId;
  final String commentKey;
  final bool isAdmin;
  final String? uid;
  final void Function(String id, Map<String, dynamic> ctx) onReport;
  final VoidCallback onChanged;
  const _RepliesView(
      {required this.discussionId,
      required this.commentKey,
      required this.isAdmin,
      required this.uid,
      required this.onReport,
      required this.onChanged});

  @override
  State<_RepliesView> createState() => _RepliesViewState();
}

class _RepliesViewState extends State<_RepliesView> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    // Content-derived keys (prefixed "local:") are not real document ids, so
    // skip the fetch instead of hitting a bogus path.
    if (widget.commentKey.startsWith('local:')) return [];
    final idToken = await AuthService.getValidIdToken() ?? '';
    try {
      final rows = await FirestoreRest.listDocuments(
          'discussions/${widget.discussionId}/comments/${widget.commentKey}/replies',
          idToken: idToken,
          pageSize: 100);
      rows.sort((a, b) {
        final ca = a['createdAt'];
        final cb = b['createdAt'];
        final ta = ca is DateTime ? ca.millisecondsSinceEpoch : 0;
        final tb = cb is DateTime ? cb.millisecondsSinceEpoch : 0;
        return ta.compareTo(tb);
      });
      return rows;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final replies = snap.data ?? [];
        if (replies.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final r in replies)
              Container(
                margin: const EdgeInsets.only(left: 16, bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((r['authorName'] ?? 'Anonymous').toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    Text((r['body'] ?? '').toString()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
