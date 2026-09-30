// Additional-feature topic screen — read vs practice tracks.
// Mirrors app/additional-features/[featureId]/[topicId].tsx.
//
// Data:
// - bank doc: app_additional_feature_question_banks/{featureId}__all__all__{topicId}
// - topic titles: the route's `extra` carries topicTitleEn/topicTitleNp so the
//   header shows the topic name immediately; the page-doc lookup
//   (app_additional_feature_pages/{featureId}__all__all) is only a fallback.
// - offline fallback: <appDocs>/af_offline/<fid>/banks/<topicId>.json +
//   <appDocs>/af_offline/<fid>/page.json (written by another agent), used when
//   the Firestore fetch fails. An "Offline" chip marks cached content.
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
// Selected answers restore from the stored progress. Question changes animate
// (fade + slight slide) and option tiles stagger in, mirroring the chapter
// practice screen. Bookmark/report actions sit next to the question badge in
// both tracks. Limit dialog + leave-practice confirm dialog (with the
// "Saved to phone cache" badge). Back navigates back directly on read track;
// on practice track it asks for confirmation first.
//
// Expand All / Collapse All animates each card via AnimatedSize (~250ms) —
// finite, pumpAndSettle-safe. No infinite animations anywhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import 'package:loksewa_solution/widgets/limit_dialog.dart';
import 'package:loksewa_solution/widgets/report_dialog.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

const int _dailyLimitCap = 50;

class AdditionalTopicScreen extends StatefulWidget {
  final String featureId;
  final String topicId;

  /// Route `extra` titles — shown in the header immediately, before the
  /// network fetch finishes. Empty/absent falls back to the page doc / bank.
  final String? topicTitleEn;
  final String? topicTitleNp;

  const AdditionalTopicScreen({
    super.key,
    required this.featureId,
    required this.topicId,
    this.topicTitleEn,
    this.topicTitleNp,
  });

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

  /// True when the bank came from the on-device offline cache.
  bool _offline = false;

  String _track = 'read'; // read | practice
  final Map<String, bool> _expanded = {};

  // Practice state
  int _current = 0;

