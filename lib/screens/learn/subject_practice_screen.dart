import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/limit_dialog.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import 'package:loksewa_solution/widgets/report_dialog.dart';

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
    // Back to the top on every question change — otherwise the new question
    // would open scrolled down at the previous question's position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 56, color: palette.textDisabled),
            const SizedBox(height: 11),
            Text('Something went wrong',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text('Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text('Retry',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 56, color: palette.textDisabled),
            const SizedBox(height: 11),
            Text('No questions are available for this chapter yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text(
                'Practice questions are not available for this chapter yet. Content is being prepared and will be added soon.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 12)),
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
      padding: const EdgeInsets.all(14),
      children: [
        // Daily-limit row.
        Container(
          padding: const EdgeInsets.all(11),
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
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: premium
                              ? palette.success
                              : palette.primary),
                    ),
                    if (!premium)
                      Text(
                        'New questions are selected after midnight.',
                        style: TextStyle(
                            fontSize: 9,
                            color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                  premium ? Icons.check_circle : Icons.speed,
                  size: 19,
                  color: premium ? palette.success : palette.primary),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Question badge + bookmark/report actions.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: palette.primary.withValues(alpha: 0.08),
              ),
              child: Text('Question ${_current + 1}',
                  style: TextStyle(
                      fontSize: 10,
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
                const SizedBox(width: 8),
                _actionBox(
                  palette,
                  IconButton(
                    onPressed: () => ReportDialog.show(
                      context: context,
                      question: bilingual(q.text, q.textNe),
                      options: q.options,
                      questionId: q.id,
                      subject: widget.subjectName,
                      chapter: widget.chapterName,
                      unit: widget.unitName,
                      mode: 'practice',
                    ),
                    icon: const Icon(Icons.flag_rounded, size: 19),
                    color: palette.textSecondary,
                    tooltip: 'Report',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 34, minHeight: 34),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
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
                const SizedBox(height: 10),
                ..._optionTiles(palette, q),
                if (_currentAttempted) _explanationCard(palette, q),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  /// The 38x38 elevated action tile from practice.tsx (bookmark / report).
  Widget _actionBox(ExpoPalette palette, Widget child) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(18),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: diffColor.withValues(
                  alpha: q.difficulty == 'medium' ? 0.12 : 0.09),
            ),
            child: Text(q.difficulty.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
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
      // Keyed on the question id so each question change builds fresh tile
      // state and the stagger replays on every question.
      return _OptionStagger(
        key: ValueKey('${q.id}:$index'),
        index: index,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => _selectOption(index),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: border, width: 1.4),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 29,
                      height: 29,
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
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: filled
                                  ? Colors.white
                                  : palette.textSecondary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(q.options[index],
                          style: const TextStyle(
                              fontSize: 13, height: 1.33)),
                    ),
                    if (showResult && isCorrect)
                      Icon(Icons.check_circle,
                          size: 19, color: palette.success)
                    else if (showResult && isSelected)
                      Icon(Icons.cancel,
                          size: 19, color: palette.danger),
                  ],
                ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: tone.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(18),
        color: tone.withValues(alpha: ok ? 0.06 : 0.035),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone,
                ),
                child: Icon(
                    ok ? Icons.check : Icons.close,
                    size: 19,
                    color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ok ? 'Correct Answer' : 'Incorrect Answer',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tone)),
                    Text(
                        ok
                            ? 'Your answer is correct.'
                            : 'The selected option is incorrect.',
                        style: TextStyle(
                            fontSize: 9,
                            color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: tone.withValues(alpha: 0.2)),
          if (_currentSelected != null) ...[
            Text('Selected option: ${q.options[_currentSelected!]}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: tone)),
            const SizedBox(height: 7),
          ],
          if (!ok) ...[
            Text('Correct option: ${q.options[q.correctIndex]}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: palette.success)),
            const SizedBox(height: 7),
          ],
          const Text('Explanation',
              style:
                  TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(bilingual(q.explanation, q.explanationNe),
              style: TextStyle(
                  fontSize: 13,
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
            const BorderRadius.vertical(top: Radius.circular(16)),
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
        minimum: const EdgeInsets.fromLTRB(12, 9, 12, 9),
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
                          size: 17, color: palette.primary),
                      const SizedBox(width: 6),
                      Text('Previous',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: palette.primary)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.35),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward,
                        size: 17, color: Colors.white),
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
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(
              horizontal: 11, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
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

  /// Generic app dialog — FeedSpring-style white card (both themes):
  /// blue gradient header fading to white, white tagline pill, navy title,
  /// stacked white Cancel + blue gradient CTA. Overlay dims per theme.
  /// Routing/callbacks unchanged — only visuals were reworked.
  Widget _appDialog({
    required ExpoPalette palette,
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
    return _FadeIn(
      child: Container(
        color: isDark
            ? Colors.black.withValues(alpha: 0.6)
            : const Color(0x800F172A),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: LimitDialogCard(
              tagline: tagline,
              title: title,
              message: message,
              bodyExtra: bodyExtra,
              icon: icon,
              confirmLabel: confirmLabel,
              confirmIcon: confirmIcon,
              cancelLabel: cancelLabel,
              onConfirm: onConfirm,
              onCancel: onCancel,
            ),
          ),
        ),
      ),
    );
  }

  Widget _limitDialog(ExpoPalette palette) => _appDialog(
        palette: palette,
        icon: Icons.diamond,
        tagline: 'Daily Limit',
        title: 'Your Daily Practice limit is reached',
        message:
            'You have completed today\u2019s practice limit for this chapter.',
        bodyExtra: const Text(
          'To Crack Your Daily Limit! Subscribe to Our Pro Plan',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            decoration: TextDecoration.none,
          ),
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
        icon: Icons.pause_circle_outline,
        tagline: 'Pause Practice',
        title: 'Pause Your Progress?',
        message:
            'Your completed answers are safely stored. You can return whenever you are ready.',
        bodyExtra: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: palette.success.withValues(alpha: 0.33)),
            color: palette.success.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_done_outlined,
                  size: 17, color: palette.success),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'Progress synced in the background',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: palette.success,
                      decoration: TextDecoration.none),
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

/// Staggered option-tile entrance — fade + 12px slide-up, tiles start
/// ~70ms apart (index * 70). Each tile is keyed on the question id, so a
/// question change builds fresh State objects whose controllers replay the
/// animation from scratch on every question — same feel as the
/// units/chapters list stagger. Selecting an option rebuilds with the same
/// keys, so the animation does not replay mid-question.
class _OptionStagger extends StatefulWidget {
  final int index;
  final Widget child;

  const _OptionStagger(
      {super.key, required this.index, required this.child});

  @override
  State<_OptionStagger> createState() => _OptionStaggerState();
}

class _OptionStaggerState extends State<_OptionStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 70), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
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

  /// Pending "save confirmed" timer — cancelled if the background write
  /// fails first, or if the tap is superseded by a newer one.
  Timer? _saveTimer;

  /// Monotonic op id: guards the fire-and-forget save against a later
  /// remove/refresh so a stale failure can't clobber newer state.
  int _opId = 0;

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

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Tap UX: a small spinner replaces the icon for 2s, then the success
  /// toast fires. The Firestore write starts immediately, fire-and-forget —
  /// the toast never waits for the network. If the write later fails, the
  /// icon reverts to unbookmarked and an error toast shows.
  void _onTap() {
    if (_busy || widget.uid.isEmpty) return;
    if (_saved) {
      _remove();
      return;
    }
    setState(() => _busy = true);
    _saveTimer?.cancel();
    final op = ++_opId;
    unawaited(_saveInBackground(op));
    _saveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saved = true;
      });
      showToast(context, 'Saved to bookmarks.', ToastVariant.success);
    });
  }

  Future<void> _saveInBackground(int op) async {
    final path = 'users/${widget.uid}/bookmarks/$_docId';
    try {
      final idToken = await AuthService.getValidIdToken();
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
        if (op != _opId || !mounted) return;
        _saveTimer?.cancel();
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
      // Success is reported by the 2s timer — nothing more to do here.
    } catch (_) {
      // Superseded by a newer tap, or the button was rebuilt — leave the
      // newer state alone.
      if (op != _opId || !mounted) return;
      _saveTimer?.cancel();
      setState(() {
        _busy = false;
        _saved = false;
      });
      showToast(
          context,
          'Could not update the bookmark. Please try again.',
          ToastVariant.error);
    }
  }

  Future<void> _remove() async {
    _opId++;
    _saveTimer?.cancel();
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
    return IconButton(
      onPressed: _busy ? null : _onTap,
      icon: _busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: palette.primary,
              ),
            )
          : Icon(
              _saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              size: 20),
      color: _saved ? palette.primary : palette.textSecondary,
      tooltip: _saved ? 'Remove bookmark' : 'Bookmark',
      padding: EdgeInsets.zero,
      constraints:
          const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}
