import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Quiz practice — mirrors app/quiz/[subjectId].tsx.
/// Untimed MCQ practice per subject with immediate inline feedback.
class SubjectQuizScreen extends StatefulWidget {
  final String subjectId;
  const SubjectQuizScreen({super.key, required this.subjectId});

  @override
  State<SubjectQuizScreen> createState() => _SubjectQuizScreenState();
}

class _SubjectQuizScreenState extends State<SubjectQuizScreen> {
  List<PracticeQuestion> _questions = const [];
  bool _loading = true;
  String? _error;

  int _index = 0;
  int? _selected;
  int _correctCount = 0;
  bool _finished = false;

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
      final questions = await fetchPracticeQuestions(widget.subjectId);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
        if (questions.isEmpty) _error = 'No questions available yet.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load questions.';
        _loading = false;
      });
    }
  }

  void _select(int i) {
    if (_selected != null) return;
    final current = _questions[_index];
    setState(() {
      _selected = i;
      if (i == current.correctIndex) _correctCount += 1;
    });
  }

  void _next() {
    if (_index + 1 >= _questions.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index += 1;
      _selected = null;
    });
  }

  void _confirmExit() {
    if (_selected != null || _finished) {
      context.pop();
      return;
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Exit Practice?'),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Stay')),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              context.pop();
            },
            child: const Text('Exit'),
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
          SubpageHeader(title: _loading
            ? 'Practice'
            : _finished
                ? 'Summary'
                : 'Q ${_index + 1}/${_questions.length}'),
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
              : _finished
                  ? _summary()
                  : _questionView(),
          ),
        ],
      ),
      bottomNavigationBar: (_loading || _error != null || _finished)
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: _selected == null ? null : _next,
                  child: const Text('Next'),
                ),
              ),
            ),
    );
  }

  Widget _questionView() {
    final current = _questions[_index];
    final showResult = _selected != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: (_index + 1) / _questions.length),
        const SizedBox(height: 12),
        Text(current.bilingualText,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        ...List.generate(current.options.length, (i) {
          final isSelected = _selected == i;
          final isCorrect = i == current.correctIndex;
          Color? border;
          if (showResult && isSelected) {
            border = isCorrect ? Colors.green : Colors.red;
          } else if (showResult && isCorrect) {
            border = Colors.green;
          }
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border ?? Colors.grey.shade300, width: 1.5),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isSelected ? border : Colors.grey.shade200,
                foregroundColor: isSelected ? Colors.white : Colors.black87,
                child: Text(String.fromCharCode(65 + i)),
              ),
              title: Text(current.options[i]),
              onTap: () => _select(i),
            ),
          );
        }),
        if (showResult && current.bilingualExplanation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(current.bilingualExplanation),
            ),
          ),
        ],
      ],
    );
  }

  Widget _summary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Practice Complete',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('$_correctCount/${_questions.length}',
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
