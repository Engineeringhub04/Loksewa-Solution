import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';

/// Daily test summary — mirrors app/daily-test/[modelId]/summary.tsx.
class DailySummaryScreen extends StatefulWidget {
  final String modelId;
  const DailySummaryScreen({super.key, required this.modelId});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
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
        if (result == null) _error = 'No result found for this test.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the summary.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        automaticallyImplyLeading: false,
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
              : _summary(),
    );
  }

  Widget _summary() {
    final model = _model!;
    final r = _result!;
    final passed = r.score >= model.passPercent;
    final passColor = passed ? Colors.green : Colors.red;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(model.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: r.score / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey.shade200,
                        color: passColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${r.score}%',
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        Text(passed ? 'PASSED' : 'FAILED',
                            style: TextStyle(
                                color: passColor,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Time taken: ${r.timeTakenSeconds ~/ 60}m ${r.timeTakenSeconds % 60}s',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Correct', '${r.correct}', Colors.green),
                _stat('Incorrect', '${r.incorrect}', Colors.red),
                _stat('Skipped', '${r.skipped}', Colors.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => context.go('/daily-test/${model.id}/review'),
          icon: const Icon(Icons.rate_review_outlined),
          label: const Text('Review Answers'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.go('/daily-test'),
          child: const Text('Back to Daily Test'),
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
