import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/firestore_rest.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/subpage_header.dart';

/// Subject read mode — faithful port of app/subjects/read.tsx.
///
/// Shuffled 'read'-mode question set as expand/collapse "Important
/// Questions"; expand reveals options + explanation. Records activity
/// progress once on leave (not per tap).
class SubjectReadScreen extends StatefulWidget {
  final String subjectId;
  final String chapterId;
  final String? unitId;
  final String courseId;
  final String subcourseId;
  final String? subjectName;
  final String? chapterName;
  final String? unitName;

  const SubjectReadScreen({
    super.key,
    required this.subjectId,
    required this.chapterId,
    this.unitId,
    this.courseId = '',
    this.subcourseId = '',
    this.subjectName,
    this.chapterName,
    this.unitName,
  });

  @override
  State<SubjectReadScreen> createState() => _SubjectReadScreenState();
}

class _SubjectReadScreenState extends State<SubjectReadScreen> {
  List<SubjectQuestion> _questions = [];
  Set<String> _expanded = {};
  bool _loading = true;
  bool _loadError = false;
  bool _isPremium = false;

  // Progress-tracking refs (port of read.tsx's refs).
  final Set<String> _opened = {};
  late DateTime _openedAt;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _recordProgress();
    super.dispose();
  }

  void _recordProgress() {
    if (_recorded) { return; }
    _recorded = true;
    final user = AuthService.currentUser;
    if (user == null) return;
    final seconds = DateTime.now().difference(_openedAt).inSeconds;
    final viewed = _opened.toList();
    if (user.uid.isEmpty ||
        widget.chapterId.isEmpty ||
        (viewed.isEmpty && seconds < 5)) {
      return;
    }
    recordActivityProgress(
      user.uid,
      source: 'read',
      refId: widget.chapterId,
      courseId: widget.courseId,
      subcourseId: widget.subcourseId,
      viewedItemIds: viewed,
      totalItems: _questions.length,
      secondsSpent: seconds,
      countVisit: true,
      completed: _questions.isNotEmpty && viewed.length >= _questions.length,
    );
    if (viewed.isNotEmpty) recordAppActivity(user.uid);
  }

  Future<void> _load() async {
    final user = AuthService.currentUser;
    if (user == null ||
        widget.subjectId.isEmpty ||
        widget.chapterId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final token = await AuthService.getValidIdToken();
      Map<String, dynamic>? userDoc;
      try {
        userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
      } catch (_) {}
      _isPremium =
          UserProfile.fromMap(user.uid, userDoc ?? {}).hasActivePremium;

      final questions = await fetchReadQuestionSet(
        courseId: widget.courseId.isEmpty
            ? 'civil-engineering'
            : widget.courseId,
        subcourseId: widget.subcourseId.isEmpty
            ? 'civil-assistant-sub-engineer'
            : widget.subcourseId,
        subjectId: widget.subjectId,
        unitId: (widget.unitId ?? '').isEmpty ? null : widget.unitId,
        chapterId: widget.chapterId,
      );
      setState(() {
        _questions = shuffleList(questions);
        _expanded = {};
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  void _toggle(String id) {
    if (!_expanded.contains(id)) _opened.add(id);
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  void _expandAll() {
    _opened.addAll(_questions.map((q) => q.id));
    setState(() => _expanded = _questions.map((q) => q.id).toSet());
  }

  void _collapseAll() => setState(() => _expanded = {});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _recordProgress();
      },
      child: Scaffold(
        body: Column(
          children: [
            SubpageHeader(
              title: 'Read Mode',
              onBackPress: () => context.pop(),
            ),
            Expanded(
              child: _loading
                  ? const PreloadingWidget(
                      tinted: false,
                      label: 'Loading...',
                      hint: 'Fetching your content',
                    )
                  : _loadError
                      ? _dataNotFound(
                          title: 'Something went wrong',
                          description:
                              'Please check your connection and try again.',
                          onRetry: _load,
                        )
                      : _questions.isEmpty
                          ? _dataNotFound(
                              title:
                                  'No questions are available for this chapter yet.',
                              description:
                                  'Read-mode questions are not available for this chapter yet. Content is being prepared and will be added soon.',
                            )
                          : _mainList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors src/components/feedback/DataNotFound.tsx.
  Widget _dataNotFound({
    required String title,
    required String description,
    VoidCallback? onRetry,
  }) {
    final palette = ExpoPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 56, color: palette.textDisabled),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: palette.textSecondary, height: 19 / 12),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Try Again',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mainList() {
    final palette = ExpoPalette.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final allExpanded = _questions.isNotEmpty &&
        _questions.every((q) => _expanded.contains(q.id));
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 48),
      children: [
        // Section header: Important Questions + expand/collapse all.
        SyllabusEntrance(
          delayMs: 0,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: palette.primary.withValues(alpha: 0.08),
                  ),
                  child: Icon(Icons.bookmark_rounded,
                      size: 19, color: palette.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Important Questions',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 21 / 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        (widget.chapterName ?? '').isNotEmpty
                            ? widget.chapterName!
                            : 'Chapter',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: palette.textSecondary,
                          height: 16 / 9,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: allExpanded ? _collapseAll : _expandAll,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 132),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          allExpanded
                              ? Icons.keyboard_arrow_up_outlined
                              : Icons.keyboard_arrow_down_outlined,
                          size: 17,
                          color: palette.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            allExpanded ? 'Collapse All' : 'Expand All',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2559C7),
                              height: 16 / 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Question cards.
        ..._questions.asMap().entries.map((entry) {
          final index = entry.key;
          final q = entry.value;
          return SyllabusEntrance(
            key: ValueKey('read_card_${q.id}'),
            delayMs: (index < 8 ? index : 8) * 60,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _questionCard(palette, q, index),
            ),
          );
        }),
      ],
    );
  }

  Widget _questionCard(
      ExpoPalette palette, SubjectQuestion q, int index) {
    final isOpen = _expanded.contains(q.id);
    final difficultyColor = q.difficulty == 'easy'
        ? palette.success
        : q.difficulty == 'medium'
            ? palette.warning
            : palette.danger;
    final difficultyLabel = q.difficulty.isEmpty
        ? ''
        : q.difficulty[0].toUpperCase() + q.difficulty.substring(1);
    final title = bilingual(q.text, q.textNe);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: palette.primary.withValues(alpha: 0.08),
                ),
                child: Text(
                  'Qn. ${index + 1}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: palette.primary),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: difficultyColor.withValues(alpha: 0.09),
                ),
                child: Text(
                  difficultyLabel,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: difficultyColor),
                ),
              ),
              const Spacer(),
              _ReadBookmarkButton(
                uid: AuthService.currentUser?.uid ?? '',
                isPro: _isPremium,
                chapterId: widget.chapterId,
                courseId: widget.courseId,
                subcourseId: widget.subcourseId,
                subjectName: widget.subjectName,
                chapterName: widget.chapterName,
                question: q,
              ),
              _smallActionButton(
                icon: Icons.flag_rounded,
                tooltip: 'Report',
                palette: palette,
                onTap: () => ReportDialog.show(
                  context: context,
                  question: bilingual(q.text, q.textNe),
                  options: q.options,
                  questionId: q.id,
                  subject: widget.subjectName,
                  chapter: widget.chapterName,
                  unit: widget.unitName,
                  mode: 'read',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 22 / 14,
              color: palette.textPrimary,
            ),
          ),
          InkWell(
            onTap: () => _toggle(q.id),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    isOpen
                        ? Icons.arrow_circle_up_outlined
                        : Icons.arrow_circle_down_outlined,
                    size: 21,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOpen ? 'Collapse answer' : 'Tap to show answer',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: palette.primary,
                        height: 15 / 10),
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            const SizedBox(height: 12),
            ...q.options.asMap().entries.map((opt) {
              final correct = opt.key == q.correctIndex;
              final border = correct
                  ? palette.success.withValues(alpha: 0.5)
                  : palette.border;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(ExpoRadius.md),
                    color: correct
                        ? palette.success.withValues(alpha: 0.07)
                        : palette.surface,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: border, width: 1.4),
                          color: correct
                              ? palette.success
                              : Colors.transparent,
                        ),
                        child: Text(
                          String.fromCharCode(65 + opt.key),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: correct
                                ? Colors.white
                                : palette.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          opt.value,
                          style: TextStyle(
                              fontSize: 12,
                              height: 18 / 12,
                              color: palette.textPrimary),
                        ),
                      ),
                      if (correct)
                        Icon(Icons.check_circle,
                            size: 18, color: palette.success),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                    color: palette.warning.withValues(alpha: 0.33)),
                borderRadius: BorderRadius.circular(ExpoRadius.md),
                color: palette.warning.withValues(alpha: 0.07),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 19, color: palette.warning),
                      const SizedBox(width: 6),
                      Text(
                        'Explanation',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 20 / 13,
                            color: palette.warning),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bilingual(q.explanation, q.explanationNe),
                    style: TextStyle(
                        fontSize: 12,
                        height: 19 / 12,
                        color: palette.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 30×30 tap target mirroring read.tsx's `smallAction` style.
  Widget _smallActionButton({
    required IconData icon,
    required String tooltip,
    required ExpoPalette palette,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 30,
      height: 30,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 18, color: palette.textSecondary),
        ),
      ),
    );
  }
}

