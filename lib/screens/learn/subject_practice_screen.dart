import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Subject practice mode — React parity port of app/subjects/practice.tsx.
///
/// UI mirrors the React screen section by section: daily-limit row, question
/// badge + bookmark/report actions, question card with difficulty pill, option
/// tiles (default / selected / correct / wrong), explanation panel, curved
/// bottom Previous/Next bar, and the AppDialog-style popups (daily-limit,
/// all-questions-complete, pause/leave). Question changes animate with a
/// fade + slight slide. Text sizes are scaled ~1-2px below the old design.
///
/// Business logic (question fetching, daily-limit gating, premium caps,
/// per-question lock-in, Firestore progress sync) is unchanged.
class SubjectPracticeScreen extends StatefulWidget {
  final String subjectId;
  final String chapterId;
  final String? unitId;
  final String courseId;
  final String subcourseId;
  final String? subjectName;
  final String? chapterName;
  final String? unitName;
  final String subjectPro;
  final String chapterPro;

  const SubjectPracticeScreen({
    super.key,
    required this.subjectId,
    required this.chapterId,
    this.unitId,
    this.courseId = '',
    this.subcourseId = '',
    this.subjectName,
    this.chapterName,
    this.unitName,
    this.subjectPro = '',
    this.chapterPro = '',
  });

  @override
  State<SubjectPracticeScreen> createState() =>
      _SubjectPracticeScreenState();
}

class _SubjectPracticeScreenState extends State<SubjectPracticeScreen> {
  List<SubjectQuestion> _questions = [];
  Map<String, dynamic>? _progress;
  bool _loading = true;
  bool _loadError = false;
  int _current = 0;
  Map<String, int> _selectedAnswers = {};
  bool _showLimit = false;
  bool _showWaiting = false;
  bool _showLeaveConfirm = false;

  /// True while any popup modal is open — the system back button then
  /// dismisses the popup instead of leaving the page.
  bool get _dialogOpen => _showLimit || _showWaiting || _showLeaveConfirm;
  bool _hasSpecificAccess = false;
  bool _profilePremium = false;
  // +1 when moving to the next question, -1 for previous — drives the
  // question transition direction.
  int _slideDir = 0;
  final ScrollController _scrollController = ScrollController();

  String get _unitId => widget.unitId ?? '';
  bool get _premiumContent =>
      widget.subjectPro == 'true' || widget.chapterPro == 'true';
  bool get _premium => _profilePremium || _hasSpecificAccess;
  bool get _proSubjectActive => _profilePremium && _premiumContent;

  int get _dailyUsed =>
      ((_progress?['dailyAttemptedQuestionIds'] as List?) ?? []).length;
  int get _dailyLimit {
    final len = _questions.length;
    return _premium
        ? (len < 100 ? len : 100)
        : (len < 30 ? len : 30);
  }

