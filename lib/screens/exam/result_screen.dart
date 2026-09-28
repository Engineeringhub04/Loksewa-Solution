import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Result — mirrors app/result/[attemptId].tsx.
/// Score ring, correct/incorrect/unattempted stats, per-question review,
/// retake and back-to-home actions.
class ResultScreen extends StatefulWidget {
  final String attemptId;
  const ResultScreen({super.key, required this.attemptId});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  AttemptResult? _attempt;
  List<MockQuestion> _questions = const [];
  bool _loading = true;
  String? _error;
  bool _showReview = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      final attempt = uid.isEmpty
          ? null
          : await fetchAttemptResult(uid, widget.attemptId);
      if (attempt == null) throw Exception('Attempt not found');
      final questions = await fetchQuestionsByIds(
          attempt.answers.map((a) => a.questionId).toList());
      if (!mounted) return;
      setState(() {
        _attempt = attempt;
        _questions = questions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the result.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Result'),
          Expanded(
            child: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Calculating result...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _resultView(),
          ),
        ],
      ),
    );
  }

  Widget _resultView() {
    final a = _attempt!;
    final percent = a.totalMarks > 0 ? a.score / a.totalMarks : 0.0;
    final minutes = a.timeTakenSeconds ~/ 60;
    final seconds = a.timeTakenSeconds % 60;
    final passColor =
        percent >= 0.5 ? Colors.green : Colors.red;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    strokeWidth: 12,
                    backgroundColor: Colors.grey.shade200,
                    color: passColor,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${a.score}/${a.totalMarks}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('${(percent * 100).round()}%'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(a.examTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Time taken: ${minutes}m ${seconds}s'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Correct', '${a.correctCount}', Colors.green),
                _stat('Incorrect', '${a.incorrectCount}', Colors.red),
                _stat('Unattempted', '${a.unattemptedCount}', Colors.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => setState(() => _showReview = !_showReview),
          child: Text(_showReview ? 'Hide Review' : 'Review Answers'),
        ),
        if (_showReview) ...[
          const SizedBox(height: 12),
          ..._questions.map((q) {
            AttemptAnswer? answer;
            for (final x in a.answers) {
              if (x.questionId == q.id) {
                answer = x;
                break;
              }
            }
            final userIndex = answer?.selectedIndex;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.text,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      'Your answer: ${userIndex != null && userIndex < q.options.length ? q.options[userIndex] : '—'}',
                    ),
                    Text(
                      'Correct answer: ${q.correctIndex < q.options.length ? q.options[q.correctIndex] : '—'}',
                      style: const TextStyle(color: Colors.green),
                    ),
                    if (q.explanation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(q.explanation,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () =>
              context.go('/mock-test/${a.examId}/instructions'),
          child: const Text('Retake Test'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}
