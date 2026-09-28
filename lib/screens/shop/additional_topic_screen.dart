// Additional-feature topic: read vs practice tracks.
// Mirrors app/additional-features/[featureId]/[topicId].tsx.
// Bank doc: app_additional_feature_question_banks/
//   {featureId}__all__all__{topicId}
// Read track: question list with expandable answers (correct option +
// explanation). Practice track: shuffled options, one-question pager, a
// daily limit of 50 questions, progress persisted via PrefsService,
// prev/next navigation, a leave-confirm dialog, and a correct/incorrect
// explanation card after each answer.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

const int _dailyLimit = 50;

class AdditionalTopicScreen extends StatefulWidget {
  final String featureId;
  final String topicId;
  const AdditionalTopicScreen(
      {super.key, required this.featureId, required this.topicId});

  @override
  State<AdditionalTopicScreen> createState() => _AdditionalTopicScreenState();
}

class _Question {
  final String id;
  final String text;
  final List<Map<String, String>> options;
  final int correctIndex;
  final String explanation;
  _Question(this.id, this.text, this.options, this.correctIndex,
      this.explanation);
}

class _AdditionalTopicScreenState extends State<AdditionalTopicScreen> {
  late final Future<List<_Question>> _future = _load();
  String _mode = 'read'; // read | practice

  // Practice state
  int _index = 0;
  List<int> _shuffled = [];
  int? _selected;
  bool _answered = false;
  int _correct = 0;
  int _attemptedToday = 0;
  final Set<String> _attemptedIds = {};