  SubjectQuestion? get _currentQuestion =>
      _questions.isEmpty ? null : _questions[_current];
  int? get _currentSelected => _currentQuestion == null
      ? null
      : _selectedAnswers[_currentQuestion!.id];
  bool get _currentAttempted => _currentQuestion != null &&
      ((_progress?['dailyAttemptedQuestionIds'] as List?) ?? [])
          .contains(_currentQuestion!.id);
  bool get _currentCorrect => _currentQuestion != null &&
      ((_progress?['dailyCorrectQuestionIds'] as List?) ?? [])
          .contains(_currentQuestion!.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      _profilePremium = _hasActivePremium(userDoc);

      final allQuestions = await fetchPracticeQuestionSet(
        courseId: widget.courseId.isEmpty
            ? 'civil-engineering'
            : widget.courseId,
        subcourseId: widget.subcourseId.isEmpty
            ? 'civil-assistant-sub-engineer'
            : widget.subcourseId,
        subjectId: widget.subjectId,
        unitId: _unitId.isEmpty ? null : _unitId,
        chapterId: widget.chapterId,
      );
      final stored = await fetchLearningProgress(
          user.uid, widget.subjectId, widget.chapterId);
      final purchases = await fetchMyContentPurchases(user.uid)
          .catchError((_) => <Map<String, dynamic>>[]);
      final specificAccess = purchases.any((p) =>
          p['status'] == 'active' &&
          ((p['contentType'] == 'chapter' &&
                  p['contentId'] == widget.chapterId) ||
              (p['contentType'] == 'subject' &&
                  p['contentId'] == widget.subjectId)));
      final premiumForLoad = _profilePremium || specificAccess;
      _hasSpecificAccess = specificAccess;
      final questions = shuffleList(
        premiumForLoad
            ? allQuestions.take(100).toList()
            : allQuestions.toList(),
      );
      final today = localDayKey();
      Map<String, dynamic> next;
      if (stored != null) {
        if (stored['dailyDate'] == today) {
          next = Map<String, dynamic>.from(stored);
        } else {
          next = {
            ...stored,
            'dailyDate': today,
            'dailyQuestionIds': <String>[],
            'dailyAttemptedQuestionIds': <String>[],
            'dailyCorrectQuestionIds': <String>[],
            'selectedAnswerIndexes': <String, int>{},
          };
        }
      } else {
        next = {
          'subjectId': widget.subjectId,
          'unitId': _unitId.isEmpty ? null : _unitId,
          'chapterId': widget.chapterId,
          'courseId': widget.courseId,
          'subcourseId': widget.subcourseId,
          'attemptedQuestionIds': <String>[],
          'correctQuestionIds': <String>[],
          'totalQuestions': questions.length,
          'bookmarked': false,
          'completed': false,
          'lastMode': 'practice',
          'dailyDate': today,
          'dailyQuestionIds': <String>[],
          'dailyAttemptedQuestionIds': <String>[],
          'dailyCorrectQuestionIds': <String>[],
          'selectedAnswerIndexes': <String, int>{},
        };
      }
      if (stored != null && stored['dailyDate'] != today) {
        unawaited(saveLearningProgress(
          user.uid,
          subjectId: widget.subjectId,
          unitId: _unitId.isEmpty ? null : _unitId,
          chapterId: widget.chapterId,
          courseId: widget.courseId,
          subcourseId: widget.subcourseId,
          dailyDate: today,
          dailyQuestionIds: [],
          dailyAttemptedQuestionIds: [],
          dailyCorrectQuestionIds: [],
          selectedAnswerIndexes: {},
          lastMode: 'practice',
        ));
      }
      setState(() {
        _questions = questions;
        _progress = next;
        _selectedAnswers = Map<String, int>.from(
            (next['selectedAnswerIndexes'] as Map?) ?? {});
        _current = 0;
        _slideDir = 0;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  static bool _hasActivePremium(Map<String, dynamic>? userDoc) {
    final pro = userDoc?['pro'];
    if (pro is bool) return pro;
    if (pro is Map) {
      final active = pro['active'];
      if (active is bool) return active;
      final exp = pro['expiresAt'];
      if (exp is String) {
        final dt = DateTime.tryParse(exp);
        if (dt != null) return dt.isAfter(DateTime.now());
      }
    }
    return false;
  }

  Future<void> _persist(Map<String, dynamic> next) async {
    setState(() => _progress = next);
    final user = AuthService.currentUser;
    if (user == null) return;
    try {
      await saveLearningProgress(
        user.uid,
        subjectId: widget.subjectId,
        unitId: _unitId.isEmpty ? null : _unitId,
        chapterId: widget.chapterId,
        courseId: widget.courseId,
        subcourseId: widget.subcourseId,
        attemptedQuestionIds:
            List<String>.from(next['attemptedQuestionIds'] ?? []),
        correctQuestionIds:
            List<String>.from(next['correctQuestionIds'] ?? []),
        completed: next['completed'] == true,
        lastMode: 'practice',
        dailyDate: next['dailyDate'] as String?,
        dailyQuestionIds:
            List<String>.from(next['dailyQuestionIds'] ?? []),
        dailyAttemptedQuestionIds:
            List<String>.from(next['dailyAttemptedQuestionIds'] ?? []),
        dailyCorrectQuestionIds:
            List<String>.from(next['dailyCorrectQuestionIds'] ?? []),
        selectedAnswerIndexes:
            Map<String, int>.from(next['selectedAnswerIndexes'] ?? {}),
        totalQuestions: _questions.length,
      );
    } catch (_) {}
  }

  void _selectOption(int optionIndex) {
    final q = _currentQuestion;
    final base = _progress;
    if (q == null || base == null) return;
    if (!_premium && _dailyUsed >= _dailyLimit && !_currentAttempted) {
      setState(() => _showLimit = true);
      return;
    }
    if (_currentAttempted) return;
    final isCorrect = optionIndex == q.correctIndex;
    final attempted = <String>{
      ...List<String>.from(base['attemptedQuestionIds'] ?? []),
      q.id
    }.toList();
    final correct = isCorrect
        ? <String>{
            ...List<String>.from(base['correctQuestionIds'] ?? []),
            q.id
          }.toList()
        : List<String>.from(base['correctQuestionIds'] ?? []);
    final dailyAttempted = <String>{
      ...List<String>.from(base['dailyAttemptedQuestionIds'] ?? []),
      q.id
    }.toList();
    final dailyCorrect = isCorrect
        ? <String>{
            ...List<String>.from(base['dailyCorrectQuestionIds'] ?? []),
            q.id
          }.toList()
        : List<String>.from(base['dailyCorrectQuestionIds'] ?? []);
    final nextSelected = {..._selectedAnswers, q.id: optionIndex};
    setState(() => _selectedAnswers = nextSelected);
    final limit = _premium
        ? (_questions.length < 100 ? _questions.length : 100)
        : _dailyLimit;
    final next = {
      ...base,
      'selectedAnswerIndexes': nextSelected,
      'attemptedQuestionIds': attempted,
      'correctQuestionIds': correct,
      'dailyDate': localDayKey(),
      'dailyQuestionIds': List<String>.from(base['dailyQuestionIds'] ?? []),
      'dailyAttemptedQuestionIds': dailyAttempted,
      'dailyCorrectQuestionIds': dailyCorrect,
      'totalQuestions': _questions.length,
      'completed': dailyAttempted.length >= limit,
      'lastMode': 'practice',
    };
    _persist(next);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
    if (!_premium && dailyAttempted.length >= _dailyLimit) {
      setState(() => _showLimit = true);
    }
  }

  void _goToQuestion(int delta) {
    final next = _current + delta;
    if (next < 0 || next >= _questions.length) return;
    setState(() {
      _slideDir = delta > 0 ? 1 : -1;
      _current = next;
    });
  }

  void _onNext() {
    if (_current == _questions.length - 1) {
      if (_proSubjectActive) {
        setState(() => _showWaiting = true);
      } else {
        setState(() => _showLimit = true);
      }
      return;
    }
    _goToQuestion(1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final hasContent = !_loading && !_loadError && _questions.isNotEmpty;
    // The dialogs sit on top of the whole Scaffold (Positioned.fill) so the
    // barrier dims the header and the bottom bar too — a Stack overlay inside
    // the body would leave the header bright and leak background slivers at
    // its curved corners in light mode.
    return PopScope(
      canPop: !_dialogOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_showLeaveConfirm) {
            setState(() => _showLeaveConfirm = false);
          } else if (_showWaiting) {
            setState(() => _showWaiting = false);
          } else if (_showLimit) {
            setState(() => _showLimit = false);
          }
        }
      },
      child: Stack(
        children: [
        Scaffold(
          backgroundColor: palette.background,
          body: Column(
            children: [
              SubpageHeader(
                title: 'Practice Mode',
                onBackPress: () =>
                    setState(() => _showLeaveConfirm = true),
              ),
              Expanded(
                child: _loading
                    ? const PreloadingWidget(
                        tinted: false,
                        label: 'Loading...',
                        hint: 'Fetching your content',
                      )
                    : _loadError
                        ? _errorState(palette)
                        : _questions.isEmpty
                            ? _emptyState(palette)
                            : _mainList(palette),
              ),
              if (hasContent) _bottomBar(palette),
            ],
          ),
        ),
        if (_showLimit)
          Positioned.fill(child: _limitDialog(palette)),
        if (_showWaiting)
          Positioned.fill(child: _waitingDialog(palette)),
        if (_showLeaveConfirm)
          Positioned.fill(child: _leaveDialog(palette)),
        ],
      ),
    );
  }

  /// Mirrors DataNotFound with a retry action.
  Widget _errorState(ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: palette.textDisabled),
            const SizedBox(height: 12),
            Text('Something went wrong',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _load,
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
                    Icon(Icons.refresh, size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Retry',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors DataNotFound with the no-questions copy (no retry — the content
  /// is being prepared, not failing to load).
  Widget _emptyState(ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: palette.textDisabled),
            const SizedBox(height: 12),
            Text('No questions are available for this chapter yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Practice questions are not available for this chapter yet. Content is being prepared and will be added soon.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _mainList(ExpoPalette palette) {
    final q = _currentQuestion!;
    final premium = _premium;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Daily-limit row.
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(
                color: premium ? palette.success : palette.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      premium
                          ? 'Pro access active'
                          : 'Daily limit reached: $_dailyUsed/$_dailyLimit',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: premium
                              ? palette.success
                              : palette.primary),
                    ),
                    if (!premium)
                      Text(
                        'New questions are selected after midnight.',
                        style: TextStyle(
                            fontSize: 10,
                            color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                  premium ? Icons.check_circle : Icons.speed,
                  size: 22,
                  color: premium ? palette.success : palette.primary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Question badge + bookmark/report actions.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: palette.primary.withValues(alpha: 0.08),
              ),
              child: Text('Question ${_current + 1}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: palette.primary)),
            ),
            Row(
              children: [
                _actionBox(
                  palette,
                  _PracticeBookmarkButton(
                    key: ValueKey('practice:${q.id}'),
                    uid: AuthService.currentUser?.uid ?? '',
                    chapterId: widget.chapterId,
                    question: q,
                    subjectName: widget.subjectName ?? '',
                    chapterName: widget.chapterName ?? '',
                    courseId: widget.courseId,
                    subcourseId: widget.subcourseId,
                    isPro: premium,
                  ),
                ),
                const SizedBox(width: 10),
                _actionBox(
                  palette,
                  IconButton(
                    onPressed: () =>
                        context.push('/settings/report-problem'),
                    icon: const Icon(Icons.flag_outlined, size: 22),
                    color: palette.textSecondary,
                    tooltip: 'Report',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Question + options + explanation, animated on question change.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder:
              (Widget child, Animation<double> animation) {
            final begin = Offset(0.05 * _slideDir, 0.015);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: begin, end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_current),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _questionCard(palette, q),
                const SizedBox(height: 12),
                ..._optionTiles(palette, q),
                if (_currentAttempted) _explanationCard(palette, q),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// The 42x42 elevated action tile from practice.tsx (bookmark / report).
  Widget _actionBox(ExpoPalette palette, Widget child) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _questionCard(ExpoPalette palette, SubjectQuestion q) {
    final diffColor = q.difficulty == 'easy'
        ? palette.success
        : q.difficulty == 'medium'
            ? palette.warning
            : palette.danger;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bilingual(q.text, q.textNe),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.35)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: diffColor.withValues(
                  alpha: q.difficulty == 'medium' ? 0.12 : 0.09),
            ),
            child: Text(q.difficulty.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: diffColor)),
          ),
        ],
      ),
    );
  }

  List<Widget> _optionTiles(ExpoPalette palette, SubjectQuestion q) {
    return List.generate(q.options.length, (index) {
      final isSelected = _currentSelected == index;
      final isCorrect = index == q.correctIndex;
      final showResult = _currentAttempted;
      final border = showResult && isCorrect
          ? palette.success
          : showResult && isSelected && !isCorrect
              ? palette.danger
              : isSelected
                  ? palette.primary
                  : palette.border;
      final background = showResult && isCorrect
          ? palette.success.withValues(alpha: 0.08)
          : showResult && isSelected && !isCorrect
              ? palette.danger.withValues(alpha: 0.08)
              : palette.surface;
      final filled = isSelected || (showResult && isCorrect);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selectOption(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 66),
              padding: const EdgeInsets.symmetric(
                  horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: border, width: 1.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: border, width: 1.5),
                      color: filled ? border : Colors.transparent,
                    ),
                    child: Text(
                        String.fromCharCode(65 + index),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: filled
                                ? Colors.white
                                : palette.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(q.options[index],
                        style: const TextStyle(
                            fontSize: 14, height: 1.33)),
                  ),
                  if (showResult && isCorrect)
                    Icon(Icons.check_circle,
                        size: 22, color: palette.success)
                  else if (showResult && isSelected)
                    Icon(Icons.cancel,
                        size: 22, color: palette.danger),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _explanationCard(ExpoPalette palette, SubjectQuestion q) {
    final ok = _currentCorrect;
    final tone = ok ? palette.success : palette.danger;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: tone.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
        color: tone.withValues(alpha: ok ? 0.06 : 0.035),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone,
                ),
                child: Icon(
                    ok ? Icons.check : Icons.close,
                    size: 22,
                    color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ok ? 'Correct Answer' : 'Incorrect Answer',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tone)),
                    Text(
                        ok
                            ? 'Your answer is correct.'
                            : 'The selected option is incorrect.',
                        style: TextStyle(
                            fontSize: 10,
                            color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 10),
              color: tone.withValues(alpha: 0.2)),
          if (_currentSelected != null) ...[
            Text('Selected option: ${q.options[_currentSelected!]}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tone)),
            const SizedBox(height: 8),
          ],
          if (!ok) ...[
            Text('Correct option: ${q.options[q.correctIndex]}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.success)),
            const SizedBox(height: 8),
          ],
          const Text('Explanation',
              style:
                  TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(bilingual(q.explanation, q.explanationNe),
              style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: palette.textSecondary)),
        ],
      ),
    );
  }