/// Per-question bookmark toggle for read mode — the Flutter equivalent of
/// React's BookmarkButton (context "read", refId "${chapterId}:${question.id}").
/// Bookmarks live at users/{uid}/bookmarks with the same doc-id scheme as the
/// Expo app (`read__<safeSegment(refId)>`), so the Bookmarks screen lists them
/// without changes.
class _ReadBookmarkButton extends StatefulWidget {
  final String uid;
  final bool isPro;
  final String chapterId;
  final String courseId;
  final String subcourseId;
  final String? subjectName;
  final String? chapterName;
  final SubjectQuestion question;

  const _ReadBookmarkButton({
    required this.uid,
    required this.isPro,
    required this.chapterId,
    required this.courseId,
    required this.subcourseId,
    this.subjectName,
    this.chapterName,
    required this.question,
  });

  @override
  State<_ReadBookmarkButton> createState() => _ReadBookmarkButtonState();
}

/// Thrown by [_ReadBookmarkButtonState._save] when the free-tier bookmark
/// cap is reached, so the tap handler can show the slot-full warning.
class _BookmarkLimitException implements Exception {}

class _ReadBookmarkButtonState extends State<_ReadBookmarkButton> {
  static const _freeLimit = 15;
  bool _saved = false;
  bool _busy = false;
  bool _spinning = false;

