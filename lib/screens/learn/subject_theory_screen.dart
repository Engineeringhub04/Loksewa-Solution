import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/firestore_rest.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/subpage_header.dart';

/// Subject theory mode — exact port of app/subjects/theory.tsx.
///
/// Hero card (icon circle, bilingual title, chapter · subject line, bookmark
/// + report action row), PDF resource card, and the "Open Theory PDF"
/// primary button. Opening the PDF marks the chapter as studied
/// (tracked once on leave).
class SubjectTheoryScreen extends StatefulWidget {
  final String subjectId;
  final String chapterId;
  final String? unitId;
  final String courseId;
  final String subcourseId;
  final String? subjectName;
  final String? chapterName;
  final String? unitName;

  const SubjectTheoryScreen({
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
  State<SubjectTheoryScreen> createState() => _SubjectTheoryScreenState();
}

class _SubjectTheoryScreenState extends State<SubjectTheoryScreen> {
  Map<String, dynamic>? _theory;
  bool _loading = true;
  bool _loadError = false;

  // Progress-tracking refs (port of theory.tsx's refs).
  bool _openedPdf = false;
  late DateTime _openedAt;
  bool _recorded = false;

  String get _chapterName => widget.chapterName ?? widget.chapterId;
  String get _subjectName => widget.subjectName ?? widget.subjectId;

  String get _bilingualTitle {
    final t = _theory;
    final en = t == null ? _chapterName : '${t['title'] ?? ''}'.trim();
    final ne = t == null ? '' : '${t['titleNe'] ?? ''}'.trim();
    return bilingual(en.isNotEmpty ? en : _chapterName, ne);
  }

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
    if (_recorded) {
      return;
    }
    _recorded = true;
    final user = AuthService.currentUser;
    if (user == null) return;
    final seconds = DateTime.now().difference(_openedAt).inSeconds;
    if (user.uid.isEmpty ||
        widget.chapterId.isEmpty ||
        (!_openedPdf && seconds < 5)) {
      return;
    }
    recordActivityProgress(
      user.uid,
      source: 'theory',
      refId: widget.chapterId,
      courseId: widget.courseId,
      subcourseId: widget.subcourseId,
      totalItems: 1,
      secondsSpent: seconds,
      countVisit: true,
      completed: _openedPdf,
    );
    if (_openedPdf) recordAppActivity(user.uid);
  }

  Future<void> _load() async {
    final user = AuthService.currentUser;
    if (user == null || widget.subjectId.isEmpty || widget.chapterId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final theory = await fetchTheoryResource(
        widget.courseId.isEmpty ? 'civil-engineering' : widget.courseId,
        widget.subcourseId.isEmpty
            ? 'civil-assistant-sub-engineer'
            : widget.subcourseId,
        widget.subjectId,
        (widget.unitId ?? '').isEmpty ? null : widget.unitId,
        widget.chapterId,
      );
      setState(() {
        _theory = theory;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  void _openPdf() {
    final pdfUrl = _theory?['pdfUrl'] as String?;
    if (pdfUrl == null || pdfUrl.isEmpty) return;
    setState(() => _openedPdf = true);
    context.push(
      '/pdf/${Uri.encodeComponent('${_theory?['id'] ?? widget.chapterId}')}'
      '?uri=${Uri.encodeComponent(pdfUrl)}'
      '&title=${Uri.encodeComponent(_bilingualTitle)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPublished = _theory != null && _theory!['isPublished'] != false;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _recordProgress();
      },
      child: Scaffold(
        body: Column(
          children: [
            const SubpageHeader(title: 'Theory Mode'),
            Expanded(
              child: _loading
                  ? const PreloadingWidget(
                      tinted: false,
                      label: 'Loading...',
                      hint: 'Fetching your content',
                    )
                  : _loadError
                      ? _DataNotFound(
                          title: 'Something went wrong',
                          description:
                              'Please check your connection and try again.',
                          onRetry: _load,
                        )
                      : (!isPublished)
                          ? _DataNotFound(
                              title:
                                  'Theory resource is not available for this chapter yet.',
                              description:
                                  '$_chapterName · $_subjectName',
                            )
                          : _content(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final t = _theory!;
    final pdfUrl = '${t['pdfUrl'] ?? ''}';
    final bottomPad = MediaQuery.of(context).padding.bottom + 32;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      children: [
        _heroCard(theme),
        const SizedBox(height: 14),
        _pdfCard(theme, pdfUrl),
        if (pdfUrl.isNotEmpty) ...[
          const SizedBox(height: 14),
          _openButton(theme),
        ],
      ],
    );
  }

  /// Hero card — mirrors theory.tsx's heroCard: centered icon circle,
  /// bilingual title, chapter · subject line, bookmark + report actions.
  Widget _heroCard(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: 0.08),
              ),
              child:
                  Icon(Icons.school_outlined, size: 26, color: primary),
            ),
            const SizedBox(height: 8),
            Text(
              _bilingualTitle,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$_chapterName · $_subjectName',
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TheoryBookmarkButton(
                  uid: AuthService.currentUser?.uid ?? '',
                  chapterId: widget.chapterId,
                  title: _bilingualTitle,
                  preview: '$_chapterName · $_subjectName',
                  sourceLabel: 'Theory Mode · $_subjectName',
                  courseId: widget.courseId,
                  subcourseId: widget.subcourseId,
                  subjectName: _subjectName,
                ),
                const SizedBox(width: 5),
                _TheoryReportButton(
                  title: _bilingualTitle,
                  chapterId: widget.chapterId,
                  chapterName: _chapterName,
                  subjectName: _subjectName,
                  unitName: widget.unitName,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// PDF resource card — mirrors theory.tsx's pdfCard.
  Widget _pdfCard(ThemeData theme, String pdfUrl) {
    final primary = theme.colorScheme.primary;
    final secondary =
        theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final hasPdf = pdfUrl.isNotEmpty;
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theory Resource',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(
                    hasPdf
                        ? 'Theory resource is ready for this chapter.'
                        : 'Theory resource is not available for this chapter yet.',
                    style:
                        TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              hasPdf
                  ? Icons.attach_file_outlined
                  : Icons.description_outlined,
              size: 25,
              color: hasPdf ? primary : secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _openButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Open Theory PDF',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        onPressed: _openPdf,
      ),
    );
  }
}

/// Port of React's DataNotFound — cloud-off icon, centered title +
/// description, optional pill retry button.
class _DataNotFound extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback? onRetry;

  const _DataNotFound({
    required this.title,
    required this.description,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary =
        theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(21),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: secondary),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: TextStyle(fontSize: 13, color: secondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 15),
              ElevatedButton.icon(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                icon:
                    const Icon(Icons.refresh, size: 14, color: Colors.white),
                label: const Text('Try Again',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Port of React's BookmarkButton (context "chapter", kind "read",
/// refId "<chapterId>:theory"). Bookmarks live at users/{uid}/bookmarks
/// with the Expo doc-id scheme (`chapter__<safeSegment(refId)>`) so the
/// Bookmarks screen lists them without changes.
class _TheoryBookmarkButton extends StatefulWidget {
  final String uid;
  final String chapterId;
  final String title;
  final String preview;
  final String sourceLabel;
  final String courseId;
  final String subcourseId;
  final String subjectName;

  const _TheoryBookmarkButton({
    required this.uid,
    required this.chapterId,
    required this.title,
    required this.preview,
    required this.sourceLabel,
    required this.courseId,
    required this.subcourseId,
    required this.subjectName,
  });

  @override
  State<_TheoryBookmarkButton> createState() => _TheoryBookmarkButtonState();
}

class _TheoryBookmarkButtonState extends State<_TheoryBookmarkButton> {
  bool _saved = false;
  bool _busy = false;
  bool _spinning = false;

  /// Mirrors React's bookmarkDocId(): `chapter__<safeSegment(refId)>`.
  String get _docId {
    var ref = '${widget.chapterId}:theory'
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ref.length > 90) ref = ref.substring(0, 90);
    return 'chapter__${ref.isEmpty ? 'item' : ref}';
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

  /// Save tap UX (mirrors the read/practice screens): the icon flips to
  /// bookmarked immediately, a spinner sits on the icon for 2 seconds, then
  /// the success toast appears. The real Firestore write runs fire-and-forget;
  /// a later failure reverts the icon and shows an error toast.
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
    unawaited(_save().catchError((Object _) {
      if (!mounted) return;
      settled = true;
      setState(() {
        _saved = false; // revert icon on failure
        _busy = false;
        _spinning = false;
      });
      showToast(context, 'Could not save the bookmark.',
          ToastVariant.error);
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
    final refId = '${widget.chapterId}:theory';
    await FirestoreRest.setDocument(
      path,
      {
        'kind': 'read',
        'context': 'chapter',
        'type': 'chapter',
        'refId': refId,
        'title': widget.title,
        'preview': widget.preview,
        'sourceLabel': widget.sourceLabel,
        'courseId': widget.courseId,
        'subcourseId': widget.subcourseId,
        'payload': {
          'body': widget.preview,
          'meta': [
            {'label': 'Subject', 'value': widget.subjectName},
            {'label': 'Chapter', 'value': widget.chapterId},
          ],
        },
      },
      idToken: idToken,
      merge: true,
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
      showToast(context, 'Could not save the bookmark.',
          ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final showSpinner = _spinning || (_busy && _saved);
    return GestureDetector(
      onTap: _busy ? null : _toggle,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: showSpinner
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: primary),
              )
            : Icon(
                _saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded,
                size: 19,
                color: primary,
              ),
      ),
    );
  }
}

/// Report action on the theory screen — opens the shared ReportDialog
/// (mode 'theory') instead of the old bottom sheet.
class _TheoryReportButton extends StatelessWidget {
  final String title;
  final String chapterId;
  final String chapterName;
  final String subjectName;
  final String? unitName;

  const _TheoryReportButton({
    required this.title,
    required this.chapterId,
    required this.chapterName,
    required this.subjectName,
    this.unitName,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => ReportDialog.show(
        context: context,
        question: title,
        options: const [],
        questionId: chapterId,
        subject: subjectName,
        chapter: chapterName,
        unit: unitName,
        mode: 'theory',
      ),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: Icon(Icons.flag_rounded, size: 19, color: primary),
      ),
    );
  }
}
