import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';

/// Daily test answer review — mirrors app/daily-test/[modelId]/review.tsx.
class DailyReviewScreen extends StatefulWidget {
  final String modelId;
  const DailyReviewScreen({super.key, required this.modelId});

  @override
  State<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends State<DailyReviewScreen> {
  DailyTestModel? _model;
  DailyTestResult? _result;
  bool _loading = true;
  String? _error;

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
      final model = await fetchDailyTestModel(widget.modelId);
      if (model == null) throw Exception('Model not found');
      final result = uid.isEmpty
          ? null
          : await fetchDailyTestResultForModel(uid, widget.modelId);
      if (!mounted) return;
      setState(() {
        _model = model;
        _result = result;
        _loading = false;
        if (result == null) _error = 'No attempt found for this test.';
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
      appBar: AppBar(
        title: const Text('Review Answers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _model!.questions.length,
                  itemBuilder: (c, i) {
                    final q = _model!.questions[i];
                    final chosen = i < _result!.answers.length
                        ? _result!.answers[i]
                        : -1;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Q ${i + 1}. ${q.question}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
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
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
