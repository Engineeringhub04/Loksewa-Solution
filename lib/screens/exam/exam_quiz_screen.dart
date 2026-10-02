import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/subpage_header.dart';

/// Exam quiz — mirrors app/exam/[setId]/quiz.tsx.
///
/// Left question-number rail (always visible), timer pill + Q x/y, report
/// button per question, tap-selected-option-again = deselect, Previous/Next/
/// Submit, leave-confirm + submit-confirm via the shared [AppModalShell]
/// (app-wide modal rule), auto-submit on timeout, and `pushReplacement` to
/// the summary (the quiz is never reachable via Back).
class ExamQuizScreen extends StatefulWidget {
  final String setId;
  const ExamQuizScreen({super.key, required this.setId});

  @override
  State<ExamQuizScreen> createState() => _ExamQuizScreenState();
}

class _ExamQuizScreenState extends State<ExamQuizScreen> {
  ExamSet? _set;
  bool _loading = true;
  String? _error;

  int _index = 0;
  List<int> _answers = const []; // -1 = unanswered
  int _remaining = 0;
  Timer? _timer;
  DateTime? _startedAt;
  bool _submitted = false;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      if (!mounted) return;
      setState(() {
        _set = set;
        _answers = List<int>.filled(set.questions.length, -1);
        _remaining = set.durationMinutes * 60;
        _startedAt = DateTime.now();
        _loading = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _submitted) return;
        setState(() {
          _remaining--;
          if (_remaining <= 0) {
            _autoSubmit();
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load the exam.', 'परीक्षा लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  String get _clock {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _answeredCount => _answers.where((a) => a >= 0).length;

  // ---------- leave / submit confirms (AppModalShell) ----------

  Future<bool> _confirmLeave() async {
    if (_submitted) return true;
    final leave = await AppModalShell.show<bool>(
      context: context,
      builder: (dialogContext) => AppModalShell(
        onClose: () => Navigator.of(dialogContext).pop(false),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.exit_to_app,
              color: Color(0xFFB91C1C), size: 28),
        ),
        tagLabel: AppLanguage.tr('Leave Exam?', 'परीक्षा छोड्ने?'),
        title: Text(
          AppLanguage.tr('Your progress will be lost.',
              'तपाईंको प्रगति गुम्नेछ।'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        body: Text(
          AppLanguage.tr(
              'If you leave now, your answers will not be saved.',
              'अहिले छोड्नुभयो भने तपाईंका उत्तरहरू सेभ हुनेछैनन्।'),
          textAlign: TextAlign.center,
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppLanguage.tr('Stay', 'बस्नुहोस्')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppLanguage.tr('Leave', 'छोड्नुहोस्')),
              ),
            ),
          ],
        ),
      ),
    );
    return leave == true;
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _answers.length - _answeredCount;
    final submit = await AppModalShell.show<bool>(
      context: context,
      builder: (dialogContext) => AppModalShell(
        onClose: () => Navigator.of(dialogContext).pop(false),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.send_outlined,
              color: Color(0xFFB45309), size: 28),
        ),
        tagLabel: AppLanguage.tr('Submit Exam?', 'परीक्षा बुझाउने?'),
        title: Text(
          AppLanguage.tr('Submit your answers?', 'उत्तरहरू बुझाउने?'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              unanswered > 0
                  ? AppLanguage.tr(
                      'You have $unanswered unanswered question(s). Unanswered questions carry no penalty.',
                      '$unanswered प्रश्नको उत्तर दिनुभएको छैन। उत्तर नदिएका प्रश्नमा जरिवाना लाग्दैन।')
                  : AppLanguage.tr(
                      'You answered all questions. Ready to submit?',
                      'सबै प्रश्नको उत्तर दिनुभयो। बुझाउन तयार?'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppLanguage.tr('Keep Solving', 'जारी राख्नुहोस्')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppLanguage.tr('Submit', 'बुझाउनुहोस्')),
              ),
            ),
          ],
        ),
      ),
    );
    if (submit == true) _submit(auto: false);
  }

  Future<void> _autoSubmit() async {
    if (_submitted) return;
    showToast(
        context,
        AppLanguage.tr('Time is up! Submitting your exam…',
            'समय सकियो! परीक्षा बुझाइँदैछ…'),
        ToastVariant.info);
    await _submit(auto: true);
  }

  Future<void> _submit({required bool auto}) async {
    if (_submitted || _submitting) return;
    setState(() => _submitting = true);
    final set = _set!;
    final timeTaken =
        DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds;
    final score = scoreExamAttempt(
      set.questions,
      _answers,
      set.passPercent,
    );
    final user = AuthService.currentUser;
    final profile = ProfileStore.instance.profile;
    try {
      if (user != null) {
        final attempts = await fetchAttemptsForSet(user.uid, set.id);
        await saveExamAttempt(
          uid: user.uid,
          set: set,
          score: score,
          answers: List<int>.from(_answers),
          attemptNumber: attempts.length + 1,
          timeTakenSeconds: timeTaken,
          name: profile?.name ?? user.displayName ?? 'Student',
          photoURL: profile?.photoURL,
          isPro: profile?.isPremium ?? false,
        );
      }
    } catch (_) {
      // Best-effort save; the summary is computed from submitted answers.
    }
    if (!mounted) return;
    setState(() {
      _submitted = true;
      _submitting = false;
    });
    _timer?.cancel();
    // Replace the quiz — Back lands on the exam detail/tab, never the quiz.
    final answersParam = _answers.map((a) => '$a').join(',');
    context.pushReplacement(
      '/exam/${set.id}/summary?answers=${Uri.encodeComponent(answersParam)}'
      '&timeTaken=$timeTaken${auto ? '&auto=1' : ''}',
    );
  }

  void _reportQuestion() {
    final q = _set!.questions[_index];
    ReportDialog.show(
      context: context,
      question: q.question,
      options: q.options,
      questionId: '${widget.setId}#$_index',
      mode: 'exam',
    );
  }

  bool _canPop = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_submitted) {
          // Already submitted — leave freely.
          _canPop = true;
          if (mounted) Navigator.of(context).pop();
          return;
        }
        if (await _confirmLeave()) {
          _canPop = true;
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            SubpageHeader(title: AppLanguage.tr('Exam', 'परीक्षा')),
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
                              ElevatedButton(
                                  onPressed: _load,
                                  child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _quizBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quizBody() {
    final set = _set!;
    final q = set.questions[_index];
    final total = set.questions.length;
    return Column(
      children: [
        // Timer pill + Q x/y + report — mirrors quiz.tsx header row.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _remaining < 300
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _remaining < 300
                        ? const Color(0xFFFECACA)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 16,
                        color: _remaining < 300
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF475569)),
                    const SizedBox(width: 4),
                    Text(_clock,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _remaining < 300
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF0F172A))),
                  ],
                ),
              ),
              const Spacer(),
              Text('Q ${_index + 1}/$total',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: AppLanguage.tr('Report', 'रिपोर्ट'),
                onPressed: _reportQuestion,
                icon: const Icon(Icons.flag_outlined, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left question-number rail — always visible (React parity).
              Container(
                width: 60,
                margin: const EdgeInsets.fromLTRB(8, 4, 0, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: total,
                  itemBuilder: (c, i) {
                    final answered = _answers[i] >= 0;
                    final current = i == _index;
                    return GestureDetector(
                      onTap: () => setState(() => _index = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        height: 40,
                        decoration: BoxDecoration(
                          color: current
                              ? const Color(0xFFF59E0B)
                              : answered
                                  ? const Color(0xFFDCFCE7)
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: current
                                ? const Color(0xFFF59E0B)
                                : answered
                                    ? const Color(0xFF86EFAC)
                                    : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Center(
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: current
                                      ? Colors.white
                                      : answered
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFF475569))),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Question + options.
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text('Q${_index + 1}. ${q.question}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...List.generate(q.options.length, (oi) {
                      final selected = _answers[_index] == oi;
                      const letters = ['A', 'B', 'C', 'D', 'E', 'F'];
                      final letter =
                          oi < letters.length ? letters[oi] : '${oi + 1}';
                      return GestureDetector(
                        onTap: () => setState(() {
                          // Tap again to deselect (React parity).
                          _answers[_index] =
                              _answers[_index] == oi ? -1 : oi;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFFFFFBEB)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFE2E8F0),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFFF1F5F9),
                                ),
                                child: Center(
                                  child: Text(letter,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: selected
                                              ? Colors.white
                                              : const Color(0xFF475569))),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(q.options[oi])),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Prev / Next / Submit.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _index > 0
                      ? () => setState(() => _index--)
                      : null,
                  child: Text(AppLanguage.tr('Previous', 'अघिल्लो')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _index < _set!.questions.length - 1
                    ? ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white),
                        onPressed: () => setState(() => _index++),
                        child: Text(AppLanguage.tr('Next', 'अर्को')),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white),
                        onPressed: _submitting ? null : _confirmSubmit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(AppLanguage.tr('Submit', 'बुझाउनुहोस्')),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