  /// +1 when moving to the next question, -1 for previous — drives the
  /// question transition direction in the AnimatedSwitcher.
  int _slideDir = 0;
  final ScrollController _practiceScroll = ScrollController();
  Set<String> _attempted = {};
  Set<String> _correctIds = {};
  Map<String, int> _selectedIndexes = {};
  Map<String, String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // The route carries the titles — show the name immediately instead of
    // '...' while the bank loads. The fetch below only fills gaps.
    final initial = widget.topicTitleEn?.trim() ?? '';
    if (initial.isNotEmpty) _topicTitle = initial;
    _load();
  }

  @override
  void dispose() {
    _practiceScroll.dispose();
    super.dispose();
  }

  String get _progressKey =>
      'af_practice_${widget.featureId}_${widget.topicId}';

  String get _displayTitle =>
      _topicTitle.isEmpty ? widget.topicId : _topicTitle;

  /// Theme-aware blue accent — the established
  /// `isDark ? 0xFF3B82F6 : 0xFF1D4ED8` pattern from the additional-features
  /// home screen. Replaces the old hardcoded navy that was invisible in
  /// dark mode.
  Color get _accent {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
  }

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

  /// Offline cache written by the offline-sync flow:
  /// `<appDocs>/af_offline/<fid>/banks/<topicId>.json` (raw decoded bank map)
  /// plus `<appDocs>/af_offline/<fid>/page.json` (raw decoded page doc).
  /// Sync fs ops — safe on test-covered paths (see AGENTS.md).
  Future<({Map<String, dynamic> bank, Map<String, dynamic>? page})?>
      _readOfflineCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final bankFile = File(
          '${dir.path}/af_offline/${widget.featureId}/banks/${widget.topicId}.json');
      if (!bankFile.existsSync()) return null;
      final bank = json.decode(bankFile.readAsStringSync());
      if (bank is! Map<String, dynamic>) return null;
      Map<String, dynamic>? page;
      final pageFile =
          File('${dir.path}/af_offline/${widget.featureId}/page.json');
      if (pageFile.existsSync()) {
        final decoded = json.decode(pageFile.readAsStringSync());
        if (decoded is Map<String, dynamic>) page = decoded;
      }
      return (bank: bank, page: page);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      final token = await AuthService.getValidIdToken();
      Map<String, dynamic>? bank;
      Map<String, dynamic>? page;
      var offline = false;
      try {
        bank = await FirestoreRest.getDocument(
          'app_additional_feature_question_banks/${widget.featureId}__all__all__${widget.topicId}',
          idToken: token,
        );
        // Topic title from the page doc — only when the route didn't carry
        // the titles already.
        if ((widget.topicTitleEn?.trim().isNotEmpty ?? false) &&
            (widget.topicTitleNp?.trim().isNotEmpty ?? false)) {
          page = null;
        } else {
          page = await FirestoreRest.getDocument(
            'app_additional_feature_pages/${widget.featureId}__all__all',
            idToken: token,
          );
        }
      } catch (_) {
        // Network failed (offline) — fall back to the on-device cache.
        final cached = await _readOfflineCache();
        if (cached == null) rethrow;
        bank = cached.bank;
        page = cached.page;
        offline = true;
      }
      if (bank == null) throw Exception('Question bank not found.');

      String titleEn = widget.topicTitleEn?.trim() ?? '';
      String titleNp = widget.topicTitleNp?.trim() ?? '';
      if (titleEn.isEmpty || titleNp.isEmpty) {
        final rawTopics = page?['topics'];
        if (rawTopics is List) {
          for (final raw in rawTopics) {
            if (raw is! Map) continue;
            if ((raw['topicId'] ?? '').toString() == widget.topicId) {
              if (titleEn.isEmpty) {
                titleEn = (raw['titleEn'] ?? '').toString();
              }
              if (titleNp.isEmpty) {
                titleNp = (raw['titleNp'] ?? '').toString();
              }
              break;
            }
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
        _offline = offline;
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
      _slideDir = 0;
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
    // Reveal the explanation below — mirrors the chapter practice screen.
    Future.delayed(const Duration(milliseconds: 180), () {
      if (_practiceScroll.hasClients) {
        _practiceScroll.animateTo(
          _practiceScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
    if (_attempted.length >= _dailyLimit) {
      _limitDialog();
    }
  }

  void _goToQuestion(int delta) {
    final total = _practiceQuestions.length;
    if (total == 0) return;
    final next = (_current + delta).clamp(0, total - 1);
    if (next == _current) return;
    setState(() {
      _slideDir = delta > 0 ? 1 : -1;
      _current = next;
    });
    // Back to the top on every question change — otherwise the new question
    // would open scrolled down at the previous question's position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_practiceScroll.hasClients) {
        _practiceScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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
    _goToQuestion(1);
  }

  /// Shared report dialog wiring for both tracks.
  void _reportQuestion(_Question q) {
    ReportDialog.show(
      context: context,
      question: q.question,
      options: q.options.map((o) => o.text).toList(),
      questionId: q.questionId,
      subject: widget.featureId,
      chapter: _displayTitle,
      mode: _track,
    );
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
            if (_offline && !_loading && _error == null) _offlineChip(),
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

  /// Small theme-aware chip marking on-device cached content. No emoji.
  Widget _offlineChip() {
    final accent = _accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 13, color: accent),
              const SizedBox(width: 5),
              Text(
                'Offline',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accent),
              ),
            ],
          ),
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
    final accent = _accent;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTrack(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? accent : Colors.transparent,
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

  /// The 38x38 elevated action tile from the chapter practice screen
  /// (bookmark / report).
  Widget _actionBox(Widget child) {
    final pal = ExpoPalette.of(context);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: pal.surface,
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

  // ============================ READ TRACK ============================

  Widget _readBody() {
    final accent = _accent;
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
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.menu_book_outlined, color: accent),
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
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
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
                  style: TextButton.styleFrom(foregroundColor: accent),
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
    final accent = _accent;
    final pal = ExpoPalette.of(context);
    final success = pal.success;
    final warning = pal.warning;
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
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accent),
                  ),
                ),
                if (q.difficulty.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _difficultyColor(q.difficulty)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
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
                const Spacer(),
                _actionBox(_AfBookmarkButton(
                  uid: AuthService.currentUser?.uid ?? '',
                  featureId: widget.featureId,
                  topicId: widget.topicId,
                  topicTitle: _displayTitle,
                  track: 'read',
                  question: q,
                )),
                const SizedBox(width: 8),
                _actionBox(
                  IconButton(
                    onPressed: () => _reportQuestion(q),
                    icon: const Icon(Icons.flag_rounded, size: 19),
                    color: pal.textSecondary,
                    tooltip: 'Report',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 34, minHeight: 34),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              q.question,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () =>
                  setState(() => _expanded[q.questionId] = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      open ? 'Hide answer' : 'Show answer',
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            // Smooth finite expand/collapse (~250ms) — AnimatedSize animates
            // between the two sizes; pumpAndSettle-safe, no controllers.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: open
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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
                    )
                  : const SizedBox(width: double.infinity),
            ),
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
                  color: correct ? success : Colors.grey.withValues(alpha: 0.4),
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
          if (correct) Icon(Icons.check_circle, size: 20, color: success),
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
    final pal = ExpoPalette.of(context);
    final accent = _accent;
    final success = pal.success;
    final error = pal.danger;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return ListView(
      controller: _practiceScroll,
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
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: accent,
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
                Icon(Icons.timer, size: 22, color: accent),
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
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accent),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_current + 1) / total,
                    minHeight: 5,
                    backgroundColor: onSurface.withValues(alpha: 0.12),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Question badge + bookmark/report actions — mirrors the chapter
        // practice screen.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: accent.withValues(alpha: 0.08),
              ),
              child: Text('Question ${_current + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accent)),
            ),
            Row(
              children: [
                _actionBox(_AfBookmarkButton(
                  key: ValueKey('af-practice:${q.questionId}'),
                  uid: AuthService.currentUser?.uid ?? '',
                  featureId: widget.featureId,
                  topicId: widget.topicId,
                  topicTitle: _displayTitle,
                  track: 'practice',
                  question: q,
                )),
                const SizedBox(width: 8),
                _actionBox(
                  IconButton(
                    onPressed: () => _reportQuestion(q),
                    icon: const Icon(Icons.flag_rounded, size: 19),
                    color: pal.textSecondary,
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
        // Question + options + explanation, animated on question change —
        // fade + slight slide, same as the chapter practice screen.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> animation) {
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
                _practiceQuestionCard(q),
                const SizedBox(height: 10),
                for (int oi = 0; oi < q.options.length; oi++)
                  _practiceOption(
                      q, oi, attempted, selected, wasCorrect, success, error),
                if (attempted)
                  _explanationCard(q, selected, wasCorrect, success, error),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 85,
              child: OutlinedButton.icon(
                onPressed: _current == 0
                    ? null
                    : () => _goToQuestion(-1),
                icon: const Icon(Icons.arrow_back, size: 19),
                label: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 135,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
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

  Widget _practiceQuestionCard(_Question q) {
    return Card(
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
    );
  }

  Widget _practiceOption(_Question q, int oi, bool attempted, int? selected,
      bool wasCorrect, Color success, Color error) {
    final isSelected = selected == oi;
    final isCorrect = oi == q.correctIndex;
    final accent = _accent;
    Color border;
    Color? bg;
    if (attempted && isCorrect) {
      border = success;
      bg = success.withValues(alpha: 0.1);
    } else if (attempted && isSelected && !isCorrect) {
      border = error;
      bg = error.withValues(alpha: 0.08);
    } else if (isSelected) {
      border = accent;
      bg = null;
    } else {
      border = Colors.grey.withValues(alpha: 0.35);
      bg = null;
    }
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final filled = isSelected || (attempted && isCorrect);
    // Keyed on the question id so each question change builds fresh tile
    // state and the stagger replays on every question.
    return _OptionStagger(
      key: ValueKey('${q.questionId}:$oi'),
      index: oi,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: bg ?? Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: attempted ? null : () => _selectPracticeOption(q, oi),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: border, width: 1.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? border : Colors.transparent,
                      border: Border.all(color: border, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        String.fromCharCode(65 + oi),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: filled
                                ? Colors.white
                                : onSurface.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(q.options[oi].text,
                        style:
                            const TextStyle(fontSize: 15, height: 1.35)),
                  ),
                  if (attempted && isCorrect)
                    Icon(Icons.check_circle, size: 22, color: success),
                  if (attempted && isSelected && !isCorrect)
                    Icon(Icons.cancel, size: 22, color: error),
                ],
              ),
            ),
          ),
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
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: success,
                  fontSize: 13),
            ),
          const SizedBox(height: 6),
          const Text('Explanation',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(q.explanation,
              style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: ExpoPalette.of(context).textSecondary)),
        ],
      ),
    );
  }

  Color _difficultyColor(String d) {
    final pal = ExpoPalette.of(context);
    switch (d.toLowerCase()) {
      case 'easy':
        return pal.success;
      case 'medium':
        return pal.warning;
      default:
        return pal.danger;
    }
  }

  // ============================== DIALOGS ==============================

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

