import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Subject practice — mirrors app/subjects/practice.tsx.
/// MCQ quiz: one question at a time, explanations, prev/next, score at end.
/// Question set doc: app_subject_cucqdata_Allmode/{course}__{subcourse}__
/// {subject}__{unit|no-unit}__{chapter}__practice
class SubjectPracticeScreen extends StatefulWidget {
  final String courseId;
  final String subcourseId;
  final String subjectId;
  final String chapterId;
  final String? unitId;
  final String? subjectName;
  final String? chapterName;
  final String? unitName;

  const SubjectPracticeScreen({
    super.key,
    required this.courseId,
    required this.subcourseId,
    required this.subjectId,
    required this.chapterId,
    this.unitId,
    this.subjectName,
    this.chapterName,
    this.unitName,
  });

  @override
  State<SubjectPracticeScreen> createState() => _SubjectPracticeScreenState();
}

class _SubjectPracticeScreenState extends State<SubjectPracticeScreen> {
  late Future<List<_Question>> _future;
  int _index = 0;
  final Map<int, int> _answers = {};
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  static String _canon(String v) {
    final parts = v.split('__').where((p) => p.isNotEmpty).toList();
    var id = parts.isNotEmpty ? parts.last : v;
    if (id == 'job-based-knowledge') id = 'technical-subject';
    return id;
  }

  Future<List<_Question>> _load() async {
    final token = await AuthService.getValidIdToken();
    final subjectId = _canon(widget.subjectId);
    final chapterId = _canon(widget.chapterId);
    final unitId =
        widget.unitId == null || widget.unitId!.isEmpty ? null : _canon(widget.unitId!);
    final docId =
        '${widget.courseId}__${widget.subcourseId}__$subjectId'
        '__${unitId ?? 'no-unit'}__${chapterId}__practice';
    final doc = await FirestoreRest.getDocument(
        'app_subject_cucqdata_Allmode/$docId',
        idToken: token);
    if (doc == null) return [];
    return _parseQuestions(doc);
  }

  static List<_Question> _parseQuestions(Map<String, dynamic> doc) {
    final raw = doc['questions'];
    if (raw is! List) return [];
    final out = <_Question>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map<String, dynamic>) continue;
      final opts = _readOptions(item['options']);
      final correctId = (item['correctOptionId'] as String?) ?? '';
      var correctIndex = (item['correctIndex'] as num?)?.toInt() ?? 0;
      if (correctId.isNotEmpty) {
        final found = opts.indexWhere((o) => o.id == correctId);
        if (found >= 0) correctIndex = found;
      }
      if (correctIndex < 0 || correctIndex >= opts.length) correctIndex = 0;
      final isActive = item['isActive'] != false &&
          (doc['isPublished'] != false);
      if (!isActive) continue;
      out.add(_Question(
        text: (item['questionNe'] as String?) ??
            (item['questionEn'] as String?) ??
            (item['text'] as String?) ??
            '',
        options: opts.map((o) => o.text).toList(),
        correctIndex: correctIndex,
        explanation: (item['explanationNe'] as String?) ??
            (item['explanationEn'] as String?) ??
            (item['explanation'] as String?) ??
            '',
        difficulty: (item['difficulty'] as String?) ?? 'easy',
        order: (item['order'] as num?)?.toInt() ?? (i + 1),
      ));
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  static List<_Opt> _readOptions(dynamic raw) {
    final out = <_Opt>[];
    if (raw is! List) return out;
    for (var i = 0; i < raw.length; i++) {
      final o = raw[i];
      if (o is String) {
        out.add(_Opt(String.fromCharCode(65 + i), o));
      } else if (o is Map<String, dynamic>) {
        out.add(_Opt(
          (o['id'] as String?) ?? String.fromCharCode(65 + i),
          (o['textEn'] as String?) ?? (o['text'] as String?) ?? '',
        ));
      }
    }
    return out;
  }

  int _score(List<_Question> qs) {
    var s = 0;
    for (final e in _answers.entries) {
      if (e.value == qs[e.key].correctIndex) s++;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterName ?? 'Practice'),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load questions.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final qs = snap.data ?? [];
          if (qs.isEmpty) {
            return const Center(
                child: Text('No practice questions yet.',
                    style: TextStyle(color: Colors.grey)));
          }
          if (_finished) return _results(qs);
          return _quiz(qs);
        },
      ),
    );
  }

  Widget _quiz(List<_Question> qs) {
    final q = qs[_index];
    final selected = _answers[_index];
    final answered = selected != null;
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index + 1) / qs.length,
          backgroundColor: Colors.grey.shade200,
          color: AppColors.navy,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text('Question ${_index + 1}/${qs.length}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _diffColor(q.difficulty).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(q.difficulty,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _diffColor(q.difficulty))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(q.text, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              ...List.generate(q.options.length, (i) {
                final isCorrect = i == q.correctIndex;
                final isSelected = selected == i;
                Color? bg;
                Color border = Colors.grey.shade300;
                if (answered) {
                  if (isCorrect) {
                    bg = Colors.green.shade50;
                    border = Colors.green;
                  } else if (isSelected) {
                    bg = Colors.red.shade50;
                    border = Colors.red;
                  }
                } else if (isSelected) {
                  border = AppColors.navy;
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: border, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: answered && isCorrect
                          ? Colors.green
                          : answered && isSelected
                              ? Colors.red
                              : AppColors.navy.withValues(alpha: 0.1),
                      child: Text(String.fromCharCode(65 + i),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: answered && (isCorrect || isSelected)
                                  ? Colors.white
                                  : AppColors.navy)),
                    ),
                    title: Text(q.options[i]),
                    trailing: answered && isCorrect
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : answered && isSelected
                            ? const Icon(Icons.cancel, color: Colors.red)
                            : null,
                    onTap: answered
                        ? null
                        : () => setState(() => _answers[_index] = i),
                  ),
                );
              }),
              if (answered && q.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Explanation',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(q.explanation),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index > 0
                        ? () => setState(() => _index--)
                        : null,
                    child: const Text('Previous'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white),
                    onPressed: () {
                      if (_index < qs.length - 1) {
                        setState(() => _index++);
                      } else {
                        setState(() => _finished = true);
                      }
                    },
                    child: Text(
                        _index < qs.length - 1 ? 'Next' : 'Finish'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _results(List<_Question> qs) {
    final score = _score(qs);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events,
                size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            Text('$score / ${qs.length}',
                style: const TextStyle(
                    fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              score == qs.length
                  ? 'Perfect! 🎉'
                  : score >= qs.length / 2
                      ? 'Good job! Keep going.'
                      : 'Keep practicing — you\'ll get there.',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white),
              onPressed: () => setState(() {
                _index = 0;
                _answers.clear();
                _finished = false;
              }),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Color _diffColor(String d) {
    switch (d) {
      case 'hard':
        return Colors.red;
      case 'medium':
        return AppColors.accent;
      default:
        return Colors.green;
    }
  }
}

class _Opt {
  final String id;
  final String text;
  const _Opt(this.id, this.text);
}

class _Question {
  final String text;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String difficulty;
  final int order;

  const _Question({
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
    required this.order,
  });
}
