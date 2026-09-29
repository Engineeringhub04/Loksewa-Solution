import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _date(DateTime? dt) {
    if (dt == null) return '';
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Exam History'),
          Expanded(
            child: _loading
          ? const PreloadingWidget(
              tinted: false,
              label: 'Loading Exam History...',
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
              : _attempts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("You haven't taken any tests yet."),
                          const SizedBox(height: 12),
                          // The Flutter router has no exam-tab route (router is
                          // read-only), so this lands on the home tabs shell,
                          // matching React's "start a mock test" intent.
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
                          final scoreStr = a.score == a.score.roundToDouble()
                              ? a.score.toInt().toString()
                              : a.score.toStringAsFixed(2);
                          final pct = a.totalMarks > 0
                              ? (a.score / a.totalMarks * 100).round()
                              : 0;
                          return Card(
                            child: ListTile(
                              title: Text(a.examTitle),
                              subtitle: Text(
                                  '${_date(a.submittedAt)} · Score: $scoreStr/${a.totalMarks}'),
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
          ),
        ],
      ),
    );
  }
}
