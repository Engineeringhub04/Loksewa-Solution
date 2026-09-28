import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Daily test quiz — mirrors app/daily-test/[modelId]/quiz.tsx.
/// Forward-only (no Previous), per-question countdown with auto-advance,
/// auto-submit on the last question; re-attempts redirect to summary.
class DailyQuizScreen extends StatefulWidget {
  final String modelId;
  const DailyQuizScreen({super.key, required this.modelId});

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> {
  DailyTestModel? _model;
  bool _loading = true;
  String? _error;

  List<int?> _answers = [];
  int _index = 0;
  int _qRemaining = 0;
  Timer? _timer;
  DateTime? _startedAt;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _qTime(int i) {
    final q = _model!.questions[i];
    return q.timeSeconds > 0
        ? q.timeSeconds
        : _model!.perQuestionTimeSeconds > 0
            ? _model!.perQuestionTimeSeconds
            : 30;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      // Re-attempt guard — redirect to summary when a result already exists.
      if (uid.isNotEmpty) {
        final existing = await fetchDailyTestResultForModel(uid, widget.modelId);
        if (existing != null) {
          if (!mounted) return;
          context.go('/daily-test/${widget.modelId}/summary');
          return;
        }
      }
      final model = await fetchDailyTestModel(widget.modelId);
      if (model == null) throw Exception('Model not found');
      if (model.questions.isEmpty) throw Exception('No questions in this test');
      if (!mounted) return;
      setState(() {
        _model = model;
        _answers = List<int?>.filled(model.questions.length, null);
        _qRemaining = 0;
        _startedAt = DateTime.now();
        _loading = false;
      });
      _armTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the test.';
        _loading = false;
      });
    }
  }

  void _armTimer() {
    _timer?.cancel();
    setState(() => _qRemaining = _qTime(_index));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_qRemaining <= 1) {
        t.cancel();
        _next(auto: true);
      } else {
        setState(() => _qRemaining -= 1);
      }
    });
  }

  void _select(int optionIndex) {
    if (_submitting) return;
    setState(() => _answers[_index] = optionIndex);
  }

  /// Forward-only — timeouts auto-advance; the last question auto-submits.
  void _next({bool auto = false}) {
    if (_submitting || _model == null) return;
    if (_index + 1 >= _model!.questions.length) {
      _submit();
      return;
    }
    setState(() => _index += 1);
    _armTimer();
  }

  Future<void> _submit() async {
    if (_submitting || _model == null) return;
    setState(() => _submitting = true);
    _timer?.cancel();
    try {
      final model = _model!;
      final score = scoreDailyTest(model, model.questions, _answers);
      final uid = AuthService.currentUser!.uid;
      final timeTaken =
          DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds;
      await saveDailyTestResult(
        uid: uid,
        model: model,
        score: score,
        answers: _answers.map((a) => a ?? -1).toList(),
        timeTakenSeconds: timeTaken,
      );
      if (!mounted) return;
      context.go('/daily-test/${model.id}/summary');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: _model?.displayName ?? 'Daily Test', actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.timer, size: 16),
                  label: Text('${_qRemaining}s',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ]),
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
              : _questionView(),
          ),
        ],
      ),
      bottomNavigationBar:
          (_loading || _error != null) ? null : _navBar(),
    );
  }

  Widget _questionView() {
    final model = _model!;
    final q = model.questions[_index];
    final selected = _answers[_index];
    final total = _qTime(_index);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(
          value: _qRemaining / (total == 0 ? 1 : total),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Q ${_index + 1}/${model.questions.length}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Chip(label: Text(q.category)),
          ],
        ),
        const SizedBox(height: 8),
        Text(q.question, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        ...List.generate(q.options.length, (i) {
          final isSel = selected == i;
          return Card(
            color: isSel ? Colors.blue.shade50 : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isSel ? Colors.blue : Colors.grey.shade200,
                foregroundColor: isSel ? Colors.white : Colors.black87,
                child: Text(String.fromCharCode(65 + i)),
              ),
              title: Text(q.options[i]),
              onTap: _submitting ? null : () => _select(i),
            ),
          );
        }),
      ],
    );
  }

  Widget _navBar() {
    final model = _model!;
    final isLast = _index == model.questions.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _next(),
                child: const Text('Skip'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isLast
                  ? ElevatedButton(
                      onPressed: _submitting ? null : () => _submit(),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Submit'),
                    )
                  : ElevatedButton(
                      onPressed: _submitting ? null : () => _next(),
                      child: const Text('Next'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
