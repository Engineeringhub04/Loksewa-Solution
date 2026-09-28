import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Exam ranking — mirrors app/exam/[setId]/ranking.tsx.
/// Best score per user, sorted by score desc then fastest time.
class ExamRankingScreen extends StatefulWidget {
  final String setId;
  const ExamRankingScreen({super.key, required this.setId});

  @override
  State<ExamRankingScreen> createState() => _ExamRankingScreenState();
}

class _ExamRankingScreenState extends State<ExamRankingScreen> {
  List<RankingRow> _rows = const [];
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
      final rows = await fetchExamRanking(widget.setId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the ranking.';
        _loading = false;
      });
    }
  }

  String _time(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Ranking'),
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
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _rows.isEmpty
                  ? const Center(child: Text('No rankings yet. Be the first!'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (c, i) {
                        final r = _rows[i];
                        final medal = i == 0
                            ? '🥇'
                            : i == 1
                                ? '🥈'
                                : i == 2
                                    ? '🥉'
                                    : '${i + 1}';
                        return Card(
                          child: ListTile(
                            leading: Text(medal,
                                style: const TextStyle(fontSize: 20)),
                            title: Row(
                              children: [
                                Expanded(child: Text(r.name)),
                                if (r.isPro)
                                  const Icon(Icons.verified,
                                      size: 16, color: Colors.blue),
                              ],
                            ),
                            subtitle:
                                Text('Time: ${_time(r.timeTakenSeconds)}'),
                            trailing: Text('${r.score}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