  /// Mirrors React's bookmarkDocId(): `read__<safeSegment(refId)>`.
  String get _docId {
    var ref = '${widget.chapterId}:${widget.question.id}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ref.length > 90) ref = ref.substring(0, 90);
    if (ref.isEmpty) ref = 'item';
    return 'read__$ref';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (widget.uid.isEmpty) return;
    try {
      final idToken = await AuthService.getValidIdToken();
      final doc = await FirestoreRest.getDocument(
          'users/${widget.uid}/bookmarks/$_docId',
          idToken: idToken);
      if (mounted) setState(() => _saved = doc != null);
    } catch (_) {}
  }

  /// Save tap UX (mirrors the practice screen): the icon flips to bookmarked
  /// immediately, a spinner sits on the icon for 2 seconds, then the success
  /// toast appears. The real Firestore write runs fire-and-forget; a later
  /// failure reverts the icon and shows an error toast.
  Future<void> _toggle() async {
    if (_busy || widget.uid.isEmpty) return;
    if (_saved) {
      await _remove();
      return;
    }
    setState(() {
      _busy = true;
      _spinning = true;
      _saved = true; // optimistic
    });
    var settled = false;
    unawaited(_save().then((_) {
      // Success: nothing extra — the timer below ends the spinner.
    }).catchError((Object e) {
      if (!mounted) return;
      settled = true;
      setState(() {
        _saved = false; // revert icon on failure
        _busy = false;
        _spinning = false;
      });
      showToast(
        context,
        e is _BookmarkLimitException
            ? 'Bookmark slots are full'
            : 'Could not update the bookmark. Please try again.',
        e is _BookmarkLimitException
            ? ToastVariant.warning
            : ToastVariant.error,
      );
    }));
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || settled) return;
    setState(() {
      _busy = false;
      _spinning = false;
    });
    if (_saved) {
      showToast(context, 'Saved to bookmarks.', ToastVariant.success);
    }
  }

  /// Fire-and-forget Firestore write for the optimistic save above.
  /// Same doc-id scheme and payload as before — UX layer only.
  Future<void> _save() async {
    final idToken = await AuthService.getValidIdToken();
    final path = 'users/${widget.uid}/bookmarks/$_docId';
    final rows = await FirestoreRest.listDocuments(
        'users/${widget.uid}/bookmarks',
        idToken: idToken);
    if (rows.length >= _freeLimit && !widget.isPro) {
      throw _BookmarkLimitException();
    }
    final q = widget.question;
    final questionTitle = bilingual(q.text, q.textNe);
    final explanationText = bilingual(q.explanation, q.explanationNe);
    final chapterName =
        (widget.chapterName ?? '').isNotEmpty ? widget.chapterName! : 'Chapter';
    await FirestoreRest.setDocument(
      path,
      {
        'context': 'read',
        'kind': 'question',
        'type': 'question',
        'refId': '${widget.chapterId}:${q.id}',
        'title': questionTitle,
        'preview': explanationText,
        'sourceLabel':
            '${(widget.subjectName ?? '').isNotEmpty ? widget.subjectName : 'Read Mode'} · $chapterName',
        'courseId': widget.courseId,
        'subcourseId': widget.subcourseId,
        'payload': {
          'question': questionTitle,
          'options': q.options,
          'answerIndex': q.correctIndex,
          'explanation': explanationText,
          'meta': [
            {'label': 'Read Mode', 'value': chapterName},
          ],
        },
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      idToken: idToken,
    );
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument(
          'users/${widget.uid}/bookmarks/$_docId',
          idToken: idToken);
      if (!mounted) return;
      setState(() {
        _saved = false;
        _busy = false;
      });
      showToast(context, 'Bookmark removed.', ToastVariant.info);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(
          context,
          'Could not update the bookmark. Please try again.',
          ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final showSpinner = _spinning || (_busy && _saved);
    return SizedBox(
      width: 30,
      height: 30,
      child: InkWell(
        onTap: _busy ? null : _toggle,
        borderRadius: BorderRadius.circular(15),
        child: Tooltip(
          message: _saved ? 'Remove bookmark' : 'Bookmark',
          child: showSpinner
              ? Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: palette.primary),
                  ),
                )
              : Icon(
                  _saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  size: 18,
                  color: _saved
                      ? palette.primary
                      : palette.textSecondary,
                ),
        ),
      ),
    );
  }
}
