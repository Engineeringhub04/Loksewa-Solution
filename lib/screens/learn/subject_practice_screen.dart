import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Subject practice mode — exact port of app/subjects/practice.tsx.
/// Daily-limit gating (free min(30,len) / premium min(100,len)), premium
/// questions capped to 100, per-question lock-in, Firestore progress sync.
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
  bool _hasSpecificAccess = false;
  bool _profilePremium = false;
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

  void _onNext() {
    if (_current == _questions.length - 1) {
      if (_proSubjectActive) {
        setState(() => _showWaiting = true);
      } else {
        setState(() => _showLimit = true);
      }
      return;
    }
    setState(() => _current++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
            title: 'Practice Mode',
            onBackPress: () => setState(() => _showLeaveConfirm = true),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError
                    ? _errorState()
                    : _questions.isEmpty
                        ? _emptyState()
                        : _mainList(theme),
          ),
        ],
      ),
      bottomNavigationBar: _loading || _loadError || _questions.isEmpty
          ? null
          : _bottomBar(theme),
    );
  }

  Widget _errorState() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Something went wrong.'),
              const SizedBox(height: 8),
              ElevatedButton(
                  onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
        if (_showLeaveConfirm) _leaveDialog(),
      ],
    );
  }

  Widget _emptyState() {
    return Stack(
      children: [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Practice questions are not available for this chapter yet. Content is being prepared and will be added soon.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (_showLeaveConfirm) _leaveDialog(),
      ],
    );
  }

  Widget _mainList(ThemeData theme) {
    final q = _currentQuestion!;
    final premium = _premium;
    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            // daily limit row
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border.all(
                    color: premium
                        ? const Color(0xFF059669)
                        : theme.dividerColor),
                borderRadius: BorderRadius.circular(10),
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
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: premium
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF1D4ED8)),
                        ),
                        if (!premium)
                          Text(
                            'New questions are selected after midnight.',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6)),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                      premium
                          ? Icons.check_circle
                          : Icons.speed,
                      size: 22,
                      color: premium
                          ? const Color(0xFF059669)
                          : const Color(0xFF1D4ED8)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // question meta row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF1D4ED8).withValues(alpha: 0.08),
                  ),
                  child: Text('Question ${_current + 1}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1D4ED8))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // question card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bilingual(q.text, q.textNe),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.35)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: q.difficulty == 'easy'
                          ? const Color(0x18059669)
                          : q.difficulty == 'medium'
                              ? const Color(0x20D97706)
                              : const Color(0x18DC2626),
                    ),
                    child: Text(q.difficulty.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: q.difficulty == 'easy'
                                ? const Color(0xFF059669)
                                : q.difficulty == 'medium'
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFFDC2626))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // options
            ...List.generate(q.options.length, (index) {
              final isSelected = _currentSelected == index;
              final isCorrect = index == q.correctIndex;
              final showResult = _currentAttempted;
              final background = showResult && isCorrect
                  ? const Color(0x16059669)
                  : showResult && isSelected && !isCorrect
                      ? const Color(0x16DC2626)
                      : theme.cardColor;
              final border = showResult && isCorrect
                  ? const Color(0xFF059669)
                  : showResult && isSelected && !isCorrect
                      ? const Color(0xFFDC2626)
                      : isSelected
                          ? const Color(0xFF1D4ED8)
                          : theme.dividerColor;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _selectOption(index),
                    child: Container(
                      constraints:
                          const BoxConstraints(minHeight: 66),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: border, width: 1.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: border, width: 1.5),
                              color:
                                  isSelected || (showResult && isCorrect)
                                      ? border
                                      : Colors.transparent,
                            ),
                            child: Text(
                                String.fromCharCode(65 + index),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ||
                                            (showResult && isCorrect)
                                        ? Colors.white
                                        : theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(q.options[index],
                                style: const TextStyle(
                                    fontSize: 15, height: 1.33)),
                          ),
                          if (showResult && isCorrect)
                            const Icon(Icons.check_circle,
                                size: 22,
                                color: Color(0xFF059669))
                          else if (showResult && isSelected)
                            const Icon(Icons.cancel,
                                size: 22,
                                color: Color(0xFFDC2626)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            // explanation card
            if (_currentAttempted) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: _currentCorrect
                          ? const Color(0x65059669)
                          : const Color(0x65DC2626)),
                  borderRadius: BorderRadius.circular(18),
                  color: _currentCorrect
                      ? const Color(0x10059669)
                      : const Color(0x09DC2626),
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
                            color: _currentCorrect
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                          child: Icon(
                              _currentCorrect
                                  ? Icons.check
                                  : Icons.close,
                              size: 22,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                  _currentCorrect
                                      ? 'Correct Answer'
                                      : 'Incorrect Answer',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: _currentCorrect
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626))),
                              Text(
                                  _currentCorrect
                                      ? 'Your answer is correct.'
                                      : 'The selected option is incorrect.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Container(
                        height: 1,
                        margin:
                            const EdgeInsets.symmetric(vertical: 10),
                        color: _currentCorrect
                            ? const Color(0x35059669)
                            : const Color(0x35DC2626)),
                    if (_currentSelected != null)
                      Text(
                          'Selected option: ${q.options[_currentSelected!]}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _currentCorrect
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626))),
                    if (!_currentCorrect)
                      Text(
                          'Correct option: ${q.options[q.correctIndex]}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF059669))),
                    const SizedBox(height: 8),
                    const Text('Explanation',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(bilingual(q.explanation, q.explanationNe),
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.75))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
        if (_showLimit) _limitDialog(),
        if (_showWaiting) _waitingDialog(),
        if (_showLeaveConfirm) _leaveDialog(),
      ],
    );
  }

  Widget _bottomBar(ThemeData theme) {
    final isLast = _current == _questions.length - 1;
    final nextDisabled =
        !_premium && _dailyUsed >= _dailyLimit && !_currentAttempted;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 85,
              child: Opacity(
                opacity: _current == 0 ? 0.45 : 1,
                child: OutlinedButton.icon(
                  onPressed: _current == 0
                      ? null
                      : () => setState(() => _current--),
                  icon: const Icon(Icons.arrow_back,
                      size: 19, color: Color(0xFF1D4ED8)),
                  label: const Text('Previous',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D4ED8))),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 135,
              child: ElevatedButton(
                onPressed: nextDisabled ? null : _onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 50),
                ),
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
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.38),
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

  Widget _sheet({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String message,
    required String confirmLabel,
    IconData? confirmIcon,
    String? extra,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
    bool singleButton = false,
  }) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: iconColor),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (extra != null) ...[
                const SizedBox(height: 8),
                Text(extra,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6)),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white),
                  icon: confirmIcon != null
                      ? Icon(confirmIcon, size: 18)
                      : const SizedBox.shrink(),
                  label: Text(confirmLabel),
                  onPressed: onConfirm,
                ),
              ),
              if (!singleButton) ...[
                const SizedBox(height: 8),
                TextButton(
                    onPressed: onCancel, child: const Text('Close')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _limitDialog() => _sheet(
        title: 'Your Daily Practice limit is reached',
        icon: Icons.diamond_outlined,
        iconColor: const Color(0xFFD97706),
        message:
            'You have completed today\u2019s practice limit for this chapter.',
        extra: 'To Crack Your Daily Limit! Subscribe to Our Pro Plan',
        confirmLabel: 'Subscription',
        confirmIcon: Icons.diamond_outlined,
        onConfirm: () {
          setState(() => _showLimit = false);
          context.push('/subscription');
        },
        onCancel: () => setState(() => _showLimit = false),
      );

  Widget _waitingDialog() => _sheet(
        title: 'All Available Questions Completed',
        icon: Icons.checklist,
        iconColor: const Color(0xFF1D4ED8),
        message:
            'You have practiced all currently available questions for this premium chapter. New questions will appear when they are uploaded.',
        confirmLabel: 'OK',
        singleButton: true,
        onConfirm: () => setState(() => _showWaiting = false),
        onCancel: () => setState(() => _showWaiting = false),
      );

  Widget _leaveDialog() => _sheet(
        title: 'Pause Your Progress?',
        icon: Icons.pause_circle_outline,
        iconColor: const Color(0xFF1D4ED8),
        message:
            'Your completed answers are safely stored. You can return whenever you are ready.',
        extra: 'Progress synced in the background',
        confirmLabel: 'Leave Practice',
        onConfirm: () {
          setState(() => _showLeaveConfirm = false);
          context.pop();
        },
        onCancel: () => setState(() => _showLeaveConfirm = false),
      );
}
