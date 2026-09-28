import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Create / edit discussion — mirrors app/discussion/create.tsx.
///
/// Category dropdown (tips/resources/general/question), body (required),
/// title/imageUrl/linkUrl shown for admins only. Edit mode (editId) loads the
/// existing post. Back with unsaved changes asks for confirmation.
class DiscussionCreateScreen extends StatefulWidget {
  final String? editId;
  const DiscussionCreateScreen({super.key, this.editId});

  @override
  State<DiscussionCreateScreen> createState() => _DiscussionCreateScreenState();
}

class _DiscussionCreateScreenState extends State<DiscussionCreateScreen> {
  bool get _editing => widget.editId != null;

  bool _loading = true;
  bool _saving = false;
  bool _isAdmin = false;

  String _category = 'general';
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  String _origCategory = 'general';
  String _origTitle = '';
  String _origBody = '';
  String _origImage = '';
  String _origLink = '';

  @override
  void initState() {
    super.initState();
    _init();
    for (final c in [_titleCtrl, _bodyCtrl, _imageCtrl, _linkCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _imageCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _category != _origCategory ||
      _titleCtrl.text != _origTitle ||
      _bodyCtrl.text != _origBody ||
      _imageCtrl.text != _origImage ||
      _linkCtrl.text != _origLink;

  Future<void> _init() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      final me =
          await FirestoreRest.getDocument('users/$uid', idToken: idToken);
      _isAdmin = (me?['role'] ?? '').toString() == 'admin';
      if (_editing) {
        final post = await FirestoreRest.getDocument(
            'discussions/${widget.editId}',
            idToken: idToken);
        if (post != null) {
          _category = _origCategory =
              (post['category'] ?? 'general').toString();
          _titleCtrl.text = _origTitle =
              (post['title'] ?? '').toString();
          _bodyCtrl.text = _origBody = (post['body'] ?? '').toString();
          _imageCtrl.text = _origImage =
              (post['imageUrl'] ?? '').toString();
          _linkCtrl.text = _origLink =
              (post['linkUrl'] ?? '').toString();
        }
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard post?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _submit() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something first.')),
      );
      return;
    }
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      final me =
          await FirestoreRest.getDocument('users/${user.uid}', idToken: idToken);
      final first = (me?['firstName'] ?? '').toString();
      final last = (me?['lastName'] ?? '').toString();
      final name = '$first $last'.trim();
      final data = {
        'title': _isAdmin ? _titleCtrl.text.trim() : '',
        'body': body,
        'category': _category,
        'imageUrl': _isAdmin ? _imageCtrl.text.trim() : '',
        'linkUrl': _isAdmin ? _linkCtrl.text.trim() : '',
      };
      if (_editing) {
        await FirestoreRest.setDocument(
          'discussions/${widget.editId}',
          {...data, 'editedAt': FirestoreRest.serverTimestamp()},
          idToken: idToken,
          merge: true,
        );
      } else {
        final id =
            '${DateTime.now().millisecondsSinceEpoch}${user.uid.hashCode.abs() % 1000}';
        await FirestoreRest.setDocument(
          'discussions/$id',
          {
            ...data,
            'authorId': user.uid,
            'authorName': name.isNotEmpty ? name : 'Anonymous',
            'authorPhoto': (me?['photoURL'] ?? '').toString(),
            'isAdmin': _isAdmin,
            'likeCount': 0,
            'commentCount': 0,
            'createdAt': FirestoreRest.serverTimestamp(),
            'editedAt': null,
          },
          idToken: idToken,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    }
  }

  static const _categories = ['tips', 'resources', 'general', 'question'];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        body: Column(
          children: [
            SubpageHeader(title: _editing ? 'Edit discussion' : 'New discussion', actions: [
            TextButton(
              onPressed: (_dirty && !_saving && !_loading) ? _submit : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Post',
                      style: TextStyle(color: Colors.white)),
            ),
          ]),
            Expanded(
              child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in _categories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) =>
                        setState(() => _category = v ?? 'general'),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title (admin)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _imageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Image URL (admin, optional)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _linkCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Link URL (admin, optional)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bodyCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Share tips, ask a question…',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 6,
                    maxLines: 12,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          (_dirty && !_saving) ? _submit : null,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : Text(_editing ? 'Save changes' : 'Post'),
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
}