  /// Bottom Previous/Next bar — a slightly curved card (rounded top corners)
  /// rather than React's full-bleed square bar.
  Widget _bottomBar(ExpoPalette palette) {
    final isLast = _current == _questions.length - 1;
    final nextDisabled =
        !_premium && _dailyUsed >= _dailyLimit && !_currentAttempted;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: palette.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              flex: 85,
              child: Opacity(
                opacity: _current == 0 ? 0.45 : 1,
                child: _barButton(
                  palette: palette,
                  filled: false,
                  onTap:
                      _current == 0 ? null : () => _goToQuestion(-1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back,
                          size: 19, color: palette.primary),
                      const SizedBox(width: 7),
                      Text('Previous',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: palette.primary)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 135,
              child: _barButton(
                palette: palette,
                filled: true,
                onTap: nextDisabled ? null : _onNext,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        isLast
                            ? (_proSubjectActive
                                ? 'Waiting For New Question Upload'
                                : 'Your Daily Practice limit is reached')
                            : 'Next Question',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.35),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Icon(Icons.arrow_forward,
                        size: 19, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barButton({
    required ExpoPalette palette,
    required bool filled,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Material(
      color: filled ? palette.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled ? null : Border.all(color: palette.border),
          ),
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- dialogs
  // Mirrors React's AppDialog shell (src/components/feedback/AppDialog.tsx):
  // full-screen overlay barrier, 26px rounded card with a gradient cap,
  // scrollable body, and a footer where Cancel is visually secondary to the
  // gradient Confirm. The card is clipped as one rounded shape so no
  // background slivers leak at the corners in light mode.

  /// Slightly darker companion for an accent, so the cap reads as a gradient.
  Color _darken(Color color) {
    int channel(double v) => (v * 0.72).round().clamp(0, 255);
    return Color.fromARGB(
      (color.a * 255).round(),
      channel(color.r),
      channel(color.g),
      channel(color.b),
    );
  }

  Widget _appDialog({
    required ExpoPalette palette,
    required Color accent,
    required IconData icon,
    required String tagline,
    required String title,
    required String message,
    Widget? bodyExtra,
    required String confirmLabel,
    IconData? confirmIcon,
    String? cancelLabel,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final darker = _darken(accent);
    return _FadeIn(
      child: Container(
        color: isDark
            ? Colors.black.withValues(alpha: 0.6)
            : const Color(0x800F172A),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    color: palette.surface,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        // Gradient header — FeedSpring onboarding style.
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accent, darker],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Decorative white circles.
                              Positioned(
                                top: -50,
                                right: -40,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white
                                        .withValues(alpha: 0.14),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: -46,
                                left: -38,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white
                                        .withValues(alpha: 0.14),
                                  ),
                                ),
                              ),
                              // Close X, top-right.
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Material(
                                  color: Colors.white
                                      .withValues(alpha: 0.22),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    onTap: onCancel,
                                    child: const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: Icon(Icons.close,
                                          size: 16,
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              // Centered column: icon tile, tagline pill, title.
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    28, 30, 28, 26),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(
                                                18),
                                        color: Colors.white
                                            .withValues(
                                                alpha: 0.22),
                                      ),
                                      child: Icon(icon,
                                          size: 28,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 12,
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(
                                                999),
                                      ),
                                      child: Text(
                                        tagline,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.bold,
                                          letterSpacing: 0.8,
                                          color: darker,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Body.
                        Container(
                          color: palette.surface,
                          padding: const EdgeInsets.fromLTRB(
                              20, 18, 20, 8),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.55,
                                  color: palette.textSecondary,
                                ),
                              ),
                              if (bodyExtra != null) ...[
                                const SizedBox(height: 10),
                                bodyExtra,
                              ],
                            ],
                          ),
                        ),
                        // Buttons — stacked full-width.
                        Container(
                          color: palette.surface,
                          padding: const EdgeInsets.fromLTRB(
                              20, 10, 20, 20),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              // Cancel.
                              if (cancelLabel != null) ...[
                                Material(
                                  color: Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius:
                                        BorderRadius.circular(
                                            16),
                                    onTap: onCancel,
                                    child: Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          vertical: 14),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.06)
                                            : Colors.white,
                                        border: Border.all(
                                            color:
                                                palette.border,
                                            width: 1.5),
                                        borderRadius:
                                            BorderRadius.circular(
                                                16),
                                        boxShadow: isDark
                                            ? null
                                            : [
                                                BoxShadow(
                                                  color: Colors
                                                      .black
                                                      .withValues(
                                                          alpha:
                                                              0.06),
                                                  blurRadius: 8,
                                                  offset:
                                                      const Offset(
                                                          0, 3),
                                                ),
                                              ],
                                      ),
                                      child: Text(
                                        cancelLabel,
                                        textAlign:
                                            TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight:
                                                FontWeight.bold,
                                            color: palette
                                                .textPrimary),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                                const SizedBox(height: 10),
                              // Confirm.
                              Material(
                                color: Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  onTap: onConfirm,
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 15),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(
                                              16),
                                      gradient: LinearGradient(
                                        colors: [
                                          accent,
                                          darker
                                        ],
                                        begin:
                                            Alignment.centerLeft,
                                        end:
                                            Alignment.centerRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withValues(
                                              alpha: 0.4),
                                          blurRadius: 12,
                                          offset: const Offset(
                                              0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      alignment:
                                          Alignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                            if (confirmIcon !=
                                                null) ...[
                                              Icon(confirmIcon,
                                                  size: 18,
                                                  color: Colors
                                                      .white),
                                              const SizedBox(
                                                  width: 8),
                                            ],
                                            Flexible(
                                              child: Text(
                                                confirmLabel,
                                                textAlign: TextAlign
                                                    .center,
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight
                                                            .bold,
                                                    color: Colors
                                                        .white),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Positioned(
                                          right: 12,
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration:
                                                const BoxDecoration(
                                              shape:
                                                  BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                            child: Icon(
                                              Icons.arrow_forward,
                                              size: 16,
                                              color: darker,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _limitDialog(ExpoPalette palette) => _appDialog(
        palette: palette,
        accent: const Color(0xFFD97706),
        icon: Icons.diamond,
        tagline: 'Daily Limit',
        title: 'Your Daily Practice limit is reached',
        message:
            'You have completed today\u2019s practice limit for this chapter.',
        bodyExtra: Text(
          'To Crack Your Daily Limit! Subscribe to Our Pro Plan',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 11, color: palette.textSecondary),
        ),
        confirmLabel: 'Subscription',
        confirmIcon: Icons.diamond_outlined,
        cancelLabel: 'Close',
        onConfirm: () {
          setState(() => _showLimit = false);
          context.push('/subscription');
        },
        onCancel: () => setState(() => _showLimit = false),
      );

  Widget _waitingDialog(ExpoPalette palette) => _appDialog(
        palette: palette,
        accent: const Color(0xFF2563EB),
        icon: Icons.done_all,
        tagline: 'All Complete',
        title: 'All Available Questions Completed',
        message:
            'You have practiced all currently available questions for this premium chapter. New questions will appear when they are uploaded.',
        confirmLabel: 'OK',
        cancelLabel: null,
        onConfirm: () => setState(() => _showWaiting = false),
        onCancel: () => setState(() => _showWaiting = false),
      );

  Widget _leaveDialog(ExpoPalette palette) => _appDialog(
        palette: palette,
        accent: const Color(0xFF2563EB),
        icon: Icons.pause_circle_outline,
        tagline: 'Pause Practice',
        title: 'Pause Your Progress?',
        message:
            'Your completed answers are safely stored. You can return whenever you are ready.',
        bodyExtra: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: palette.success.withValues(alpha: 0.33)),
            color: palette.success.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_done_outlined,
                  size: 19, color: palette.success),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Progress synced in the background',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: palette.success),
                ),
              ),
            ],
          ),
        ),
        confirmLabel: 'Leave Practice',
        cancelLabel: 'Keep Practicing',
        onConfirm: () {
          setState(() => _showLeaveConfirm = false);
          context.pop();
        },
        onCancel: () => setState(() => _showLeaveConfirm = false),
      );
}

/// Fade-in wrapper for the dialog overlay — mirrors AppDialog's
/// FadeIn.duration(200) entrance.
class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: widget.child,
    );
  }
}