/// Staggered option-tile entrance — fade + 12px slide-up, tiles start
/// ~70ms apart (index * 70). Each tile is keyed on the question id, so a
/// question change builds fresh State objects whose controllers replay the
/// animation from scratch on every question. Selecting an option rebuilds
/// with the same keys, so the animation does not replay mid-question.
/// Finite (280ms + stagger delay) — pumpAndSettle-safe.
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

/// Per-question bookmark toggle for additional-feature topics — the Flutter
/// equivalent of the Expo topic screen's BookmarkButton (context = the
/// track: 'read' | 'practice', kind 'question',
/// refId "${topicId}:${questionId}"). Bookmarks live at
/// users/{uid}/bookmarks with the same doc-id scheme as the Expo app
/// (`<track>__<safeSegment(refId)>`), so the Bookmarks screen lists them
/// without changes. UX mirrors the chapter practice bookmark: tap shows a
/// brief spinner, then a success toast; the Firestore write is
/// fire-and-forget and reverts the icon on failure.
class _AfBookmarkButton extends StatefulWidget {
  final String uid;
  final String featureId;
  final String topicId;
  final String topicTitle;
  final String track; // 'read' | 'practice'
  final _Question question;

  const _AfBookmarkButton({
    super.key,
    required this.uid,
    required this.featureId,
    required this.topicId,
    required this.topicTitle,
    required this.track,
    required this.question,
  });

