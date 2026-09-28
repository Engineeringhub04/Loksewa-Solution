import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Mock test attempt — mirrors app/mock-test/[id]/attempt.tsx.
/// Timed MCQ with next/previous, per-question palette, flags, submit →
/// saves attempt and opens the result screen.
class MockAttemptScreen extends StatefulWidget {
  final String id;
  const MockAttemptScreen({super.key, required this.id});

  @override
  State<MockAttemptScreen> createState() => _MockAttemptScreenState();
}

class _MockAttemptScreenState extends State<MockAttemptScreen> {
  ExamDefinition? _exam;
  List<MockQuestion> _questions = const [];
  bool _loading = true;
  String? _error;

  List<int?> _selected = [];
  List<bool> _flagged = [];
  int _index = 0;
  int _remaining = 0;
  Timer? _timer;
  DateTime? _startedAt;
  bool _submitting = false;
  bool _showPalette = false;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final exam = await fetchMockTest(widget.id);
      if (exam == null) throw Exception('Test not found');
      final questions = await fetchQuestionsByIds(exam.questionIds);
      if (!mounted) return;
      setState(() {
        _exam = exam;
        _questions = questions;
        _selected = List<int?>.filled(questions.length, null);
        _flagged = List<bool>.filled(questions.length, false);
        _remaining = exam.durationMinutes * 60;
        _startedAt = DateTime.now();
        _loading = false;
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          if (_remaining <= 1) {
            t.cancel();
            _submit(auto: true);
          } else {
            setState(() => _remaining -= 1);
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the test.';
        _loading = false;
      });
    }
  }

  void _goTo(int i) {
    if (i < 0 || i >= _questions.length) return;
    setState(() {
      _index = i;
      _showPalette = false;
    });
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting || _exam == null) return;
    if (!auto) {
      final unanswered = _selected.where((s) => s == null).length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Submit Test?'),
          content: Text(unanswered > 0
              ? '$unanswered question(s) unanswered. Submit anyway?'
              : 'Submit your answers?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Submit')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _submitting = true);
    _timer?.cancel();
    try {
      final answers = List.generate(
        _questions.length,
        (i) => AttemptAnswer(
          questionId: _questions[i].id,
          selectedIndex: _selected[i],
          flagged: _flagged[i],
        ),
      );
      final uid = AuthService.currentUser!.uid;
      final timeTaken =
          DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds;
      final attemptId = await submitAttempt(
        uid: uid,
        examId: _exam!.id,
        examTitle: _exam!.title,
        questions: _questions,
        answers: answers,
        timeTakenSeconds: timeTaken,
      );
      if (!mounted) return;
      context.go('/result/$attemptId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit. Try again.')),
      );
    }
  }

  String _clock() {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: _exam?.title ?? 'Mock Test', actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.timer, size: 16),
                  label: Text(_clock(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          if (!_loading && _error == null)
            IconButton(
              icon: const Icon(Icons.grid_view),
              onPressed: () =>
                  setState(() => _showPalette = !_showPalette),
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
              : _showPalette
                  ? _palette()
                  : _questionView(),
          ),
        ],
      ),
      bottomNavigationBar:
          (_loading || _error != null) ? null : _navBar(),
    );
  }

  Widget _questionView() {
    final q = _questions[_index];
    final selected = _selected[_index];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: (_index + 1) / _questions.length),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Q ${_index + 1}/${_questions.length}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: Icon(
                _flagged[_index] ? Icons.flag : Icons.flag_outlined,
                color: _flagged[_index] ? Colors.orange : null,
              ),
              onPressed: () => setState(
                  () => _flagged[_index] = !_flagged[_index]),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(q.text, style: Theme.of(context).textTheme.titleSmall),
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
              onTap: _submitting
                  ? null
                  : () => setState(() => _selected[_index] = i),
            ),
          );
        }),
      ],
    );
  }

  Widget _palette() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _questions.length,
      itemBuilder: (c, i) {
        final answered = _selected[i] != null;
        Color bg = Colors.grey.shade200;
        if (_index == i) {
          bg = Colors.blue;
        } else if (answered) {
          bg = Colors.green.shade100;
        } else if (_flagged[i]) {
          bg = Colors.orange.shade100;
        }
        return InkWell(
          onTap: () => _goTo(i),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text('${i + 1}',
                style: TextStyle(
                    color: _index == i ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _navBar() {
    final isLast = _index == _questions.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _index > 0 && !_submitting ? () => _goTo(_index - 1) : null,
                child: const Text('Previous'),
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
                      onPressed: () => _goTo(_index + 1),
                      child: const Text('Next'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
