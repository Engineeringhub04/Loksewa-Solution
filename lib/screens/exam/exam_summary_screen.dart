import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../tabs_screen.dart';

/// Exam summary — mirrors app/exam/[setId]/summary.tsx.
///
/// The score shown is EXACTLY what was submitted: answers arrive via route
/// params and the breakdown is recomputed from them (never re-read from
/// Firestore). Verdict bands, 6-stat grid, negative-marking caption, and a
/// review button that stays visible but locked (with a toast) until the
/// exam window closes.
class ExamSummaryScreen extends StatefulWidget {
  final String setId;
  final String? answers; // comma-separated, -1 = skipped
  final int? timeTaken;
  final bool auto; // submitted automatically on timeout

  const ExamSummaryScreen({
    super.key,
    required this.setId,
    this.answers,
    this.timeTaken,
    this.auto = false,
  });

  @override
  State<ExamSummaryScreen> createState() => _ExamSummaryScreenState();
}

class _ExamSummaryScreenState extends State<ExamSummaryScreen> {
  ExamSet? _set;
  ScoreBreakdown? _score;
  List<int> _answers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      final answers = (widget.answers ?? '')
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? -1)
          .toList();
      // Pad/truncate to the question count so the score is exact.
      final padded = List<int>.filled(set.questions.length, -1);
      for (var i = 0; i < padded.length && i < answers.length; i++) {
        padded[i] = answers[i];
      }
      final score = scoreExamAttempt(
        set.questions,
        padded,
        set.passPercent,
      );
      if (!mounted) return;
      setState(() {
        _set = set;
        _answers = padded;
        _score = score;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load the summary.', 'नतिजा लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  (String, String) _verdict(ScoreBreakdown s) {
    if (s.percent >= 85) {
      return (
        AppLanguage.tr('Outstanding!', 'उत्कृष्ट!'),
        AppLanguage.tr('Exceptional performance. Keep it up!',
            'असाधारण प्रदर्शन। यसरी नै अगाडि बढ्नुहोस्!')
      );
    }
    if (s.percent >= 60) {
      return (
        AppLanguage.tr('Well Done!', 'राम्रो!'),
        AppLanguage.tr('Strong performance. A little polish to go!',
            'बलियो प्रदर्शन। थोरै मेहनत बाँकी!')
      );
    }
    if (s.passed) {
      return (
        AppLanguage.tr('Passed', 'उत्तीर्ण'),
        AppLanguage.tr('You cleared the pass mark. Keep practising!',
            'उत्तीर्ण अंक पार गर्नुभयो। अभ्यास जारी राख्नुहोस्!')
      );
    }
    return (
      AppLanguage.tr('Keep Trying', 'प्रयास जारी राख्नुहोस्'),
      AppLanguage.tr('Review your answers and try again — you\'ve got this!',
          'उत्तरहरू समीक्षा गर्नुहोस् र पुनः प्रयास गर्नुहोस्!')
    );
  }

  String _timeLabel(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  void _goReview() {
    final set = _set!;
    if (!areResultsUnlocked(set, DateTime.now())) {
      final unlock = resultsUnlockAt(set, DateTime.now());
      final k = unlock.toUtc().add(const Duration(hours: 5, minutes: 45));
      showToast(
        context,
        AppLanguage.tr(
            'Answers unlock after the exam window closes (${k.hour}:${k.minute.toString().padLeft(2, '0')}).',
            'परीक्षा समय सकिएपछि उत्तरहरू खुल्नेछन्।'),
        ToastVariant.warning,
      );
      return;
    }
    final answersParam = _answers.map((a) => '$a').join(',');
    context.push(
      '/exam/${set.id}/review?answers=${Uri.encodeComponent(answersParam)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Result'),
          Expanded(
            child: _loading
                ? const PreloadingWidget(
                    tinted: false,
                    label: 'Loading Result...',
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            ElevatedButton(
                                onPressed: _load,
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _summary(),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final set = _set!;
    final s = _score!;
    final (verdict, message) = _verdict(s);
    final passColor = s.passed ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final unlocked = areResultsUnlocked(set, DateTime.now());
    final timeTaken = widget.timeTaken ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.auto)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_off_outlined,
                    color: Color(0xFFB45309), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLanguage.tr(
                        'Time ran out — your exam was submitted automatically.',
                        'समय सकियो — तपाईंको परीक्षा स्वतः बुझाइयो।'),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(set.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: s.percent / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey.shade200,
                        color: passColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${s.percent}%',
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        Text('${s.marks.toStringAsFixed(1)} '
                            '${AppLanguage.tr('marks', 'अंक')}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(verdict,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: passColor)),
                const SizedBox(height: 4),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(AppLanguage.tr('Correct', 'सही'), '${s.correct}',
                        const Color(0xFF16A34A)),
                    _stat(AppLanguage.tr('Incorrect', 'गलत'), '${s.incorrect}',
                        const Color(0xFFDC2626)),
                    _stat(AppLanguage.tr('Skipped', 'छोडियो'), '${s.skipped}',
                        Colors.grey),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(AppLanguage.tr('Time', 'समय'),
                        _timeLabel(timeTaken), const Color(0xFF0F172A)),
                    _stat(
                        AppLanguage.tr('Negative', 'नकारात्मक'),
                        '-${s.negativeMarks.toStringAsFixed(2)}',
                        const Color(0xFFB45309)),
                    _stat(AppLanguage.tr('Pass Mark', 'उत्तीर्णांक'),
                        '${set.passPercent}%', const Color(0xFF1D4ED8)),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            AppLanguage.tr(
                'Wrong answers carry −0.25 marks each.',
                'गलत उत्तरमा −०.२५ अंक कट्छ।'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        // Review — visible but locked until the window closes (React parity).
        OutlinedButton.icon(
          onPressed: _goReview,
          icon: Icon(unlocked
              ? Icons.rate_review_outlined
              : Icons.lock_outline),
          label: Text(AppLanguage.tr('Review Answers', 'उत्तर समीक्षा')),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                unlocked ? const Color(0xFF0F172A) : Colors.grey.shade500,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push('/exam/${set.id}'),
          icon: const Icon(Icons.info_outline),
          label: Text(
              AppLanguage.tr('Exam Details & Attempts', 'परीक्षा विवरण')),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () {
            // Back to the Exam tab (index 1) — React: router.push('/(tabs)/exam').
            TabsScreen.tabIndex.value = 1;
            context.go('/');
          },
          icon: const Icon(Icons.quiz_outlined),
          label: Text(
              AppLanguage.tr('Practice Other Exams', 'अन्य परीक्षा')),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) => SizedBox(
        width: 100,
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}
