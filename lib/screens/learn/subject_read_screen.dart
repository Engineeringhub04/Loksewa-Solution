import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Subject read mode — exact port of app/subjects/read.tsx.
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
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError
                      ? _errorState()
                      : _questions.isEmpty
                          ? _emptyState()
                          : _mainList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Something went wrong.'),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Read-mode questions are not available for this chapter yet. Content is being prepared and will be added soon.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _mainList() {
    final theme = Theme.of(context);
    final allExpanded =
        _questions.isNotEmpty && _questions.every((q) => _expanded.contains(q.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Section header: Important Questions + expand/collapse all
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color:
                      const Color(0xFF1D4ED8).withValues(alpha: 0.08),
                ),
                child: const Icon(Icons.bookmark,
                    size: 22, color: Color(0xFF1D4ED8)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Important Questions',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.35)),
                    Text(
                      (widget.chapterName ?? '').isNotEmpty
                          ? widget.chapterName!
                          : 'Chapter',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                          height: 1.55),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: allExpanded ? _collapseAll : _expandAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          allExpanded
                              ? Icons.keyboard_arrow_up_outlined
                              : Icons.keyboard_arrow_down_outlined,
                          size: 19,
                          color: const Color(0xFF1D4ED8)),
                      const SizedBox(width: 4),
                      Text(
                          allExpanded
                              ? 'Collapse All'
                              : 'Expand All',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2559C7),
                              height: 1.3),
                          textAlign: TextAlign.right),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Question cards
        ..._questions.asMap().entries.map((entry) {
          final index = entry.key;
          final q = entry.value;
          final isOpen = _expanded.contains(q.id);
          final difficultyColor = q.difficulty == 'easy'
              ? const Color(0xFF059669)
              : q.difficulty == 'medium'
                  ? const Color(0xFFD97706)
                  : const Color(0xFFDC2626);
          final difficultyLabel = q.difficulty.isEmpty
              ? ''
              : q.difficulty[0].toUpperCase() +
                  q.difficulty.substring(1);
          final title = bilingual(q.text, q.textNe);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0xFF1D4ED8)
                              .withValues(alpha: 0.08),
                        ),
                        child: Text('Qn. ${index + 1}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1D4ED8))),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: difficultyColor
                              .withValues(alpha: 0.09),
                        ),
                        child: Text(difficultyLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: difficultyColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.33)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _toggle(q.id),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                              isOpen
                                  ? Icons
                                      .keyboard_arrow_up_outlined
                                  : Icons
                                      .keyboard_arrow_down_outlined,
                              size: 24,
                              color: const Color(0xFF1D4ED8)),
                          const SizedBox(width: 8),
                          Text(
                              isOpen
                                  ? 'Collapse answer'
                                  : 'Tap to show answer',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D4ED8))),
                        ],
                      ),
                    ),
                  ),
                  if (isOpen) ...[
                    const SizedBox(height: 8),
                    ...q.options.asMap().entries.map((opt) {
                      final correct = opt.key == q.correctIndex;
                      final border = correct
                          ? const Color(0x80059669)
                          : theme.dividerColor;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          constraints: const BoxConstraints(
                              minHeight: 53),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                            border: Border.all(color: border),
                            borderRadius: BorderRadius.circular(10),
                            color: correct
                                ? const Color(0x12059669)
                                : theme.cardColor,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 29,
                                height: 29,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: border, width: 1.4),
                                  color: correct
                                      ? const Color(0xFF059669)
                                      : Colors.transparent,
                                ),
                                child: Text(
                                    String.fromCharCode(
                                        65 + opt.key),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.bold,
                                        color: correct
                                            ? Colors.white
                                            : theme
                                                .colorScheme.onSurface
                                                .withValues(
                                                    alpha: 0.6))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(opt.value,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.36)),
                              ),
                              if (correct)
                                const Icon(Icons.check_circle,
                                    size: 20,
                                    color: Color(0xFF059669)),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0x55D97706)),
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0x12D97706),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.lightbulb_outline,
                                  size: 22,
                                  color: Color(0xFFD97706)),
                              SizedBox(width: 8),
                              Text('Explanation',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFD97706))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                              bilingual(
                                  q.explanation, q.explanationNe),
                              style: const TextStyle(
                                  fontSize: 14, height: 1.43)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 32),
      ],
    );
  }
}
