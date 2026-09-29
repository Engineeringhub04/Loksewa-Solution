import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/theme_service.dart';
import '../../widgets/app_toast.dart';

/// Daily test quiz — mirrors app/daily-test/[modelId]/quiz.tsx.
///
/// Forward-only (no Previous), per-question countdown with auto-advance,
/// auto-submit on the last question. Re-attempts are bounced to the saved
/// summary via a server read — local history never gates access.
class DailyQuizScreen extends StatefulWidget {
  final String modelId;

  const DailyQuizScreen({super.key, required this.modelId});

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> {
  DailyTestModel? _model;
  bool _loading = true;
  String? _blockTitle;
  String? _blockMessage;

  List<int?> _answers = [];
  int _index = 0;
  int _qRemaining = 0;
  int _timerQuestion = -1;
  Timer? _timer;
  Timer? _blinkTimer;
  bool _blinkOn = false;
  bool _dialogOpen = false;
  bool _submitting = false;
  bool _allowPop = false;
  DateTime? _startedAt;
  String? _uid;
  // Stashed from the boot profile read (used by the header subtitle and the
  // bookmark free-tier cap). The quiz itself has no premium gate — React's
  // quiz.tsx doesn't gate either; gating lives on the landing card.
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    // A10: the clock starts at mount — timeTakenSeconds includes load latency,
    // exactly like React's `Date.now()` in a ref at component mount.
    _startedAt = DateTime.now();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blinkTimer?.cancel();
    super.dispose();
  }

  /// The schedule rule, enforced where the questions live — the landing card
  /// already refuses unplayable models, but this screen is also reachable by
  /// deep link, notification, or Back-then-forward after midnight. Returns the
  /// block (title + message), or null when the model is playable.
  /// Mirrors the scheduleBlock memo in React quiz.tsx.
  ({String title, String message})? _scheduleBlock(DailyTestModel model) {
    final today = todayDateKey();
    if (isDailyTestDemo(model)) {
      return (
        title: 'Not a real test',
        message:
            'That card is only a preview — the real test will appear here once it is scheduled.',
      );
    }
    if (model.testDate.isEmpty) {
      return (
        title: 'Test not scheduled',
        message: 'This test does not have a release date yet.',
      );
    }
    if (model.testDate.compareTo(today) > 0) {
      return (
        title: 'Not unlocked yet',
        message:
            'This test unlocks on ${formatDateKeyShort(model.testDate)} at 12:00 AM. Come back then.',
      );
    }
    if (model.testDate.compareTo(today) < 0) {
      return (
        title: 'Test missed',
        message:
            'This test was only available on ${formatDateKeyShort(model.testDate)} and can no longer be attempted.',
      );
    }
    return null;
  }

