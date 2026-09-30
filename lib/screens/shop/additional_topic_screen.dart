// Additional-feature topic screen — read vs practice tracks.
// Mirrors app/additional-features/[featureId]/[topicId].tsx exactly.
//
// Data:
// - bank doc: app_additional_feature_question_banks/{featureId}__all__all__{topicId}
// - topic titles: looked up from the page doc
//   app_additional_feature_pages/{featureId}__all__all (the route carries only
//   featureId + topicId)
// - practice progress (local): af_practice_{featureId}_{topicId} = JSON of
//   { featureId, topicId, dailyDate, attemptedQuestionIds, correctQuestionIds,
//     selectedAnswerIndexes, selectedAnswerIds } — stale dates reset.
//
// Answer key: the seeded schema stores `correctOption` 1-BASED. Resolution
// matches React's correctIndex(): first try correctOptionId -> option id match,
// else convert the numeric correctOption via options[raw - 1].
//
// Practice: shuffled question order + shuffled options per question,
// one-at-a-time, DAILY_LIMIT = 50 -> dailyLimit = min(questionCount, 50).
// Selected answers restore from the stored progress. Limit dialog +
// leave-practice confirm dialog (with the "Saved to phone cache" badge).
// Back navigates back directly on read track; on practice track it asks for
// confirmation first.
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/limit_dialog.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

const int _dailyLimitCap = 50;

class AdditionalTopicScreen extends StatefulWidget {
  final String featureId;
  final String topicId;
  const AdditionalTopicScreen(
      {super.key, required this.featureId, required this.topicId});

  @override
  State<AdditionalTopicScreen> createState() => _AdditionalTopicScreenState();
}

class _Option {
  final String id;
  final String text;
  _Option({required this.id, required this.text});
}

class _Question {
  final String questionId;
  final String question;
  final List<_Option> options;
  final int correctIndex;
  final String explanation;
  final String difficulty;
  _Question({
    required this.questionId,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
  });
}

class _AdditionalTopicScreenState extends State<AdditionalTopicScreen> {
  List<_Question> _questions = [];
  bool _loading = true;
  String? _error;
  String _topicTitle = '';

  String _track = 'read'; // read | practice
  final Map<String, bool> _expanded = {};

  // Practice state
  int _current = 0;
  Set<String> _attempted = {};
  Set<String> _correctIds = {};
  Map<String, int> _selectedIndexes = {};
  Map<String, String> _selectedIds = {};
  // Practice state

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _progressKey =>
      'af_practice_${widget.featureId}_${widget.topicId}';

