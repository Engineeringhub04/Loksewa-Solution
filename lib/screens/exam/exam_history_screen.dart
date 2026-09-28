import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';

/// Exam history — mirrors app/exam-history.tsx.
/// All mock-test attempts for the user, newest first.
class ExamHistoryScreen extends StatefulWidget {
  const ExamHistoryScreen({super.key});

  @override
  State<ExamHistoryScreen> createState() => _ExamHistoryScreenState();
}

class _ExamHistoryScreenState extends State<ExamHistoryScreen> {
  List<AttemptResult> _attempts = const [];
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
      final attempts =
          uid.isEmpty ? <AttemptResult>[] : await fetchAttemptHistory(uid);
      if (!mounted) return;
      setState(() {
        _attempts = attempts;
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

  String _date(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam History')),
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
              : _attempts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No attempts yet.'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => context.go('/'),
                            child: const Text('Start a Mock Test'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _attempts.length,
                        itemBuilder: (c, i) {
                          final a = _attempts[i];
                          final pct = a.totalMarks > 0
                              ? (a.score / a.totalMarks * 100).round()
                              : 0;
                          return Card(
                            child: ListTile(
                              title: Text(a.examTitle),
                              subtitle: Text(
                                  '${_date(a.submittedAt)} · ${a.correctCount}/${a.totalMarks} correct'),
                              trailing: Text('$pct%',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              onTap: () => context.go('/result/${a.id}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