  // -- boot ---------------------------------------------------------------
  Future<void> _boot() async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.go('/login');
      return;
    }
    _uid = uid;
    try {
      final profile = await fetchUserProfile(uid);
      if (!mounted) return;
      final subcourseId = profile?.subcourseId ?? '';
      if (subcourseId.isEmpty) {
        _block('Not available',
            'Choose a course first to attempt daily tests.');
        return;
      }
      // Exact id match — a stale/foreign id shows "not available",
      // never serves another model.
      final models = await fetchDailyTestModels(subcourseId);
      DailyTestModel? model;
      for (final m in models) {
        if (m.id == widget.modelId) {
          model = m;
          break;
        }
      }
      if (model == null) {
        _block('Not available',
            'This test could not be found. It may have been removed.');
        return;
      }
      // Once-per-user enforcement: server read, not local history.
      final existing =
          await fetchDailyTestResultForModel(uid, model.id);
      if (!mounted) return;
      if (existing != null) {
        showToast(context, 'You have already completed this model.',
            ToastVariant.info);
        _allowPop = true;
        final uri = Uri(
          path: '/daily-test/${model.id}/summary',
          queryParameters: {
            'answers': jsonEncode(existing.answers),
            'timeTaken': '${existing.timeTakenSeconds}',
          },
        );
        context.replace(uri.toString());
        return;
      }
      // Schedule check (deep links can't bypass the cards).
      final block = _scheduleBlock(model);
      if (block != null) {
        _block(block.title, block.message);
        return;
      }
      // A8: no premium gate here — React's quiz.tsx has none; gating lives on
      // the landing card. This also drops the forced per-open profile read.
      _isPro = profile?.isPro ?? false;
      if (!mounted) return;
      setState(() {
        _model = model;
        _answers = List<int?>.filled(model!.questions.length, null);
        _loading = false;
      });
      _startQuestionTimer(0);
    } catch (e) {
      if (!mounted) return;
      _block('Not available', 'Couldn\'t load the test. ${_cleanErr('$e')}');
    }
  }

  /// A9: React's formatClock — m:ss ("0:30", "1:05"), never "30s".
  String _formatClock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final m = safe ~/ 60;
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Strips raw JSON/API dumps from an error so the UI never shows them.
  String _cleanErr(String raw) {
    var msg = raw.replaceFirst('Exception: ', '');
    final jsonStart = msg.indexOf('{');
    if (jsonStart >= 0) msg = msg.substring(0, jsonStart).trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160).trim()}…';
    return msg.isEmpty ? 'Please try again.' : msg;
  }

  void _block(String title, String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _blockTitle = title;
      _blockMessage = message;
      _allowPop = true;
    });
  }

  // -- timer ---------------------------------------------------------------
  void _startQuestionTimer(int index) {
    _timer?.cancel();
    _blinkTimer?.cancel();
    final model = _model;
    if (model == null) return;
    _timerQuestion = index;
    setState(() {
      _qRemaining = questionTimeSeconds(model, index);
      _blinkOn = false;
    });
    _armTicker();
  }

  /// A6: resume the countdown from the preserved remaining time — a failed
  /// submit must NOT restart the full question timer.
  void _resumeQuestionTimer() {
    _timer?.cancel();
    _blinkTimer?.cancel();
    _timerQuestion = _index;
    // NOTE: _qRemaining is intentionally left untouched here.
    _armTicker();
  }

  void _armTicker() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_dialogOpen || _submitting) return;
      // The clock carries its question index so expiry can't double-fire.
      if (_timerQuestion != _index) return;
      if (!mounted) return;
      setState(() => _qRemaining -= 1);
      if (_qRemaining <= 5 && _qRemaining > 0 && _blinkTimer == null) {
        _blinkTimer =
            Timer.periodic(const Duration(milliseconds: 400), (_) {
          if (mounted) setState(() => _blinkOn = !_blinkOn);
        });
      }
      if (_qRemaining <= 0) _onExpire();
    });
  }

  void _onExpire() {
    _timer?.cancel();
    _blinkTimer?.cancel();
    if (_submitting || _dialogOpen) return;
    final model = _model;
    if (model == null) return;
    if (_index >= model.questions.length - 1) {
      _submit(auto: true);
    } else {
      setState(() => _index += 1);
      _startQuestionTimer(_index);
    }
  }

  int get _answeredCount => _answers.where((a) => a != null).length;

  // -- navigation guards ----------------------------------------------------
  Future<void> _confirmLeave() async {
    if (_allowPop || _submitting || _model == null) {
      if (mounted) context.pop();
      return;
    }
    _dialogOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave the Daily Test?'),
        content: Text(
            'Your progress will not be saved. $_answeredCount answered question(s) will be lost and this attempt will not appear in your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Leave anyway'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    if (leave == true) {
      _allowPop = true;
      if (mounted) context.pop();
    }
  }

  Future<void> _confirmSubmit() async {
    final model = _model;
    if (model == null || _submitting) return;
    final total = model.questions.length;
    final answered = _answeredCount;
    final unanswered = total - answered;
    _dialogOpen = true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Submit your answers?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$answered of $total answered.'),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                unanswered > 0
                    ? (model.negativeMarking
                        ? 'Unanswered questions score zero (but carry no penalty).'
                        : 'Unanswered questions score zero.')
                    : 'You have answered every question. Ready to see your result?',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A)),
            child:
                const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    if (ok == true) _submit();
  }

  Future<void> _submit({bool auto = false}) async {
    final model = _model;
    final uid = _uid;
    if (model == null || uid == null || _submitting) return;
    // A5: schedule re-check at submit — a blocked model never renders the quiz
    // and its clock is paused, so nothing should reach here; but scoring and
    // saving an attempt at a test the user was not allowed to take would be
    // written to the database permanently. Never write a result for an
    // unplayable model.
    final block = _scheduleBlock(model);
    if (block != null) {
      _timer?.cancel();
      _blinkTimer?.cancel();
      if (!mounted) return;
      showToast(context, '${block.title}. This attempt was not saved.',
          ToastVariant.warning);
      setState(() => _allowPop = true);
      if (mounted) context.pop();
      return;
    }
    setState(() => _submitting = true);
    _timer?.cancel();
    _blinkTimer?.cancel();
    final answers = _answers.map((a) => a ?? -1).toList();
    final score = scoreDailyTest(model, model.questions, _answers);
    final timeTaken =
        _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inSeconds;
    // A4: the real doc id comes back from saveDailyTestResult — it identifies
    // the completion marker and the activity-feed entry (no fabricated ids).
    final String resultId;
    try {
      resultId = await saveDailyTestResult(
        uid: uid,
        model: model,
        score: score,
        answers: answers,
        timeTakenSeconds: timeTaken,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast(context,
          'Could not save your result. Please try again.',
          ToastVariant.error);
      // A6: resume from the remaining time — never restart the full clock.
      _resumeQuestionTimer();
      return;
    }
    // In-memory flip so the landing card updates with no refetch.
    markDailyTestCompleted(
        uid,
        DailyTestResult(
          id: resultId,
          modelId: model.id,
          modelName: model.displayName,
          courseId: model.courseId,
          subcourseId: model.subcourseId,
          score: score.percent,
          totalQuestions: model.questions.length,
          correct: score.correct,
          incorrect: score.incorrect,
          skipped: score.skipped,
          timeTakenSeconds: timeTaken,
          answers: answers,
          createdAt: DateTime.now(),
        ));
    // On-device feed — its own try/catch: a local failure never un-saves.
    try {
      await addDailyTestActivity(
        uid,
        DailyTestActivity(
          id: resultId,
          modelId: model.id,
          modelName: model.displayName,
          score: score.percent,
          totalQuestions: model.questions.length,
          correct: score.correct,
          incorrect: score.incorrect,
          skipped: score.skipped,
          timeTakenSeconds: timeTaken,
          completedAt: DateTime.now().millisecondsSinceEpoch,
          answers: answers,
          passed: score.passed,
          passPercent:
              model.passPercent > 0 ? model.passPercent : 40,
        ),
      );
    } catch (_) {}
    if (!mounted) return;
    _allowPop = true;
    final uri = Uri(
      path: '/daily-test/${model.id}/summary',
      queryParameters: {
        'answers': jsonEncode(answers),
        'timeTaken': '$timeTaken',
      },
    );
    context.replace(uri.toString());
    if (auto) {
      // The auto-submit path replaces before the toast would show;
      // nothing further to do.
    }
  }

  void _select(int optionIndex) {
    if (_submitting || _dialogOpen) return;
    setState(() {
      // Tapping the selected option again clears it (-1 = skipped).
      _answers[_index] =
          _answers[_index] == optionIndex ? null : optionIndex;
    });
  }

  void _next() {
    final model = _model;
    if (model == null || _submitting) return;
    if (_index >= model.questions.length - 1) {
      _confirmSubmit();
    } else {
      setState(() => _index += 1);
      _startQuestionTimer(_index);
    }
  }

  /// B1: React's quiz.tsx uses its own gradient header (model name +
  /// subcourse subtitle), not the generic SubpageHeader. Full-bleed like
  /// SubpageHeader: transparent status bar + its own top inset inside the
  /// gradient, so it is the first body child with no outer top padding.
  ///
  /// The subtitle falls back to 'Daily Test' (React's own fallback) — the
  /// Flutter profile carries only course ids, and no extra read is spent
  /// resolving names for a subtitle.
  Widget _quizHeader(bool isDark) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2563EB),
              Color(0xFF1D4ED8),
              Color(0xFF0B1F5B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _confirmLeave,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_back,
                        size: 20, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _model?.displayName ?? 'Daily Test',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Daily Test',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white
                                .withValues(alpha: 0.85),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => ThemeService.toggle(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                        isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        size: 20,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- build -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA),
        body: SafeArea(
          // The header paints behind the status bar itself (React parity) —
          // no top inset here or the header gets pushed down.
          top: false,
          child: Column(
            children: [
              _quizHeader(isDark),
              Expanded(child: _body(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_blockTitle != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_busy,
                    size: 32, color: Color(0xFF2563EB)),
              ),
              const SizedBox(height: 16),
              Text(_blockTitle!,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_blockMessage ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: const Text('Go back',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    final model = _model!;
    final q = model.questions[_index];
    final total = model.questions.length;
    final isLast = _index == total - 1;
    // B9: the category row shows only the question's own category — when it is
    // empty the row is hidden (no fallback to the model category, like React).
    final hasCategory = q.category.isNotEmpty;
    final warning = _qRemaining <= 5;
    final timerColor =
        warning ? const Color(0xFFDC2626) : const Color(0xFF2563EB);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF151D2E) : Colors.white,
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF26314B)
                        : const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.layers_outlined,
                                size: 13, color: Color(0xFF2563EB)),
                            const SizedBox(width: 5),
                            Text('Q ${_index + 1} / $total',
                                style: const TextStyle(
                                    color: Color(0xFF2563EB),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Timer pill — blinks red in the last 5 seconds.
                      AnimatedOpacity(
                        opacity:
                            warning && !_blinkOn ? 0.35 : 1.0,
                        duration:
                            const Duration(milliseconds: 200),
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 74),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: timerColor
                                .withValues(alpha: 0.1),
                            // B8: `${timerColor}55`-equivalent border (~33% alpha).
                            border: Border.all(
                                color: timerColor
                                    .withValues(alpha: 0.33)),
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 13, color: timerColor),
                              const SizedBox(width: 5),
                              Text(
                                _formatClock(_qRemaining),
                                style: TextStyle(
                                  color: timerColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // A7: per-question bookmark + report, mirroring React
                      // quiz.tsx (BookmarkButton context "daily-test",
                      // refId "${model.id}:$currentIndex"; ReportButton).
                      _QuestionBookmarkButton(
                        key: ValueKey('${model.id}:$_index'),
                        uid: _uid ?? '',
                        model: model,
                        index: _index,
                        isPro: _isPro,
                      ),
                      IconButton(
                        onPressed: () =>
                            context.push('/settings/report-problem'),
                        icon: const Icon(Icons.flag_outlined,
                            size: 20),
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF6B7280),
                        tooltip: 'Report',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                  if (hasCategory) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.sell_outlined,
                            size: 13,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(q.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF6B7280))),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(q.question,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.5)),
                  const Divider(height: 28),
                  ...List.generate(q.options.length, (oi) {
                    final selected = _answers[_index] == oi;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => _select(oi),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF2563EB)
                                  : (isDark
                                      ? const Color(0xFF26314B)
                                      : const Color(0xFFE5E7EB)),
                              width: 1.5,
                            ),
                            color: selected
                                ? const Color(0xFF2563EB)
                                    .withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? const Color(0xFF2563EB)
                                      : (isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  String.fromCharCode(65 + oi),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : (isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(
                                                  0xFF475569))),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(q.options[oi],
                                    style: const TextStyle(
                                        fontSize: 14, height: 1.4)),
                              ),
                              if (selected)
                                const Icon(Icons.check_circle,
                                    size: 20,
                                    color: Color(0xFF2563EB)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0B1120)
                : const Color(0xFFF5F6FA),
            border: Border(
                top: BorderSide(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              Text('$_answeredCount / $total answered',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF6B7280))),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _next,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Icon(
                            isLast
                                ? Icons.check
                                : Icons.chevron_right,
                            color: Colors.white),
                    label: Text(isLast ? 'Submit' : 'Next',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLast
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Per-question bookmark toggle for the daily-test quiz — the Flutter
/// equivalent of React's BookmarkButton (context "daily-test",
/// refId "${model.id}:${index}"). Bookmarks live at users/{uid}/bookmarks
/// with the same doc-id scheme as the Expo app (`daily-test__<ref>`), so the
/// Bookmarks screen lists them without changes.
class _QuestionBookmarkButton extends StatefulWidget {
  final String uid;
  final DailyTestModel model;
  final int index;
  final bool isPro;

  const _QuestionBookmarkButton({
    super.key,
    required this.uid,
    required this.model,
    required this.index,
    required this.isPro,
  });

  @override
  State<_QuestionBookmarkButton> createState() =>
      _QuestionBookmarkButtonState();
}

class _QuestionBookmarkButtonState extends State<_QuestionBookmarkButton> {
  static const _freeLimit = 15;
  bool _saved = false;
  bool _busy = false;

  /// Mirrors React's bookmarkDocId(): `daily-test__<safeSegment(refId)>`.
  String get _docId {
    var ref = '${widget.model.id}:${widget.index}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ref.length > 90) ref = ref.substring(0, 90);
    return 'daily-test__${ref.isEmpty ? 'item' : ref}';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (widget.uid.isEmpty) return;
    try {
      final idToken = await AuthService.getValidIdToken();
      final doc = await FirestoreRest.getDocument(
          'users/${widget.uid}/bookmarks/$_docId',
          idToken: idToken);
      if (mounted) setState(() => _saved = doc != null);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_busy || widget.uid.isEmpty) return;
    setState(() => _busy = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      final path = 'users/${widget.uid}/bookmarks/$_docId';
      if (_saved) {
        await FirestoreRest.deleteDocument(path, idToken: idToken);
        if (!mounted) return;
        setState(() {
          _saved = false;
          _busy = false;
        });
        showToast(context, 'Bookmark removed.', ToastVariant.info);
        return;
      }
      final rows = await FirestoreRest.listDocuments(
          'users/${widget.uid}/bookmarks',
          idToken: idToken);
      if (rows.length >= _freeLimit && !widget.isPro) {
        if (!mounted) return;
        setState(() => _busy = false);
        showToast(context, 'Bookmark slots are full', ToastVariant.warning);
        return;
      }
      final q = widget.model.questions[widget.index];
      await FirestoreRest.setDocument(
        path,
        {
          'context': 'daily-test',
          'kind': 'question',
          'refId': '${widget.model.id}:${widget.index}',
          'title': q.question,
          'preview': q.explanation,
          'sourceLabel': 'Daily Test',
          'courseId': widget.model.courseId,
          'subcourseId': widget.model.subcourseId,
          'payload': {
            'question': q.question,
            'options': q.options,
            'answerIndex': q.correctIndex,
            'explanation': q.explanation,
          },
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        idToken: idToken,
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      showToast(context, 'Saved to bookmarks.', ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(
          context,
          'Could not update the bookmark. Please try again.',
          ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      onPressed: _busy ? null : _toggle,
      icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border,
          size: 20),
      color: _saved
          ? const Color(0xFF2563EB)
          : (isDark
              ? const Color(0xFF94A3B8)
              : const Color(0xFF6B7280)),
      tooltip: _saved ? 'Remove bookmark' : 'Bookmark',
      padding: EdgeInsets.zero,
      constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
