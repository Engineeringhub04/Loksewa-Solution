import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Exam set detail — mirrors app/exam/[setId]/index.tsx.
/// Shows meta info, rules and start/ranking/review entry points.
class ExamDetailScreen extends StatefulWidget {
  final String setId;
  const ExamDetailScreen({super.key, required this.setId});

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  ExamSet? _set;
  List<ExamRule> _rules = const [];
  List<ExamAttempt> _attempts = const [];
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
      final attempts = uid.isEmpty ? <ExamAttempt>[] : await fetchAttemptsForSet(uid, widget.setId);
      final rules = await ExamRest.listDocs('app_exam_rules')
          .then((docs) => docs.map(ExamRule.fromMap).toList());
      if (!mounted) return;
      setState(() {
        _set = set;
        _rules = rules;
        _attempts = attempts;
        _unlocked = areResultsUnlocked(set, DateTime.now());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load exam details.';
        _loading = false;
      });
    }
  }

  void _startTest() {
    if (_set?.contentType == 'pdf') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is a PDF study set — open it to read.')),
      );
      return;
    }
    context.go('/exam/${widget.setId}/quiz');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Exam Details'),
          Expanded(
            child: _loading
          ? const PreloadingWidget(
            tinted: false,
            label: 'Loading Exam...',
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
              : _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final set = _set!;
    final best = _attempts.isEmpty
        ? null
        : _attempts.reduce((a, b) => a.score >= b.score ? a : b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(set.title,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (set.isPro)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('PRO',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('${set.questions.length} Questions'),
                    _chip('${set.durationMinutes} min'),
                    _chip('Pass ${set.passPercent}%'),
                    _chip(set.difficulty.toUpperCase()),
                  ],
                ),
                if (best != null) ...[
                  const SizedBox(height: 12),
                  Text('Best score: ${best.score}% '
                      '(${best.correct}/${best.totalQuestions} correct)',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_rules.isNotEmpty) ...[
          Text('Rules', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._rules.map((r) => Card(
                child: ListTile(
                  leading: const Icon(Icons.rule),
                  title: Text(r.title),
                  subtitle: r.description.isNotEmpty ? Text(r.description) : null,
                ),
              )),
          const SizedBox(height: 16),
        ],
        ElevatedButton.icon(
          onPressed: _startTest,
          icon: const Icon(Icons.play_arrow),
          label: Text(set.contentType == 'pdf' ? 'Open PDF' : 'Start Test'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/exam/${widget.setId}/ranking'),
          icon: const Icon(Icons.leaderboard_outlined),
          label: const Text('Ranking'),
        ),
        if (_unlocked && _attempts.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/exam/${widget.setId}/review'),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Review Answers'),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label) => Chip(label: Text(label));
}
