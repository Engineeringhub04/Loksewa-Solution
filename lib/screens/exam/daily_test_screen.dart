import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Daily test landing — mirrors app/daily-test/index.tsx.
/// Today + missed + upcoming strip, then the released models list.
class DailyTestScreen extends StatefulWidget {
  const DailyTestScreen({super.key});

  @override
  State<DailyTestScreen> createState() => _DailyTestScreenState();
}

class _DailyTestScreenState extends State<DailyTestScreen> {
  List<DailyTestModel> _models = const [];
  Map<String, DailyTestResult> _results = const {};
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
      final profile = uid.isEmpty ? null : await fetchUserProfile(uid);
      final subcourseId = profile?.subcourseId ?? '';
      if (subcourseId.isEmpty) throw Exception('Course not set up');
      final models = await fetchDailyTestModels(subcourseId);
      final results = uid.isEmpty
          ? <DailyTestResult>[]
          : await fetchDailyTestResults(uid);
      if (!mounted) return;
      setState(() {
        _models = models;
        _results = {for (final r in results) r.modelId: r};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load daily tests.';
        _loading = false;
      });
    }
  }

  void _start(DailyTestModel model) {
    final isPro = model.subscriptionType == 'on' || model.isPro;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(model.displayName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${model.questions.length} questions · '
                  '${model.perQuestionTimeSeconds}s per question'),
              Text('Pass: ${model.passPercent}%'),
              if (model.rules.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Rules:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...model.rules.map((r) => Text('• $r')),
              ],
              if (isPro) ...[
                const SizedBox(height: 8),
                const Text('Premium test.',
                    style: TextStyle(color: Colors.orange)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(c);
              context.go('/daily-test/${model.id}/quiz');
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Daily Test'),
          Expanded(
            child: _loading
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
              : _models.isEmpty
                  ? const Center(child: Text('No daily tests available yet.'))
                  : _list(),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final today = todayDateKey();
    final released =
        _models.where((m) => m.testDate.compareTo(today) <= 0).toList()
          ..sort((a, b) => b.testDate.compareTo(a.testDate));
    final upcoming =
        _models.where((m) => m.testDate.compareTo(today) > 0).toList()
          ..sort((a, b) => a.testDate.compareTo(b.testDate));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Daily Tests',
                style: Theme.of(context).textTheme.titleMedium),
            TextButton(
              onPressed: () => context.go('/daily-test/history'),
              child: const Text('History'),
            ),
          ],
        ),
        ...released.map((m) {
          final result = _results[m.id];
          final isToday = m.testDate == today;
          return Card(
            child: ListTile(
              title: Text(m.displayName),
              subtitle: Text(
                  '${m.testDate} · ${m.questions.length} questions'),
              trailing: result != null
                  ? Chip(label: Text('${result.score}%'))
                  : isToday
                      ? ElevatedButton(
                          onPressed: () => _start(m),
                          child: const Text('Start'),
                        )
                      : const Chip(label: Text('Missed')),
              onTap: result != null
                  ? () => context.go('/daily-test/${m.id}/summary')
                  : isToday
                      ? () => _start(m)
                      : null,
            ),
          );
        }),
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Upcoming', style: Theme.of(context).textTheme.titleMedium),
          ...upcoming.map((m) => Card(
                child: ListTile(
                  title: Text(m.displayName),
                  subtitle: Text('Releases on ${m.testDate}'),
                  trailing: const Icon(Icons.lock_outline),
                ),
              )),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => context.go('/daily-test/models'),
          child: const Text('All Models'),
        ),
      ],
    );
  }
}
