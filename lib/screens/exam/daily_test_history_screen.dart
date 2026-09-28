import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';

/// Daily test attempt history — mirrors app/daily-test/history.tsx.
class DailyTestHistoryScreen extends StatefulWidget {
  const DailyTestHistoryScreen({super.key});

  @override
  State<DailyTestHistoryScreen> createState() => _DailyTestHistoryScreenState();
}

class _DailyTestHistoryScreenState extends State<DailyTestHistoryScreen> {
  List<DailyTestResult> _results = const [];
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
      final results =
          uid.isEmpty ? <DailyTestResult>[] : await fetchDailyTestResults(uid);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load history.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Test History'),
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
              : _results.isEmpty
                  ? const Center(
                      child: Text('No daily test attempts yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _results.length,
                      itemBuilder: (c, i) {
                        final r = _results[i];
                        return Card(
                          child: ListTile(
                            title: Text(r.modelName),
                            subtitle: Text(
                                '${r.correct}/${r.totalQuestions} correct · ${r.timeTakenSeconds ~/ 60}m ${r.timeTakenSeconds % 60}s'),
                            trailing: Text('${r.score}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            onTap: () => context
                                .go('/daily-test/${r.modelId}/summary'),
                          ),
                        );
                      },
                    ),
    );
  }
}
