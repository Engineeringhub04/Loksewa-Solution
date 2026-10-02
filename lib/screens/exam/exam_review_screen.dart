import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Exam answer review — mirrors app/exam/[setId]/review.tsx.
///
/// Answers arrive via route params (from the summary or a specific attempt
/// on the detail screen), falling back to the user's latest attempt.
/// Stats header, per-question cards with Correct/Wrong tags, a skipped note
/// and the explanation. Locked until the exam window closes. The list is a
/// lazy ListView (React uses FlatList) with no entering animations — cheap
/// on low-end phones.
class ExamReviewScreen extends StatefulWidget {
  final String setId;
  final String? answers; // comma-separated, -1 = skipped
  final String? attemptLabel;
  final String? attemptDate;

  const ExamReviewScreen({
    super.key,
    required this.setId,
    this.answers,
    this.attemptLabel,
    this.attemptDate,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  ExamSet? _set;
  List<int> _answers = const [];
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
          _lockedMessage = AppLanguage.tr(
              'Answers will be available for review once the exam window closes.',
              'परीक्षा समय सकिएपछि उत्तर समीक्षा उपलब्ध हुनेछ।');
        });
        return;
      }
      List<int> answers;
      if (widget.answers != null && widget.answers!.isNotEmpty) {
        answers = widget.answers!
            .split(',')
            .map((s) => int.tryParse(s.trim()) ?? -1)
            .toList();
      } else {
        // Fallback: latest attempt.
        final uid = AuthService.currentUser?.uid ?? '';
        final attempts = uid.isEmpty
            ? <ExamAttempt>[]
            : await fetchAttemptsForSet(uid, widget.setId);
        if (attempts.isEmpty) {
          if (!mounted) return;
          setState(() {
            _set = set;
            _loading = false;
          });
          return;
        }
        attempts.sort((a, b) => b.attemptNumber.compareTo(a.attemptNumber));
        answers = attempts.first.answers;
      }
      final padded = List<int>.filled(set.questions.length, -1);
      for (var i = 0; i < padded.length && i < answers.length; i++) {
        padded[i] = answers[i];
      }
      if (!mounted) return;
      setState(() {
        _set = set;
        _answers = padded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load the review.', 'समीक्षा लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Review Answers', 'उत्तर समीक्षा')),
          Expanded(
            child: _loading
                ? const PreloadingWidget(
                    tinted: false,
                    label: 'Loading Answers...',
                  )
                : _lockedMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline,
                                  size: 48, color: Color(0xFF1E3A8A)),
                              const SizedBox(height: 16),
                              Text(_lockedMessage!,
                                  textAlign: TextAlign.center),
                            ],
                          ),
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
                                    onPressed: _load,
                                    child: const Text('Retry')),
                              ],
                            ),
                          )
                        : _answers.isEmpty
                            ? Center(
                                child: Text(AppLanguage.tr(
                                    'No attempt found for this exam.',
                                    'यस परीक्षाको प्रयास भेटिएन।')))
                            : _reviewList(),
          ),
        ],
      ),
    );
  }

  Widget _reviewList() {
    final set = _set!;
    final score = scoreExamAttempt(
      set.questions,
      _answers,
      set.passPercent,
    );
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: set.questions.length + 1,
      itemBuilder: (c, i) {
        if (i == 0) return _statsHeader(set, score);
        return _questionCard(set.questions[i - 1], _answers[i - 1], i);
      },
    );
  }

  Widget _statsHeader(ExamSet set, ScoreBreakdown s) {
    final label = widget.attemptLabel;
    final date = widget.attemptDate;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null && label.isNotEmpty) ...[
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              if (date != null && date.isNotEmpty)
                Text(date,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(AppLanguage.tr('Total', 'जम्मा'),
                    '${set.questions.length}', const Color(0xFF0F172A)),
                _stat(AppLanguage.tr('Correct', 'सही'), '${s.correct}',
                    const Color(0xFF16A34A)),
                _stat(AppLanguage.tr('Incorrect', 'गलत'), '${s.incorrect}',
                    const Color(0xFFDC2626)),
                _stat(AppLanguage.tr('Skipped', 'छोडियो'), '${s.skipped}',
                    Colors.grey),
                _stat(AppLanguage.tr('Score', 'स्कोर'), '${s.percent}%',
                    const Color(0xFF1D4ED8)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _questionCard(ExamQuestion q, int chosen, int number) {
    final skipped = chosen < 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('$number',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ),
                Expanded(
                  child: Text(q.question,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (skipped)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  AppLanguage.tr('Skipped — no answer given.',
                      'छोडियो — उत्तर दिइएन।'),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ...List.generate(q.options.length, (oi) {
              final isChosen = oi == chosen;
              final isCorrect = oi == q.correctIndex;
              Color? bg;
              Color border = Colors.grey.shade300;
              if (isCorrect) {
                bg = Colors.green.shade50;
                border = Colors.green;
              } else if (isChosen) {
                bg = Colors.red.shade50;
                border = Colors.red;
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(q.options[oi])),
                    if (isCorrect)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                            AppLanguage.tr('Correct', 'सही'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      )
                    else if (isChosen)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(AppLanguage.tr('Wrong', 'गलत'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              );
            }),
            if (q.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  '${AppLanguage.tr('Explanation', 'व्याख्या')}: ${q.explanation}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
