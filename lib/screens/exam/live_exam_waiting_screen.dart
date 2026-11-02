import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Live exam waiting room — mirrors app/live-exam/[id]/waiting.tsx.
/// Confirm join → countdown → auto-start; late join is blocked.
class LiveExamWaitingScreen extends StatefulWidget {
  final String id;
  const LiveExamWaitingScreen({super.key, required this.id});

  @override
  State<LiveExamWaitingScreen> createState() => _LiveExamWaitingScreenState();
}

class _LiveExamWaitingScreenState extends State<LiveExamWaitingScreen> {
  ExamDefinition? _exam;
  bool _loading = true;
  String? _error;
  bool _joined = false;
  int? _countdown;
  Timer? _timer;

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
      final exam = await fetchLiveExam(widget.id);
      if (!mounted) return;
      setState(() {
        _exam = exam;
        _loading = false;
        if (exam == null) _error = 'Live exam not found.';
      });
      if (exam != null) _askToJoin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the live exam.';
        _loading = false;
      });
    }
  }

  void _askToJoin() {
    AppModalShell.show<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AppModalShell(
        maxWidth: 360,
        tagLabel: AppLanguage.tr('Live Exam', 'लाइभ परीक्षा'),
        accent: const Color(0xFF2563EB),
        accentMid: const Color(0xFF3B82F6),
        accentLight: const Color(0xFFBFDBFE),
        tagColor: const Color(0xFF1D4ED8),
        onClose: () {
          Navigator.of(c).pop();
          context.pop();
        },
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF2563EB),
          ),
          child: const Icon(Icons.live_tv_outlined,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Join Live Exam?', 'लाइभ परीक्षामा सामेल हुने?'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          _exam!.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF475569),
            height: 1.5,
            decoration: TextDecoration.none,
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(c).pop();
                  context.pop();
                },
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(c).pop();
                  setState(() => _joined = true);
                  _startCountdown();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(AppLanguage.tr('Join', 'सामेल हुनुहोस्')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startCountdown() {
    final start = _exam?.scheduledStart;
    if (start == null) {
      // No scheduled start — go straight to the attempt.
      context.go('/mock-test/${widget.id}/attempt');
      return;
    }
    void tick() {
      if (!mounted) return;
      final remaining =
          ((start.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch) /
                  1000)
              .round();
      if (remaining <= 0) {
        _timer?.cancel();
        context.go('/mock-test/${widget.id}/attempt');
        return;
      }
      setState(() => _countdown = remaining);
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String _clock(int? seconds) {
    if (seconds == null) return '--:--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasStarted = _exam?.scheduledStart != null &&
        _exam!.scheduledStart!.isBefore(DateTime.now());
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Waiting Room'),
          Expanded(
            child: _loading
          ? const PreloadingWidget(
            tinted: false,
            label: 'Loading...',
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
              : hasStarted && !_joined
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'This live exam has already started. Late join is not allowed.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_exam!.title,
                                style: Theme.of(context).textTheme.headlineSmall,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            if (_joined) ...[
                              const Text('Starts in'),
                              const SizedBox(height: 8),
                              Text(_clock(_countdown),
                                  style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold)),
                            ] else
                              const PreloadingWidget(
                                tinted: false,
                                label: 'Joining exam...',
                              ),
                          ],
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