  Future<List<_Question>> _load() async {
    final token = await AuthService.getValidIdToken();
    final bank = await FirestoreRest.getDocument(
        'app_additional_feature_question_banks/${widget.featureId}__all__all__${widget.topicId}',
        idToken: token);
    final raw =
        ((bank?['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [])
          ..sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    final today = _dateKey();
    final attemptedRaw =
        await PrefsService.getString(_practiceKey(today)) ?? '';
    _attemptedToday =
        attemptedRaw.isEmpty ? 0 : attemptedRaw.split(',').length;
    _attemptedIds.addAll(
        attemptedRaw.isEmpty ? <String>[] : attemptedRaw.split(','));
    return raw.map((q) {
      final opts = ((q['options'] as List?)?.cast<Map>() ?? [])
          .map((o) => {
                'id': o['id']?.toString() ?? '',
                'text': o['text']?.toString() ?? ''
              })
          .toList();
      var correct = _num(q['correctOption']).toInt();
      final cid = q['correctOptionId']?.toString();
      if (cid != null && cid.isNotEmpty) {
        final idx = opts.indexWhere((o) => o['id'] == cid);
        if (idx >= 0) correct = idx;
      }
      return _Question(
        q['questionId']?.toString() ?? '',
        q['question']?.toString() ?? '',
        opts,
        correct.clamp(0, opts.isEmpty ? 0 : opts.length - 1),
        q['explanation']?.toString() ?? '',
      );
    }).toList();
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;

  String _dateKey([DateTime? d]) {
    final n = d ?? DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _practiceKey(String date) =>
      'af_practice_${widget.featureId}_${widget.topicId}_$date';

  String _progressKey() =>
      'af_progress_${widget.featureId}_${widget.topicId}';

  void _startPractice(List<_Question> qs) {
    if (qs.isEmpty) return;
    if (_attemptedToday >= _dailyLimit) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Daily practice limit reached (50 questions). Come back tomorrow!')));
      return;
    }
    final order = List<int>.generate(
        qs[_index.clamp(0, qs.length - 1)].options.length, (i) => i)
      ..shuffle();
    setState(() {
      _shuffled = order;
      _selected = null;
      _answered = false;
    });
  }

  Future<void> _answer(List<_Question> qs, int optPos) async {
    if (_answered) return;
    final q = qs[_index];
    final wasCorrect = _shuffled[optPos] == q.correctIndex;
    setState(() {
      _selected = optPos;
      _answered = true;
      if (wasCorrect) _correct++;
    });
    // Persist daily progress.
    _attemptedIds.add(q.id);
    final today = _dateKey();
    await PrefsService.setString(
        _practiceKey(today), _attemptedIds.join(','));
    _attemptedToday = _attemptedIds.length;
    // Persist topic progress fraction (unique attempted / total).
    final frac = (qs.isEmpty ? 0 : _attemptedIds.length / qs.length)
        .clamp(0.0, 1.0);
    final prev = double.tryParse(
            await PrefsService.getString(_progressKey()) ?? '') ??
        0.0;
    if (frac > prev) {
      await PrefsService.setString(_progressKey(), frac.toString());
    }
  }

  void _go(List<_Question> qs, int delta) {
    final next = (_index + delta).clamp(0, qs.length - 1);
    if (next == _index) return;
    if (_attemptedToday >= _dailyLimit && delta > 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Daily practice limit reached (50 questions).')));
      return;
    }
    setState(() {
      _index = next;
      _selected = null;
      _answered = false;
    });
    _startPractice(qs);
  }

  Future<bool> _confirmLeave() async {
    if (_mode != 'practice') return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave practice?'),
        content: const Text(
            'Your progress for today is saved. Leave this session?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave')),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Topic'),
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<List<_Question>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          'Could not load questions.\n${snap.error}',
                          textAlign: TextAlign.center)));
            }
            final qs = snap.data!;
            if (qs.isEmpty) {
              return const Center(
                  child: Text('No questions in this topic yet.'));
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'read',
                          label: Text('Read'),
                          icon: Icon(Icons.menu_book)),
                      ButtonSegment(
                          value: 'practice',
                          label: Text('Practice'),
                          icon: Icon(Icons.quiz)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _mode = s.first;
                        _index = 0;
                        _selected = null;
                        _answered = false;
                        _correct = 0;
                      });
                      if (_mode == 'practice') _startPractice(qs);
                    },
                  ),
                ),
                if (_mode == 'practice')
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            'Today: $_attemptedToday/$_dailyLimit',
                            style: const TextStyle(
                                color: Colors.black54)),
                        Text('Score: $_correct',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                Expanded(
                  child: _mode == 'read'
                      ? _readList(qs)
                      : _practicePager(qs),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _readList(List<_Question> qs) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: qs.length,
        itemBuilder: (_, i) {
          final q = qs[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              title: Text('Q${i + 1}. ${q.text}',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...q.options.asMap().entries.map((e) {
                        final isCorrect = e.key == q.correctIndex;
                        return Container(
                          margin:
                              const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isCorrect
                                ? Colors.green.shade50
                                : Colors.grey.shade100,
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                                color: isCorrect
                                    ? Colors.green
                                    : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              if (isCorrect)
                                const Icon(Icons.check_circle,
                                    color: Colors.green,
                                    size: 18),
                              if (isCorrect)
                                const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      '${String.fromCharCode(65 + e.key)}. ${e.value['text']}')),
                            ],
                          ),
                        );
                      }),
                      if (q.explanation.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius:
                                  BorderRadius.circular(8)),
                          child: Text(
                              'Explanation: ${q.explanation}'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _practicePager(List<_Question> qs) {
    final q = qs[_index.clamp(0, qs.length - 1)];
    if (_shuffled.length != q.options.length) {
      // Initialise shuffle on first build.
      _shuffled = List<int>.generate(q.options.length, (i) => i)..shuffle();
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Question ${_index + 1} of ${qs.length}',
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                Text(q.text,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ..._shuffled.asMap().entries.map((e) {
                  final optIdx = e.value;
                  final pos = e.key;
                  Color? bg;
                  IconData? icon;
                  if (_answered) {
                    if (optIdx == q.correctIndex) {
                      bg = Colors.green.shade100;
                      icon = Icons.check_circle;
                    } else if (pos == _selected) {
                      bg = Colors.red.shade100;
                      icon = Icons.cancel;
                    }
                  } else if (pos == _selected) {
                    bg = AppColors.navy.withValues(alpha: 0.08);
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: bg ?? Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.all(14),
                        alignment: Alignment.centerLeft,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            side: const BorderSide(
                                color: Colors.black12)),
                        elevation: 0,
                      ),
                      onPressed: _answered
                          ? null
                          : () => _answer(qs, pos),
                      child: Row(
                        children: [
                          if (icon != null)
                            Icon(icon,
                                color: optIdx == q.correctIndex
                                    ? Colors.green
                                    : Colors.red),
                          if (icon != null)
                            const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  '${String.fromCharCode(65 + pos)}. ${q.options[optIdx]['text']}')),
                        ],
                      ),
                    ),
                  );
                }),
                if (_answered) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (_selected != null &&
                              _shuffled[_selected!] ==
                                  q.correctIndex)
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: (_selected != null &&
                                  _shuffled[_selected!] ==
                                      q.correctIndex)
                              ? Colors.green
                              : Colors.red),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_selected != null &&
                                  _shuffled[_selected!] ==
                                      q.correctIndex)
                              ? 'Correct!'
                              : 'Incorrect.',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (_selected != null &&
                                      _shuffled[_selected!] ==
                                          q.correctIndex)
                                  ? Colors.green.shade800
                                  : Colors.red.shade800),
                        ),
                        Text(
                            'Answer: ${String.fromCharCode(65 + _shuffled.indexOf(q.correctIndex))}. ${q.options[q.correctIndex]['text']}'),
                        if (q.explanation.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(q.explanation),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _index > 0 ? () => _go(qs, -1) : null,
                  child: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white),
                  onPressed: _index < qs.length - 1
                      ? () => _go(qs, 1)
                      : null,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
