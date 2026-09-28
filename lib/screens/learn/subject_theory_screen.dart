import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Subject theory mode — exact port of app/subjects/theory.tsx.
/// Hero card with bilingual title + PDF resource card; opening the PDF
/// marks the chapter as studied (tracked once on leave).
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
    final title = bilingual(
      '${_theory?['title'] ?? ''}'.isNotEmpty
          ? '${_theory?['title']}'
          : _chapterName,
      '${_theory?['titleNe'] ?? ''}',
    );
    context.push(
      '/pdf/${Uri.encodeComponent('${_theory?['id'] ?? widget.chapterId}')}' 
      '?uri=${Uri.encodeComponent(pdfUrl)}'
      '&title=${Uri.encodeComponent(title)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Something went wrong.'),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                  onPressed: _load,
                                  child: const Text('Retry')),
                            ],
                          ),
                        )
                      : (!isPublished)
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Theory resource is not available for this chapter yet.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$_chapterName · $_subjectName',
                                      style: TextStyle(
                                          color: theme
                                              .colorScheme.onSurface
                                              .withValues(alpha: 0.6)),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _content(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemeData theme) {
    final t = _theory!;
    final pdfUrl = '${t['pdfUrl'] ?? ''}';
    final title = bilingual(
      '${t['title'] ?? ''}'.isNotEmpty
          ? '${t['title']}'
          : _chapterName,
      '${t['titleNe'] ?? ''}',
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // hero card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      const Color(0xFF1D4ED8).withValues(alpha: 0.08),
                ),
                child: const Icon(Icons.school_outlined,
                    size: 30, color: Color(0xFF1D4ED8)),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                '$_chapterName · $_subjectName',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // PDF resource card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Theory Resource',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      pdfUrl.isNotEmpty
                          ? 'Theory resource is ready for this chapter.'
                          : 'Theory resource is not available for this chapter yet.',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              Icon(
                pdfUrl.isNotEmpty
                    ? Icons.attach_file_outlined
                    : Icons.description_outlined,
                size: 28,
                color: pdfUrl.isNotEmpty
                    ? const Color(0xFF1D4ED8)
                    : theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (pdfUrl.isNotEmpty)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open Theory PDF'),
            onPressed: _openPdf,
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}
