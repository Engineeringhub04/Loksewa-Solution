import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Question of the day — mirrors app/question-of-the-day.tsx.
/// Daily stats strip, today's question, one answer, explanation + result.
class QuestionOfDayScreen extends StatefulWidget {
  const QuestionOfDayScreen({super.key});

  @override
  State<QuestionOfDayScreen> createState() => _QuestionOfDayScreenState();
}

class _QuestionOfDayScreenState extends State<QuestionOfDayScreen> {
  QotdQuestion? _question;
  QotdResult? _result;
  QotdSummary? _summary;
  String _courseName = '';
  String _subcourseName = '';
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Kathmandu midnight delay for the auto-refresh timer (approx).
  Duration _midnightDelay() {
    final nowKathmandu =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 45));
    final nextMidnight = DateTime(
            nowKathmandu.year, nowKathmandu.month, nowKathmandu.day)
        .add(const Duration(days: 1));
    return nextMidnight.difference(nowKathmandu);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      final profile = uid.isEmpty ? null : await fetchUserProfile(uid);
      final courseId = profile?.courseId ?? '';
      final subcourseId = profile?.subcourseId ?? '';
      if (courseId.isEmpty || subcourseId.isEmpty) {
        throw Exception('Select your Course and Sub-course first.');
      }
      final question = await fetchTodayQuestion(courseId, subcourseId);
      QotdResult? result;
      QotdSummary summary = QotdSummary(
          totalAttempts: 0, correct: 0, averagePercent: 0);
      if (uid.isNotEmpty) {
        summary = await fetchQotdSummary(uid);
        if (question != null) {
          // Find today's result doc by prefix on attempt id pattern
          // {dateKey}__{courseId}__{subcourseId}__v* — list and match.
          final docs = await ExamRest.runQuery(
            'questionofdata',
            parent: 'users/$uid',
            where: ExamRest.fieldFilter('dateKey', 'EQUAL', todayDateKey()),
            limit: 5,
          );
          final match = docs.where((d) =>
              _str(d['courseId']) == courseId &&
              _str(d['subcourseId']) == subcourseId);
          if (match.isNotEmpty) {
            result = QotdResult.fromMap(match.first);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _question = question;
        _result = result;
        _summary = summary;
        _courseName = profile?.courseId ?? '';
        _subcourseName = profile?.subcourseId ?? '';
        _loading = false;
        if (question == null) {
          _error = 'No question added for today.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _str(dynamic v) => v is String ? v : '';

  Future<void> _choose(QotdOption option) async {
    if (_result != null || _submitting || _question == null) return;
    setState(() => _submitting = true);
    try {
      final uid = AuthService.currentUser!.uid;
      final q = _question!;
      final attemptId = '${todayDateKey()}__${q.courseId}__${q.subcourseId}__v1';
      final summary = await answerQotd(
        uid: uid,
        attemptId: attemptId,
        question: q,
        selectedOptionId: option.id,
      );
      if (!mounted) return;
      setState(() {
        _result = QotdResult(
          selectedOptionId: option.id,
          isCorrect: option.id == q.correctOptionId,
          answeredAt: DateTime.now(),
        );
        _summary = summary;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save answer.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Question of the Day'),
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _content(),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final q = _question!;
    final completed = _result != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statsCard(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(label: Text(q.difficulty.toUpperCase())),
                    const SizedBox(width: 8),
                    if (q.showingDate.isNotEmpty) Text(q.showingDate),
                  ],
                ),
                const SizedBox(height: 12),
                Text(q.content,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Choose the best answer',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...q.options.map((o) {
          final isSel = _result?.selectedOptionId == o.id;
          final isCorrect = o.id == q.correctOptionId;
          Color? border;
          Color? bg;
          if (completed && isCorrect) {
            border = Colors.green;
            bg = Colors.green.shade50;
          } else if (completed && isSel) {
            border = Colors.red;
            bg = Colors.red.shade50;
          }
          return Card(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border ?? Colors.grey.shade300),
            ),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(o.id.isNotEmpty ? o.id[0] : '?'),
              ),
              title: Text(o.content),
              trailing: completed && isCorrect
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : completed && isSel
                      ? const Icon(Icons.cancel, color: Colors.red)
                      : null,
              onTap: completed || _submitting ? null : () => _choose(o),
            ),
          );
        }),
        if (completed) ...[
          const SizedBox(height: 16),
          Card(
            color: _result!.isCorrect
                ? Colors.green.shade50
                : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _result!.isCorrect ? 'CORRECT ANSWER' : 'INCORRECT ANSWER',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _result!.isCorrect
                            ? Colors.green.shade800
                            : Colors.orange.shade800),
                  ),
                  const SizedBox(height: 8),
                  const Text('Explanation',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(q.explanation),
                  const SizedBox(height: 8),
                  const Text(
                      'Completed for today. Come back tomorrow for a new question. Thank you!',
                      style: TextStyle(color: Colors.blue)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statsCard() {
    final s = _summary!;
    return Card(
      color: const Color(0xFF0B1F51),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('YOUR DAILY PROGRESS',
                style: TextStyle(
                    color: Colors.lightBlue, letterSpacing: 1.1, fontSize: 11)),
            const SizedBox(height: 4),
            Text('$_courseName · $_subcourseName',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('${s.totalAttempts}', 'Total Attempts'),
                _stat('${s.correct}', 'Correct'),
                _stat('${s.averagePercent}%', 'Average'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );
}