/// Per-question bookmark toggle — the Flutter equivalent of React's
/// BookmarkButton (context "practice", kind "question",
/// refId "${chapterId}:${questionId}"). Bookmarks live at
/// users/{uid}/bookmarks with the same doc-id scheme as the Expo app
/// (`practice__<ref>`), so the Bookmarks screen lists them without changes.
class _PracticeBookmarkButton extends StatefulWidget {
  final String uid;
  final String chapterId;
  final SubjectQuestion question;
  final String subjectName;
  final String chapterName;
  final String courseId;
  final String subcourseId;
  final bool isPro;

  const _PracticeBookmarkButton({
    super.key,
    required this.uid,
    required this.chapterId,
    required this.question,
    required this.subjectName,
    required this.chapterName,
    required this.courseId,
    required this.subcourseId,
    required this.isPro,
  });

  @override
  State<_PracticeBookmarkButton> createState() =>
      _PracticeBookmarkButtonState();
}

class _PracticeBookmarkButtonState
    extends State<_PracticeBookmarkButton> {
  static const _freeLimit = 15;
  bool _saved = false;
  bool _busy = false;

  String get _refId => '${widget.chapterId}:${widget.question.id}';

  /// Mirrors React's bookmarkDocId(): `practice__<safeSegment(refId)>`.
  String get _docId {
    var ref = _refId
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ref.length > 90) ref = ref.substring(0, 90);
    if (ref.isEmpty) ref = 'item';
    return 'practice__$ref';
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
        idToken: idToken,
      );
      if (mounted) setState(() => _saved = doc != null);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_busy || widget.uid.isEmpty) return;
    setState(() => _busy = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      final path = 'users/${widget.uid}/bookmarks/$_docId';
      if (_saved) {
        await FirestoreRest.deleteDocument(path, idToken: idToken);
        if (!mounted) return;
        setState(() {
          _saved = false;
          _busy = false;
        });
        showToast(context, 'Bookmark removed.', ToastVariant.info);
        return;
      }
      final rows = await FirestoreRest.listDocuments(
        'users/${widget.uid}/bookmarks',
        idToken: idToken,
      );
      // Free-tier cap: 15 bookmarks per sub-course (React parity).
      final scoped = widget.subcourseId.isEmpty
          ? rows.length
          : rows
              .where((r) =>
                  (r['subcourseId'] ?? '') == widget.subcourseId)
              .length;
      if (scoped >= _freeLimit && !widget.isPro) {
        if (!mounted) return;
        setState(() => _busy = false);
        showToast(context, 'Bookmark limit reached for this sub-course',
            ToastVariant.warning);
        return;
      }
      final q = widget.question;
      final sourceLabel = [
        if (widget.subjectName.isNotEmpty)
          widget.subjectName
        else
          'Practice Mode',
        if (widget.chapterName.isNotEmpty) widget.chapterName,
      ].join(' · ');
      await FirestoreRest.setDocument(
        path,
        {
          'context': 'practice',
          'kind': 'question',
          'refId': _refId,
          'title': bilingual(q.text, q.textNe),
          'preview': bilingual(q.explanation, q.explanationNe),
          'sourceLabel': sourceLabel,
          'courseId': widget.courseId,
          'subcourseId': widget.subcourseId,
          'payload': {
            'question': bilingual(q.text, q.textNe),
            'options': q.options,
            'answerIndex': q.correctIndex,
            'explanation':
                bilingual(q.explanation, q.explanationNe),
            'meta': widget.chapterName.isNotEmpty
                ? [
                    {
                      'label': 'Chapter',
                      'value': widget.chapterName
                    }
                  ]
                : null,
          },
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        idToken: idToken,
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      showToast(context, 'Saved to bookmarks.', ToastVariant.success);
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
    return IconButton(
      onPressed: _busy ? null : _toggle,
      icon: Icon(
          _saved ? Icons.bookmark : Icons.bookmark_border,
          size: 22),
      color: _saved ? palette.primary : palette.textSecondary,
      tooltip: _saved ? 'Remove bookmark' : 'Bookmark',
      padding: EdgeInsets.zero,
      constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
