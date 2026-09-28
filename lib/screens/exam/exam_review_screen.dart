import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Exam answer review — mirrors app/exam/[setId]/review.tsx.
/// Rebuilds the latest attempt exactly as answered; locked until the exam
/// window closes (results unlock).
class ExamReviewScreen extends StatefulWidget {
  final String setId;
  const ExamReviewScreen({super.key, required this.setId});

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  ExamSet? _set;
  ExamAttempt? _attempt;
  bool _loading = true;
  String? _error;
  String? _lockedMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _lockedMessage = null;
    });
    try {
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      if (!areResultsUnlocked(set, DateTime.now())) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _lockedMessage =
              'Answers will be available for review once the exam window closes.';
        });
        return;
      }
      final uid = AuthService.currentUser?.uid ?? '';
      final attempts =
          uid.isEmpty ? <ExamAttempt>[] : await fetchAttemptsForSet(uid, widget.setId);
      if (!mounted) return;
      setState(() {
        _set = set;
        _attempt = attempts.isEmpty ? null : attempts.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the review.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Review Answers'),
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lockedMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_lockedMessage!,
                        textAlign: TextAlign.center),
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
                  : _attempt == null
                      ? const Center(
                          child: Text('No attempt found for this exam.'))
                      : _reviewList(),
          ),
        ],
      ),
    );
  }

  Widget _reviewList() {
    final set = _set!;
    final attempt = _attempt!;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: set.questions.length,
      itemBuilder: (c, i) {
        final q = set.questions[i];
        final chosen = i < attempt.answers.length ? attempt.answers[i] : -1;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q ${i + 1}. ${q.question}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...List.generate(q.options.length, (oi) {
                  final isChosen = oi == chosen;
                  final isCorrect = oi == q.correctIndex;
                  Color? bg;
                  if (isCorrect) bg = Colors.green.shade50;
                  if (isChosen && !isCorrect) bg = Colors.red.shade50;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCorrect
                            ? Colors.green
                            : isChosen
                                ? Colors.red
                                : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(q.options[oi])),
                        if (isCorrect)
                          const Icon(Icons.check_circle,
                              size: 18, color: Colors.green),
                        if (isChosen && !isCorrect)
                          const Icon(Icons.cancel,
                              size: 18, color: Colors.red),
                      ],
                    ),
                  );
                }),
                if (q.explanation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Explanation: ${q.explanation}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
