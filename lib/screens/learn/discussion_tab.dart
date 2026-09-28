import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Discussion tab — mirrors app/(tabs)/discussion.tsx.
/// Gradient header + search, post list with like/report/delete, FAB.
class DiscussionTab extends StatefulWidget {
  const DiscussionTab({super.key});

  @override
  State<DiscussionTab> createState() => _DiscussionTabState();
}

class _DiscussionTabState extends State<DiscussionTab> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await AuthService.getValidIdToken();
    final docs = await FirestoreRest.listDocuments('discussions',
        idToken: token, pageSize: 50);
    docs.removeWhere((d) => d['isDeleted'] == true);
    docs.sort(
        (a, b) => _num(b['createdAt']).compareTo(_num(a['createdAt'])));
    return docs;
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> docs) {
    if (_query.trim().isEmpty) return docs;
    final q = _query.toLowerCase();
    return docs.where((d) {
      final t = ((d['title'] as String?) ?? '').toLowerCase();
      final b = ((d['body'] as String?) ?? '').toLowerCase();
      return t.contains(q) || b.contains(q);
    }).toList();
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = post['id'] as String;
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    final liked = _likedIds.contains(id);
    setState(() {
      if (liked) {
        _likedIds.remove(id);
      } else {
        _likedIds.add(id);
      }
    });
    try {
      final token = await AuthService.getValidIdToken();
      final likes =
          List<String>.from((post['likes'] as List?)?.cast<String>() ?? []);
      if (liked) {
        likes.remove(uid);
      } else if (!likes.contains(uid)) {
        likes.add(uid);
      }
      await FirestoreRest.setDocument('discussions/$id', {'likes': likes},
          idToken: token, merge: true);
      post['likes'] = likes;
    } catch (_) {
      setState(() {
        if (liked) {
          _likedIds.add(id);
        } else {
          _likedIds.remove(id);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update like.')));
      }
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final id = post['id'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument('discussions/$id', idToken: token);
      if (mounted) setState(() => _future = _load());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete post.')));
      }
    }
  }

  void _showGuidelines() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discussion Guidelines'),
        content: const Text(
          '• Be respectful to fellow learners.\n'
          '• Ask study-related questions.\n'
          '• No spam or advertisements.\n'
          '• Do not share personal contact details.\n'
          '• Report inappropriate content.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it')),
        ],
      ),
    );
  }

  String _timeAgo(dynamic v) {
    final ms = _num(v).toInt();
    if (ms <= 0) return '';
    final diff = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.currentUser?.uid;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 170,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.navy, AppColors.deepNavy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('Discussion',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      'Ask questions, share knowledge',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline,
                                  color: Colors.white),
                              onPressed: _showGuidelines,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search discussions...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Text('Failed to load discussions.'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () =>
                              setState(() => _future = _load()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final posts = _filtered(snap.data ?? []);
                if (posts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: Text('No discussions yet. Be the first!',
                            style: TextStyle(color: Colors.grey))),
                  );
                }
                return Column(
                  children: posts.map((p) => _postCard(p, uid)).toList(),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.navy,
        onPressed: () => context.push('/discussion/create'),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> p, String? uid) {
    final id = p['id'] as String;
    final title = (p['title'] as String?) ?? '';
    final body = (p['body'] as String?) ?? '';
    final author = (p['authorName'] as String?) ?? 'Anonymous';
    final likes = ((p['likes'] as List?)?.length ?? 0) +
        (_likedIds.contains(id) ? 1 : 0);
    final comments = (p['commentCount'] as num?)?.toInt() ?? 0;
    final isMine = uid != null && p['authorId'] == uid;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => context.push('/discussion/$id'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.navy,
                    radius: 18,
                    child: Text(
                        author.isNotEmpty ? author[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(_timeAgo(p['createdAt']),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (isMine)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: Colors.red),
                      onPressed: () => _deletePost(p),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.flag_outlined,
                          size: 20, color: Colors.grey),
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(
                              content:
                                  Text('Thanks — our team will review this post.'))),
                    ),
                ],
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    onTap: () => _toggleLike(p),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _likedIds.contains(id)
                                ? Icons.thumb_up
                                : Icons.thumb_up_outlined,
                            size: 18,
                            color: _likedIds.contains(id)
                                ? AppColors.navy
                                : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text('$likes',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      const Icon(Icons.comment_outlined,
                          size: 18, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('$comments',
                          style: const TextStyle(fontSize: 13)),
                    ],
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