  /// Resolves the correct option INDEX exactly like React's correctIndex():
  /// 1) correctOptionId matched against option ids;
  /// 2) numeric correctOption is 1-BASED -> options[raw - 1].
  static int _resolveCorrectIndex(Map<String, dynamic> q, List<_Option> opts) {
    final cid = q['correctOptionId']?.toString();
    if (cid != null && cid.isNotEmpty) {
      final idx = opts.indexWhere((o) => o.id == cid);
      if (idx >= 0) return idx;
    }
    final raw = num.tryParse(q['correctOption']?.toString() ?? '');
    if (raw != null && raw.isFinite) {
      final oneBased = raw.toInt();
      if (oneBased >= 1 && oneBased <= opts.length) return oneBased - 1;
      return oneBased.clamp(0, opts.length - 1);
    }
    return 0;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await AuthService.getValidIdToken();
      final bank = await FirestoreRest.getDocument(
        'app_additional_feature_question_banks/${widget.featureId}__all__all__${widget.topicId}',
        idToken: token,
      );
      if (bank == null) throw Exception('Question bank not found.');

      // Topic title from the page doc (route carries only featureId/topicId).
      final page = await FirestoreRest.getDocument(
        'app_additional_feature_pages/${widget.featureId}__all__all',
        idToken: token,
      );
      String titleEn = '';
      String titleNp = '';
      final rawTopics = page?['topics'];
      if (rawTopics is List) {
        for (final raw in rawTopics) {
          if (raw is! Map) continue;
          if ((raw['topicId'] ?? '').toString() == widget.topicId) {
            titleEn = (raw['titleEn'] ?? '').toString();
            titleNp = (raw['titleNp'] ?? '').toString();
            break;
          }
        }
      }
      if (titleEn.isEmpty) {
        titleEn = (bank['topicTitleEn'] ?? widget.topicId).toString();
      }
      if (titleNp.isEmpty) {
        titleNp = (bank['topicTitleNp'] ?? titleEn).toString();
      }

      final rawQs = (bank['questions'] as List?) ?? [];
      final questions = <_Question>[];
      for (final raw in rawQs) {
        if (raw is! Map) continue;
        final q = Map<String, dynamic>.from(raw);
        final opts = ((q['options'] as List?) ?? [])
            .whereType<Map>()
            .map((o) => _Option(
                  id: (o['id'] ?? '').toString(),
                  text: (o['text'] ?? '').toString(),
                ))
            .toList();
        if (opts.isEmpty) continue;
        questions.add(_Question(
          questionId: (q['questionId'] ?? '').toString(),
          question: (q['question'] ?? '').toString(),
          options: opts,
          correctIndex: _resolveCorrectIndex(q, opts),
          explanation: (q['explanation'] ?? '').toString(),
          difficulty: (q['difficulty'] ?? '').toString(),
        ));
      }
      questions.sort((a, b) => 0); // read mode shows bank order

      // Restore stored practice progress (fresh dailyDate only).
      final saved = await PrefsService.getString(_progressKey);
      final today = _dateKey();
      if (saved != null && saved.isNotEmpty) {
        try {
          final m = json.decode(saved) as Map<String, dynamic>;
          if ((m['dailyDate'] ?? '').toString() == today) {
            _attempted = ((m['attemptedQuestionIds'] as List?) ?? [])
                .map((e) => e.toString())
                .toSet();
            _correctIds = ((m['correctQuestionIds'] as List?) ?? [])
                .map((e) => e.toString())
                .toSet();
            final si = m['selectedAnswerIndexes'];
            if (si is Map) {
              _selectedIndexes = {
                for (final e in si.entries)
                  e.key.toString(): (e.value as num).toInt()
              };
            }
            final sid = m['selectedAnswerIds'];
            if (sid is Map) {
              _selectedIds = {
                for (final e in sid.entries) e.key.toString(): e.value.toString()
              };
            }
          }
        } catch (_) {}
      }

      setState(() {
        _questions = questions;
        _topicTitle = titleEn;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static String _dateKey() {
    final d = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Future<void> _persist() async {
    await PrefsService.setString(
      _progressKey,
      json.encode({
        'featureId': widget.featureId,
        'topicId': widget.topicId,
        'dailyDate': _dateKey(),
        'attemptedQuestionIds': _attempted.toList(),
        'correctQuestionIds': _correctIds.toList(),
        'selectedAnswerIndexes': _selectedIndexes,
        'selectedAnswerIds': _selectedIds,
      }),
    );
  }

  /// Practice question order: shuffled once per load, questions in bank order
  /// otherwise (read mode).
  List<_Question> get _practiceQuestions {
    final rng = Random('practice${widget.topicId}'.hashCode);
    final shuffled = List<_Question>.from(_questions)..shuffle(rng);
    // Shuffle each question's options too, keeping the correct index aligned.
    return shuffled.map((q) {
      final idxs = List<int>.generate(q.options.length, (i) => i)..shuffle(rng);
      final newOpts = idxs.map((i) => q.options[i]).toList();
      return _Question(
        questionId: q.questionId,
        question: q.question,
        options: newOpts,
        correctIndex: idxs.indexOf(q.correctIndex),
        explanation: q.explanation,
        difficulty: q.difficulty,
      );
    }).toList();
  }

  int get _dailyLimit =>
      _questions.length < _dailyLimitCap ? _questions.length : _dailyLimitCap;

  void _changeTrack(String track) {
    setState(() {
      _track = track;
      _current = 0;
      _expanded.clear();
    });
  }

  Future<bool> _onBack() async {
    if (_track == 'practice') {
      final leave = await _leaveDialog();
      return leave == true;
    }
    return true;
  }

  void _selectPracticeOption(_Question q, int optionIndex) {
    if (_attempted.contains(q.questionId)) return;
    if (_attempted.length >= _dailyLimit) {
      _limitDialog();
      return;
    }
    final correct = optionIndex == q.correctIndex;
    setState(() {
      _attempted.add(q.questionId);
      if (correct) _correctIds.add(q.questionId);
      _selectedIndexes[q.questionId] = optionIndex;
      _selectedIds[q.questionId] = q.options[optionIndex].id;
    });
    _persist();
    if (_attempted.length >= _dailyLimit) {
      _limitDialog();
    }
  }

  void _practiceNext(int total) {
    final isLast = _current >= total - 1;
    if (isLast) {
      if (_attempted.length >= _dailyLimit) {
        _limitDialog();
      } else {
        showToast(context, 'Practice complete', ToastVariant.success);
      }
      return;
    }
    setState(() => _current = (_current + 1).clamp(0, total - 1));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onBack()) {
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            SubpageHeader(title: _topicTitle.isEmpty ? '...' : _topicTitle),
            if (!_loading && _error == null && _questions.isNotEmpty)
              _trackBar(),
            Expanded(
              child: _loading
                  // Mirrors the React Preloading state on the topic screen.
                  ? const PreloadingWidget(
                      tinted: false,
                      label: 'Loading questions...',
                      hint: 'Preparing your questions',
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Unable to load questions.',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _load,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _questions.isEmpty
                          ? const Center(
                              child: Text(
                                  'No questions are available for this topic.'))
                          : _track == 'read'
                              ? _readBody()
                              : _practiceBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          _trackButton('read', Icons.menu_book_outlined, 'Read'),
          _trackButton('practice', Icons.edit_note_outlined, 'Practice'),
        ],
      ),
    );
  }

  Widget _trackButton(String key, IconData icon, String label) {
    final active = _track == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTrack(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: active
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: active
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================ READ TRACK ============================

  Widget _readBody() {
    final allOpen = _questions.every((q) => _expanded[q.questionId] == true);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.menu_book_outlined,
                      color: AppColors.navy),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Important Questions',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text(
                        'Tap a question to expand its answer.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      final openAll = !allOpen;
                      for (final q in _questions) {
                        _expanded[q.questionId] = openAll;
                      }
                    });
                  },
                  child: Text(allOpen ? 'Collapse all' : 'Expand all'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < _questions.length; i++)
          _readQuestion(_questions[i], i),
      ],
    );
  }

  Widget _readQuestion(_Question q, int index) {
    final open = _expanded[q.questionId] == true;
    const success = Color(0xFF16A34A);
    const warning = Color(0xFFD97706);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {},
                ),
              ],
            ),
            Text(
              q.question,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(
                  () => _expanded[q.questionId] = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      open ? 'Hide answer' : 'Show answer',
                      style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...[
              const SizedBox(height: 6),
              for (int oi = 0; oi < q.options.length; oi++)
                _readOption(q, oi, success),
              const SizedBox(height: 10),
              if (q.explanation.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: warning.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 20, color: warning),
                          const SizedBox(width: 6),
                          Text(
                            'Explanation',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: warning,
                                fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(q.explanation,
                          style: const TextStyle(
                              fontSize: 14, height: 1.45)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _readOption(_Question q, int oi, Color success) {
    final correct = oi == q.correctIndex;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: correct
            ? success.withValues(alpha: 0.08)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: correct
                ? success.withValues(alpha: 0.6)
                : Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: correct ? success : Colors.transparent,
              border: Border.all(
                  color: correct
                      ? success
                      : Colors.grey.withValues(alpha: 0.4),
                  width: 1.4),
            ),
            child: Center(
              child: Text(
                String.fromCharCode(65 + oi),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: correct
                        ? Colors.white
                        : onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(q.options[oi].text,
                style: const TextStyle(fontSize: 14, height: 1.35)),
          ),
          if (correct)
            const Icon(Icons.check_circle, size: 20, color: Color(0xFF16A34A)),
        ],
      ),
    );
  }

  // =========================== PRACTICE TRACK ==========================

  Widget _practiceBody() {
    final active = _practiceQuestions;
    final total = active.length;
    final q = active[_current.clamp(0, total - 1)];
    final attempted = _attempted.contains(q.questionId);
    final selected = _selectedIndexes[q.questionId];
    final wasCorrect = _correctIds.contains(q.questionId);
    final used = _attempted.length;
    final limit = _dailyLimit;
    const success = Color(0xFF16A34A);
    const error = Color(0xFFDC2626);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's practice: $used/$limit",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'The daily limit will reset on the next day.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.timer,
                    size: 22, color: AppColors.navy),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUESTION ${_current + 1} OF $total',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_current + 1) / total,
                    minHeight: 5,
                    backgroundColor:
                        onSurface.withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.navy),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.question,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600, height: 1.45),
                ),
                if (q.difficulty.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _difficultyColor(q.difficulty)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      q.difficulty.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _difficultyColor(q.difficulty)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (int oi = 0; oi < q.options.length; oi++)
          _practiceOption(q, oi, attempted, selected, wasCorrect, success, error),
        if (attempted) _explanationCard(q, selected, wasCorrect, success, error),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 85,
              child: OutlinedButton.icon(
                onPressed: _current == 0
                    ? null
                    : () => setState(() => _current--),
                icon: const Icon(Icons.arrow_back, size: 19),
                label: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 135,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: (!attempted && used >= limit)
                    ? null
                    : () => _practiceNext(total),
                child: Text(
                  _current == total - 1 ? 'Practice complete' : 'Next',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _practiceOption(_Question q, int oi, bool attempted, int? selected,
      bool wasCorrect, Color success, Color error) {
    final isSelected = selected == oi;
    final isCorrect = oi == q.correctIndex;
    Color border;
    Color? bg;
    if (attempted && isCorrect) {
      border = success;
      bg = success.withValues(alpha: 0.1);
    } else if (attempted && isSelected && !isCorrect) {
      border = error;
      bg = error.withValues(alpha: 0.08);
    } else if (isSelected) {
      border = AppColors.navy;
      bg = null;
    } else {
      border = Colors.grey.withValues(alpha: 0.35);
      bg = null;
    }
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: attempted ? null : () => _selectPracticeOption(q, oi),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: bg ?? Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1.4),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isSelected || (attempted && isCorrect))
                    ? border
                    : Colors.transparent,
                border: Border.all(color: border, width: 1.5),
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + oi),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: (isSelected || (attempted && isCorrect))
                          ? Colors.white
                          : onSurface.withValues(alpha: 0.6)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(q.options[oi].text,
                  style: const TextStyle(fontSize: 15, height: 1.35)),
            ),
            if (attempted && isCorrect)
              const Icon(Icons.check_circle, size: 22, color: Color(0xFF16A34A)),
            if (attempted && isSelected && !isCorrect)
              const Icon(Icons.cancel, size: 22, color: Color(0xFFDC2626)),
          ],
        ),
      ),
    );
  }

  Widget _explanationCard(_Question q, int? selected, bool wasCorrect,
      Color success, Color error) {
    final color = wasCorrect ? success : error;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                    wasCorrect ? Icons.check : Icons.close,
                    color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wasCorrect ? 'Correct answer' : 'Incorrect answer',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: color),
                    ),
                    Text(
                      wasCorrect
                          ? 'Answer recorded'
                          : 'Please review the correct answer below',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (selected != null)
            Text(
              'Answer: ${String.fromCharCode(65 + selected)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: color, fontSize: 13),
            ),
          if (!wasCorrect)
            Text(
              'Correct answer: ${String.fromCharCode(65 + q.correctIndex)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                  fontSize: 13),
            ),
          const SizedBox(height: 6),
          const Text('Explanation',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(q.explanation,
              style: const TextStyle(
                  fontSize: 15, height: 1.4, color: Colors.black87)),
        ],
      ),
    );
  }

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return const Color(0xFF16A34A);
      case 'medium':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFDC2626);
    }
  }

  Future<bool?> _leaveDialog() {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.exit_to_app,
            color: Color(0xFFDC2626), size: 32),
        title: const Text('Leave this practice?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your progress will be saved in this phone\u2019s cache. You can continue this topic later.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF16A34A)
                        .withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smartphone,
                      size: 19, color: Color(0xFF16A34A)),
                  SizedBox(width: 8),
                  Text('Saved to phone cache',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep practising'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Leave practice',
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }

  Future<void> _limitDialog() async {
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: LimitDialogCard(
          tagline: 'Daily Limit',
          title: 'Today\u2019s practice limit is complete',
          message:
              'You have completed today\u2019s available practice. Please come back tomorrow and practice again.',
          icon: Icons.diamond,
          confirmLabel: 'Subscription',
          confirmIcon: Icons.diamond_outlined,
          cancelLabel: 'Close',
          onConfirm: () => Navigator.pop(c),
          onCancel: () => Navigator.pop(c),
        ),
      ),
    );
  }
}
