import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Exam summary — mirrors app/exam/[setId]/summary.tsx.
/// Score breakdown of the latest attempt + retake/review/ranking actions.
class ExamSummaryScreen extends StatefulWidget {
  final String setId;
  const ExamSummaryScreen({super.key, required this.setId});

  @override
  State<ExamSummaryScreen> createState() => _ExamSummaryScreenState();
}

class _ExamSummaryScreenState extends State<ExamSummaryScreen> {
  ExamSet? _set;
  ExamAttempt? _attempt;
  bool _loading = true;
  String? _error;
  bool _unlocked = false;

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
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      final uid = AuthService.currentUser?.uid ?? '';
      final attempts =
          uid.isEmpty ? <ExamAttempt>[] : await fetchAttemptsForSet(uid, widget.setId);
      if (!mounted) return;
      setState(() {
        _set = set;
        _attempt = attempts.isEmpty ? null : attempts.first;
        _unlocked = areResultsUnlocked(set, DateTime.now());
        _loading = false;
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
      body: Column(
        children: [
          const SubpageHeader(title: 'Result'),
          Expanded(
            child: _loading
          ? const PreloadingWidget(
            tinted: false,
            label: 'Loading Result...',
          )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _attempt == null
                  ? const Center(child: Text('No attempt found.'))
                  : _summary(),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final set = _set!;
    final a = _attempt!;
    final passColor = a.passed ? Colors.green : Colors.red;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(set.title,
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
                        value: a.score / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey.shade200,
                        color: passColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${a.score}%',
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        Text(a.passed ? 'PASSED' : 'FAILED',
                            style: TextStyle(
                                color: passColor,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Time taken: ${a.timeTakenSeconds ~/ 60}m ${a.timeTakenSeconds % 60}s',
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
                _stat('Correct', '${a.correct}', Colors.green),
                _stat('Incorrect', '${a.incorrect}', Colors.red),
                _stat('Skipped', '${a.skipped}', Colors.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => context.go('/exam/${set.id}/quiz'),
          icon: const Icon(Icons.refresh),
          label: const Text('Retake Test'),
        ),
        const SizedBox(height: 8),
        if (_unlocked)
          OutlinedButton.icon(
            onPressed: () => context.go('/exam/${set.id}/review'),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Review Answers'),
          ),
        if (_unlocked) const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/exam/${set.id}/ranking'),
          icon: const Icon(Icons.leaderboard_outlined),
          label: const Text('View Ranking'),
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
