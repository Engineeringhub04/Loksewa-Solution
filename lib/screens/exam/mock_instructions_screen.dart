import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Mock test instructions — mirrors app/mock-test/[id]/instructions.tsx.
class MockInstructionsScreen extends StatefulWidget {
  final String id;
  const MockInstructionsScreen({super.key, required this.id});

  @override
  State<MockInstructionsScreen> createState() => _MockInstructionsScreenState();
}

class _MockInstructionsScreenState extends State<MockInstructionsScreen> {
  ExamDefinition? _exam;
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
      final exam = await fetchMockTest(widget.id);
      if (!mounted) return;
      setState(() {
        _exam = exam;
        _loading = false;
        if (exam == null) _error = 'Test not found.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the test.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Instructions'),
          Expanded(
            child: _loading
          ? const PreloadingWidget(
            tinted: false,
            label: 'Loading Instructions...',
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(_exam!.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _info('Questions', '${_exam!.questionIds.length}'),
                            _info('Duration', '${_exam!.durationMinutes} minutes'),
                            if (_exam!.markingScheme.isNotEmpty)
                              _info('Marking', _exam!.markingScheme),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Instructions',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• Answer all questions within the time limit.'),
                            SizedBox(height: 6),
                            Text('• Wrong answers carry a negative mark of 0.25.'),
                            SizedBox(height: 6),
                            Text('• You can navigate between questions freely.'),
                            SizedBox(height: 6),
                            Text('• Do not leave the app once the test starts.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () =>
                          context.go('/mock-test/${widget.id}/attempt'),
                      child: const Text('Start Test'),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
