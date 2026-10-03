// Discussion create / edit screen (/discussion/create, ?editId=).
//
// BEHAVIOR mirrors app/discussion/create.tsx exactly:
// - new post vs edit mode (prefill + updateDiscussion)
// - admin-only: title field (required for NEW posts), image/link URL tools
// - category for everyone; body required
// - canSubmit: body non-empty; admin new posts also need a title
// - discard-confirm on back with unsaved content
// - offline: warning banner + submit disabled (no offline queue for posts)
// - success: new → feed refresh + pop; edit → replace with detail
// - failure: "Something went wrong" toast
//
// DESIGN is premium-modern (unique to Flutter): section cards with soft
// shadows, category as selectable chips, live post-card preview as they
// type, gradient submit button with loading state. All animations finite.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/discussion/discussion_post_card.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import '../learn/discussion_tab.dart';

class DiscussionCreateScreen extends StatefulWidget {
  final String? editId;

  const DiscussionCreateScreen({super.key, this.editId});

  @override
  State<DiscussionCreateScreen> createState() =>
      _DiscussionCreateScreenState();
}

class _DiscussionCreateScreenState extends State<DiscussionCreateScreen> {
  static const _border = Color(0xFFE2E8F0);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  DiscussionCategory? _category;
  bool _posting = false;
  bool _loadingPost = false;
  bool _offline = false;
  bool _showPreview = false;

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
    if (_isEdit) {
      _loadPost();
    } else {
      // Brief opening preloading for new posts too (visual feedback
      // that the page is opening).
      _loadingPost = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadingPost = false);
      });
    }
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
      final post = await DiscussionService.fetchDiscussion(widget.editId!);
      if (!mounted) return;
      if (post == null) {
        showToast(
            context,
            AppLanguage.tr(
                'This post has been deleted', 'यो पोस्ट मेटाइएको छ'),
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
      builder: (pageContext) => const _DiscardBody(),
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
    // No outer SafeArea: SubpageHeader is full-bleed under the status bar.
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
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
                ? Center(
                    child: PreloadingWidget(tinted: false,
                        label: AppLanguage.tr(
                            'Loading...', 'लोड हुँदैछ...')))
                : _buildForm(),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildForm() {
    final previewable = _bodyCtrl.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_offline)
          SyllabusEntrance(
            delayMs: 0,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFB45309).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_outlined,
                      size: 18, color: Color(0xFFB45309)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLanguage.tr(
                          'You\'re offline. Connect to the internet to post.',
                          'तपाईं अफलाइन हुनुहुन्छ। पोस्ट गर्न इन्टरनेटमा जडान गर्नुहोस्।'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                          decoration: TextDecoration.none),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isAdmin)
          SyllabusEntrance(
            delayMs: 40,
            child: _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(AppLanguage.tr('Title', 'शीर्षक'),
                      optional: true),
                  const SizedBox(height: 8),
                  _TextInput(
                    controller: _titleCtrl,
                    hint: AppLanguage.tr('Give your discussion a title…',
                        'छलफललाई शीर्षक दिनुहोस्…'),
                  ),
                ],
              ),
            ),
          ),
        if (_isAdmin) const SizedBox(height: 12),
        SyllabusEntrance(
          delayMs: 80,
          child: _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label(AppLanguage.tr('Category', 'श्रेणी')),
                const SizedBox(height: 10),
                _CategoryChips(
                  value: _category,
                  onChanged: (c) => setState(
                      () => _category = _category == c ? null : c),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isAdmin) ...[
          SyllabusEntrance(
            delayMs: 120,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.07),
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLanguage.tr(
                            'Admin post tools', 'एडमिन पोस्ट उपकरण'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Label(AppLanguage.tr('Image URL', 'इमेज URL'),
                      optional: true),
                  const SizedBox(height: 8),
                  _TextInput(
                    controller: _imageCtrl,
                    hint: 'https://…',
                    url: true,
                  ),
                  const SizedBox(height: 12),
                  _Label(AppLanguage.tr('Link URL', 'लिंक URL'),
                      optional: true),
                  const SizedBox(height: 8),
                  _TextInput(
                    controller: _linkCtrl,
                    hint: 'https://…',
                    url: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SyllabusEntrance(
          delayMs: 160,
          child: _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label(AppLanguage.tr(
                    'What\'s on your mind?', 'तपाईंको मनमा के छ?')),
                const SizedBox(height: 8),
                _TextInput(
                  controller: _bodyCtrl,
                  hint: AppLanguage.tr('Write your discussion...',
                      'आफ्नो छलफल लेख्नुहोस्...'),
                  multiline: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Live preview — the exact card readers will see.
        SyllabusEntrance(
          delayMs: 200,
          child: _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: previewable
                      ? () =>
                          setState(() => _showPreview = !_showPreview)
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: previewable
                            ? Theme.of(context).colorScheme.primary
                            : _grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLanguage.tr('Preview', 'पूर्वावलोकन'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: previewable
                                ? Theme.of(context).colorScheme.primary
                                : _grey.withValues(alpha: 0.5),
                            decoration: TextDecoration.none),
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _showPreview ? 0.5 : 0,
                        duration:
                            const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: previewable
                              ? _grey
                              : _grey.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showPreview && previewable) ...[
                  const SizedBox(height: 12),
                  _buildPreviewCard(),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SyllabusEntrance(
          delayMs: 240,
          child: _SubmitButton(
            label: _isEdit
                ? AppLanguage.tr('Save', 'सेभ गर्नुहोस्')
                : AppLanguage.tr('Post', 'पोस्ट गर्नुहोस्'),
            loading: _posting,
            enabled: _canSubmit && !_offline && !_posting,
            onTap: _submit,
          ),
        ),
      ],
    );
  }

  /// Live preview rendered with the shared post card.
  Widget _buildPreviewCard() {
    final profile = ProfileStore.instance.profile;
    final uid = AuthService.currentUser?.uid ?? '';
    final name = (profile?.name ?? '').trim().isEmpty
        ? 'Anonymous'
        : profile!.name.trim();
    final image = _imageCtrl.text.trim();
    final link = _linkCtrl.text.trim();
    return DiscussionPostCard(
      post: DiscussionPost(
        id: 'preview',
        title: _isAdmin ? _titleCtrl.text.trim() : '',
        body: _bodyCtrl.text.trim(),
        category:
            _category == null ? '' : discussionCategoryValue(_category!),
        authorName: name,
        authorPhoto: profile?.photoURL,
        authorId: uid,
        isAdmin: _isAdmin,
        imageUrl: _isAdmin && image.isNotEmpty ? image : null,
        linkUrl: _isAdmin && link.isNotEmpty ? link : null,
        createdAt: DateTime.now(),
      ),
      liked: false,
      onToggleLike: (_) async {},
      onTap: () {},
      onMenu: (_) {},
      timestampOverride:
          formatDiscussionDetailDateTime(DateTime.now()),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool optional;

  const _Label(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
              decoration: TextDecoration.none),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              AppLanguage.tr('Optional', 'ऐच्छिक'),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                  decoration: TextDecoration.none),
            ),
          ),
        ],
      ],
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
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
      ),
      style: const TextStyle(
          fontSize: 14, decoration: TextDecoration.none),
    );
  }
}

/// Category as selectable chips (tap again to clear).
class _CategoryChips extends StatelessWidget {
  final DiscussionCategory? value;
  final ValueChanged<DiscussionCategory> onChanged;

  const _CategoryChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.current.value;
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: DiscussionCategory.values.map((c) {
        final selected = value == c;
        return GestureDetector(
          onTap: () => onChanged(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      colors: [
                        primary,
                        Color.lerp(primary, Colors.black, 0.12)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: selected ? null : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              discussionCategoryLabel(c, lang),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : const Color(0xFF64748B),
                  decoration: TextDecoration.none),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Gradient submit button with loading state.
class _SubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _SubmitButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final active = enabled && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  colors: [
                    primary,
                    Color.lerp(primary, Colors.black, 0.15)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active ? null : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(16),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Text(
                label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? Colors.white
                        : const Color(0xFF94A3B8),
                    decoration: TextDecoration.none),
              ),
      ),
    );
  }
}

/// Discard-confirm body for unsaved form content.
class _DiscardBody extends StatelessWidget {
  const _DiscardBody();

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
