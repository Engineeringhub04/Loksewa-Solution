import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';

/// Exam quiz — mirrors app/exam/[setId]/quiz.tsx.
/// Full-screen timed MCQ: option select, next/previous, question palette,
/// countdown, submit → score → save attempt → summary.
class ExamQuizScreen extends StatefulWidget {
  final String setId;
  const ExamQuizScreen({super.key, required this.setId});

  @override
  State<ExamQuizScreen> createState() => _ExamQuizScreenState();
}

class _ExamQuizScreenState extends State<ExamQuizScreen> {
  ExamSet? _set;
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  bool _locked = false;

  List<int?> _answers = [];
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
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      final uid = AuthService.currentUser?.uid ?? '';
      final profile = uid.isEmpty ? null : await fetchUserProfile(uid);
      if (!mounted) return;
      final locked = set.isPro && !(profile?.isPro ?? false);
      setState(() {
        _set = set;
        _profile = profile;
        _locked = locked;
        _loading = false;
        if (!locked) {
          _answers = List<int?>.filled(set.questions.length, null);
          _remaining = set.durationMinutes * 60;
          _startedAt = DateTime.now();
          _timer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) return;
            if (_remaining <= 1) {
              t.cancel();
              _autoSubmit();
            } else {
              setState(() => _remaining -= 1);
            }
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the exam.';
        _loading = false;
      });
    }
  }

  void _select(int optionIndex) {
    if (_submitting) return;
    setState(() => _answers[_index] = optionIndex);
  }

  void _goTo(int i) {
    if (i < 0 || i >= _set!.questions.length) return;
    setState(() {
      _index = i;
      _showPalette = false;
    });
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _answers.where((a) => a == null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit Test?'),
        content: Text(unanswered > 0
            ? 'You have $unanswered unanswered question(s). Submit anyway?'
            : 'Are you sure you want to submit?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok == true) _submit();
  }

  void _autoSubmit() {
    if (_submitting) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Time is up — submitting automatically.')),
    );
    _submit();
  }

  Future<void> _submit() async {
    if (_submitting || _set == null) return;
    setState(() => _submitting = true);
    _timer?.cancel();
    try {
      final set = _set!;
      final score = scoreExamAttempt(set.questions, _answers, set.passPercent);
      final uid = AuthService.currentUser!.uid;
      final prev = await fetchAttemptsForSet(uid, set.id);
      final timeTaken = DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds;
      await saveExamAttempt(
        uid: uid,
        set: set,
        score: score,
        answers: _answers.map((a) => a ?? -1).toList(),
        attemptNumber: prev.length + 1,
        timeTakenSeconds: timeTaken,
        name: _profile?.name ??
            AuthService.currentUser?.displayName ??
            'Anonymous',
        photoURL: _profile?.photoURL ?? AuthService.currentUser?.photoURL,
        isPro: _profile?.isPro ?? false,
      );
      if (!mounted) return;
      context.go('/exam/${set.id}/summary');
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
    return WillPopScope(
      onWillPop: () async {
        if (_submitting || _loading) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Leave Test?'),
            content: const Text('Your progress will be lost.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Stay')),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Leave')),
            ],
          ),
        );
        return ok == true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_set?.title ?? 'Test'),
          actions: [
            if (_set != null && !_locked)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Chip(
                    avatar: const Icon(Icons.timer, size: 16),
                    label: Text(_clock(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            if (_set != null && !_locked)
              IconButton(
                icon: const Icon(Icons.grid_view),
                onPressed: () =>
                    setState(() => _showPalette = !_showPalette),
              ),
          ],
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
                : _locked
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'This is a premium test. Upgrade to Premium to unlock it.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _showPalette
                        ? _palette()
                        : _questionView(),
        bottomNavigationBar:
            (_set != null && !_locked && !_loading && _error == null)
                ? _navBar()
                : null,
      ),
    );
  }

  Widget _questionView() {
    final set = _set!;
    final q = set.questions[_index];
    final selected = _answers[_index];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: (_index + 1) / set.questions.length),
        const SizedBox(height: 12),
        Text('Q ${_index + 1}/${set.questions.length}',
            style: Theme.of(context).textTheme.titleMedium),
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
              onTap: () => _select(i),
            ),
          );
        }),
      ],
    );
  }

  Widget _palette() {
    final set = _set!;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: set.questions.length,
      itemBuilder: (c, i) {
        final answered = _answers[i] != null;
        return InkWell(
          onTap: () => _goTo(i),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _index == i
                  ? Colors.blue
                  : answered
                      ? Colors.green.shade100
                      : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
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
    final set = _set!;
    final isLast = _index == set.questions.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _index > 0 && !_submitting ? () => _goTo(_index - 1) : null,
                child: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isLast
                  ? ElevatedButton(
                      onPressed: _submitting ? null : _confirmSubmit,
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
