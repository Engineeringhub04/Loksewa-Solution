import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// All daily test models grouped by date — mirrors app/daily-test/models.tsx.
class DailyTestModelsScreen extends StatefulWidget {
  const DailyTestModelsScreen({super.key});

  @override
  State<DailyTestModelsScreen> createState() => _DailyTestModelsScreenState();
}

class _DailyTestModelsScreenState extends State<DailyTestModelsScreen> {
  List<DailyTestModel> _models = const [];
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
      if (!mounted) return;
      setState(() {
        _models = models..sort((a, b) => b.testDate.compareTo(a.testDate));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load models.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Daily Test Models'),
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
                  ? const Center(child: Text('No models yet.'))
                  : _grouped(),
          ),
        ],
      ),
    );
  }

  Widget _grouped() {
    final today = todayDateKey();
    final groups = <String, List<DailyTestModel>>{};
    for (final m in _models) {
      groups.putIfAbsent(m.testDate, () => []).add(m);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dates.length,
      itemBuilder: (c, i) {
        final date = dates[i];
        final label = date == today ? 'Today' : date;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(label,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            ...groups[date]!.map((m) => Card(
                  child: ListTile(
                    title: Text(m.displayName),
                    subtitle: Text(
                        '${m.questions.length} questions · ${m.category}'),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => context.go('/daily-test/${m.id}/quiz'),
                  ),
                )),
          ],
        );
      },
    );
  }
}
