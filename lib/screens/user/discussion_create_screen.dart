// Discussion create / edit screen (/discussion/create, ?editId=).
// Mirrors app/discussion/create.tsx:
// - new post vs edit mode (prefill + updateDiscussion)
// - admin-only: title field (required for NEW posts), image/link URL tools
// - category dropdown for everyone
// - canSubmit: body non-empty; admin new posts also need a title
// - discard-confirm on back with unsaved content
// - offline: warning banner + submit disabled (no offline queue for posts)
// - success: new → back to feed (feed refreshes); edit → replace with detail
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../learn/discussion_tab.dart';

class DiscussionCreateScreen extends StatefulWidget {
  final String? editId;

  const DiscussionCreateScreen({super.key, this.editId});

  @override
  State<DiscussionCreateScreen> createState() =>
      _DiscussionCreateScreenState();
}

class _DiscussionCreateScreenState extends State<DiscussionCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  DiscussionCategory? _category;
  bool _posting = false;
  bool _loadingPost = false;
  bool _offline = false;

  bool get _isEdit => widget.editId != null;
  bool get _isAdmin => ProfileStore.instance.profile?.isAdmin ?? false;

  bool get _canSubmit => canSubmitDiscussionPost(
        body: _bodyCtrl.text,
        isAdmin: _isAdmin,
        title: _titleCtrl.text,
        editId: widget.editId,
      );

  bool get _hasUnsaved => hasUnsavedDiscussionContent(
        title: _titleCtrl.text,
        body: _bodyCtrl.text,
        imageUrl: _imageCtrl.text,
        linkUrl: _linkCtrl.text,
      );

  @override
  void initState() {
    super.initState();
    _checkOnline();
    if (_isEdit) _loadPost();
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

  Future<void> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(
          () => _offline = results.every((r) => r == ConnectivityResult.none));
    } catch (_) {}
  }

  Future<void> _loadPost() async {
    setState(() => _loadingPost = true);
    try {
      final post =
          await DiscussionService.fetchDiscussion(widget.editId!);
      if (!mounted) return;
      if (post == null) {
        showToast(
            context,
            AppLanguage.tr('This post has been deleted',
                'यो पोस्ट मेटाइएको छ'),
            ToastVariant.error);
        context.pop();
        return;
      }
      setState(() {
        _titleCtrl.text = post.title;
        _bodyCtrl.text = post.body;
        _category = discussionCategoryFromValue(post.category);
        _imageCtrl.text = post.imageUrl ?? '';
        _linkCtrl.text = post.linkUrl ?? '';
        _loadingPost = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPost = false);
      showToast(
          context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
      context.pop();
    }
  }

  Future<void> _handleBack() async {
    if (!_hasUnsaved) {
      context.pop();
      return;
    }
    final discard = await AppModalShell.show<bool>(
      context: context,
      builder: (pageContext) => _DiscardBody(),
    );
    if (discard == true && mounted) context.pop();
  }

  Future<void> _submit() async {
    if (_posting || !_canSubmit || _offline) return;
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.pop();
      return;
    }
    final profile = ProfileStore.instance.profile;
    final authorName = (profile?.name ?? '').trim().isEmpty
        ? 'Anonymous'
        : profile!.name.trim();
    final courseInfo = ProfileStore.instance.courseInfo;

    setState(() => _posting = true);
    try {
      final categoryValue =
          _category == null ? '' : discussionCategoryValue(_category!);
      if (_isEdit) {
        await DiscussionService.updateDiscussion(
          widget.editId!,
          title: _isAdmin ? _titleCtrl.text.trim() : null,
          body: _bodyCtrl.text.trim(),
          category: categoryValue,
          imageUrl: _isAdmin && _imageCtrl.text.trim().isNotEmpty
              ? _imageCtrl.text.trim()
              : null,
          linkUrl: _isAdmin && _linkCtrl.text.trim().isNotEmpty
              ? _linkCtrl.text.trim()
              : null,
        );
        if (!mounted) return;
        context.pushReplacement('/discussion/${widget.editId}');
      } else {
        await DiscussionService.createDiscussion(
          title: _isAdmin ? _titleCtrl.text.trim() : '',
          body: _bodyCtrl.text.trim(),
          category: categoryValue,
          authorName: authorName,
          authorPhoto: profile?.photoURL,
          authorId: uid,
          courseId: courseInfo?.courseId,
          subcourseId: courseInfo?.subcourseId,
          courseName: courseInfo?.courseName,
          subcourseName: courseInfo?.subcourseName,
          imageUrl: _isAdmin && _imageCtrl.text.trim().isNotEmpty
              ? _imageCtrl.text.trim()
              : null,
          linkUrl: _isAdmin && _linkCtrl.text.trim().isNotEmpty
              ? _linkCtrl.text.trim()
              : null,
          isAdmin: _isAdmin,
        );
        if (!mounted) return;
        DiscussionTab.requestRefresh();
        context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            SubpageHeader(
              title: _isEdit
                  ? AppLanguage.tr('Edit', 'सम्पादन गर्नुहोस्')
                  : AppLanguage.tr('Create Post', 'पोस्ट बनाउनुहोस्'),
              showBack: true,
              onBackPress: _handleBack,
            ),
            Expanded(
              child: _loadingPost
                  ? Center(child: PreloadingWidget(label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...')))
                  : _buildForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_offline)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              AppLanguage.tr(
                  'You\'re offline. Connect to the internet to post.',
                  'तपाईं अफलाइन हुनुहुन्छ। पोस्ट गर्न इन्टरनेटमा जडान गर्नुहोस्।'),
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFB45309),
                  decoration: TextDecoration.none),
            ),
          ),
        if (_isAdmin) ...[
          _Label(
              '${AppLanguage.tr('Title', 'शीर्षक')} (${AppLanguage.tr('optional', 'ऐच्छिक')})'),
          _TextInput(
            controller: _titleCtrl,
            hint: AppLanguage.tr(
                'Give your discussion a title…', 'छलफललाई शीर्षक दिनुहोस्…'),
          ),
          const SizedBox(height: 14),
        ],
        _Label(AppLanguage.tr('Category', 'श्रेणी')),
        _CategoryDropdown(
          value: _category,
          onChanged: (c) => setState(() => _category = c),
        ),
        const SizedBox(height: 14),
        if (_isAdmin) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr('Admin post tools', 'एडमिन पोस्ट उपकरण'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 10),
                _Label(
                    '${AppLanguage.tr('Image URL', 'इमेज URL')} (${AppLanguage.tr('optional', 'ऐच्छिक')})'),
                _TextInput(
                  controller: _imageCtrl,
                  hint: 'https://…',
                  url: true,
                ),
                const SizedBox(height: 10),
                _Label(
                    '${AppLanguage.tr('Link URL', 'लिंक URL')} (${AppLanguage.tr('optional', 'ऐच्छिक')})'),
                _TextInput(
                  controller: _linkCtrl,
                  hint: 'https://…',
                  url: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _Label(AppLanguage.tr(
            'What\'s on your mind?', 'तपाईंको मनमा के छ?')),
        _TextInput(
          controller: _bodyCtrl,
          hint: AppLanguage.tr('Write your discussion...',
              'आफ्नो छलफल लेख्नुहोस्...'),
          multiline: true,
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed:
                (_canSubmit && !_offline && !_posting) ? _submit : null,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _posting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _isEdit
                        ? AppLanguage.tr('Save', 'सेभ गर्नुहोस्')
                        : AppLanguage.tr('Post', 'पोस्ट गर्नुहोस्'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
            decoration: TextDecoration.none),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool multiline;
  final bool url;

  const _TextInput({
    required this.controller,
    required this.hint,
    this.multiline = false,
    this.url = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: multiline ? 6 : 1,
      maxLines: multiline ? 10 : 1,
      keyboardType: url ? TextInputType.url : null,
      autocorrect: !url,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            decoration: TextDecoration.none),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary),
        ),
      ),
      style: const TextStyle(
          fontSize: 14, decoration: TextDecoration.none),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final DiscussionCategory? value;
  final ValueChanged<DiscussionCategory?> onChanged;

  const _CategoryDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.current.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DiscussionCategory?>(
          value: value,
          isExpanded: true,
          hint: Text(
            AppLanguage.tr('Select a category…', 'श्रेणी छान्नुहोस्…'),
            style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
                decoration: TextDecoration.none),
          ),
          items: DiscussionCategory.values
              .map((c) => DropdownMenuItem<DiscussionCategory?>(
                    value: c,
                    child: Text(
                      discussionCategoryLabel(c, lang),
                      style: const TextStyle(
                          fontSize: 14,
                          decoration: TextDecoration.none),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Discard-confirm body for unsaved form content.
class _DiscardBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLanguage.tr('Discard this post?', 'यो पोस्ट हटाउने हो?'),
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none),
        ),
        const SizedBox(height: 8),
        Text(
          AppLanguage.tr(
              'You have unsaved content. Are you sure you want to discard it?',
              'तपाईंसँग सेव नगरिएको सामग्री छ। तपाई पक्का हटाउन चाहनुहुन्छ?'),
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              decoration: TextDecoration.none),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                    style:
                        const TextStyle(decoration: TextDecoration.none)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(AppLanguage.tr('Discard', 'मेट्नुहोस्'),
                    style:
                        const TextStyle(decoration: TextDecoration.none)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