  @override
  State<_AfBookmarkButton> createState() => _AfBookmarkButtonState();
}

class _AfBookmarkButtonState extends State<_AfBookmarkButton> {
  bool _saved = false;
  bool _busy = false;

  /// Pending "save confirmed" timer — cancelled if the background write
  /// fails first, or if the tap is superseded by a newer one.
  Timer? _saveTimer;

  /// Monotonic op id: guards the fire-and-forget save against a later
  /// remove/refresh so a stale failure can't clobber newer state.
  int _opId = 0;

  String get _refId => '${widget.topicId}:${widget.question.questionId}';

  /// Mirrors React's bookmarkDocId(): `<context>__<safeSegment(refId)>`.
  String get _docId {
    var ref = _refId
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ref.length > 90) ref = ref.substring(0, 90);
    if (ref.isEmpty) ref = 'item';
    return '${widget.track}__$ref';
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
      final q = widget.question;
      final modeLabel =
          widget.track == 'read' ? 'Read Mode' : 'Practice Mode';
      await FirestoreRest.setDocument(
        path,
        {
          'context': widget.track,
          'kind': 'question',
          'refId': _refId,
          'title': q.question,
          'preview': q.explanation,
          'sourceLabel': '${widget.featureId} · $modeLabel',
          'payload': {
            'question': q.question,
            'options': q.options.map((o) => o.text).toList(),
            'answerIndex': q.correctIndex,
            'explanation': q.explanation,
            'meta': [
              {'label': 'Topic', 'value': widget.topicTitle},
              {'label': 'Mode', 'value': modeLabel},
            ],
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
    final pal = ExpoPalette.of(context);
    return IconButton(
      onPressed: _busy ? null : _onTap,
      icon: _busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: pal.primary,
              ),
            )
          : Icon(
              _saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              size: 20),
      color: _saved ? pal.primary : pal.textSecondary,
      tooltip: _saved ? 'Remove bookmark' : 'Bookmark',
      padding: EdgeInsets.zero,
      constraints:
          const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}
