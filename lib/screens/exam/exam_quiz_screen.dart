import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/profile_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/syllabus_entrance.dart';

/// Exam quiz — mirrors app/exam/[setId]/quiz.tsx same-to-same.
///
/// Gradient header (back with leave-guard, title + subcourse subtitle, theme
/// toggle), left question-number rail, Q pill + timer pill (red under 30s),
/// report button, tap-again-to-deselect, Previous/Next/Submit bottom bar,
/// leave + submit confirms via [AppModalShell], auto-submit on timeout with
/// `pushReplacement` to the summary.
class ExamQuizScreen extends StatefulWidget {
  final String setId;

  /// Title passed from the launching card so the header shows it instantly
  /// during preloading (no empty-title flash).
  final String? initialTitle;

  const ExamQuizScreen({super.key, required this.setId, this.initialTitle});

  @override
  State<ExamQuizScreen> createState() => _ExamQuizScreenState();
}

class _ExamQuizScreenState extends State<ExamQuizScreen> {
  ExamSet? _set;
  bool _loading = true;
  String? _error;

  int _index = 0;
  List<int> _answers = const []; // -1 = unanswered
  int? _remaining;
  Timer? _timer;
  DateTime? _startedAt;
  bool _submitted = false;
  bool _submitting = false;
  bool _canPop = false;

  /// Header height minus the overlap, so the question rail slides *under*
  /// the header's rounded bottom edge instead of peeking beside it.
  final _headerKey = GlobalKey();
  double _headerReserve = 0;

  static const _gradientColors = [
    Color(0xFF2563EB),
    Color(0xFF1D4ED8),
    Color(0xFF0B1F5B),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncHeaderReserve());
  }

  /// Measures the header so the body can tuck 24px under its rounded
  /// bottom edge (point 8). Only setStates when the height actually moved.
  void _syncHeaderReserve() {
    final box =
        _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final reserve = (box.size.height - 24).clamp(0.0, 10000.0);
    if ((reserve - _headerReserve).abs() > 0.5) {
      setState(() => _headerReserve = reserve);
    }
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
      if (set == null || set.questions.isEmpty) {
        throw Exception('empty');
      }
      if (!mounted) return;
      // The timer starts now — the rules were already confirmed on the tab,
      // so reading them never eats into exam time.
      setState(() {
        _set = set;
        _answers = List<int>.filled(set.questions.length, -1);
        _remaining = set.durationMinutes * 60;
        _startedAt = DateTime.now();
        _loading = false;
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _syncHeaderReserve());
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _submitted) return;
        _syncHeaderReserve();
        final left = (_remaining ?? 1) - 1;
        if (left <= 0) {
          _timer?.cancel();
          _submit(auto: true);
          return;
        }
        setState(() => _remaining = left);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Exam not available', 'परीक्षा उपलब्ध छैन');
        _loading = false;
      });
    }
  }

  String get _clock {
    final total = _remaining ?? 0;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _answeredCount => _answers.where((a) => a >= 0).length;
  bool get _isLast => _set != null && _index >= _set!.questions.length - 1;

  // ---------- confirms ----------

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
        tagLabel: AppLanguage.tr('Leave the exam?', 'परीक्षा छोड्ने?'),
        title: Text(
          AppLanguage.tr('Your attempt will not be saved.',
              'तपाईंको प्रयास सेभ हुनेछैन।'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        body: Text(
          AppLanguage.tr(
              'Your attempt will not be saved and the questions you have answered will be lost.',
              'तपाईंको प्रयास सेभ हुनेछैन र उत्तर दिएका प्रश्नहरू गुम्नेछन्।'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF475569),
            height: 1.5,
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppLanguage.tr('Keep going', 'जारी राख्नुहोस्')),
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
        tagLabel:
            AppLanguage.tr('Submit your exam?', 'परीक्षा बुझाउने?'),
        title: Text(
          AppLanguage.tr(
              unanswered > 0
                  ? '$unanswered question(s) are still unanswered.'
                  : 'You have answered every question.',
              unanswered > 0
                  ? '$unanswered प्रश्नको उत्तर बाँकी छ।'
                  : 'सबै प्रश्नको उत्तर दिनुभयो।'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        body: Text(
          unanswered > 0
              ? AppLanguage.tr(
                  'Unanswered questions score zero but carry no penalty.',
                  'उत्तर नदिएका प्रश्नमा शून्य अंक, जरिवाना लाग्दैन।')
              : AppLanguage.tr(
                  'Ready to submit?', 'बुझाउन तयार हुनुहुन्छ?'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF475569),
            height: 1.5,
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child:
                    Text(AppLanguage.tr('Review first', 'पहिले हेर्नुहोस्')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
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

  Future<void> _submit({required bool auto}) async {
    if (_submitted || _submitting) return;
    final set = _set;
    if (set == null) return;
    setState(() => _submitting = true);
    final timeTaken =
        DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds;
    final score = scoreExamAttempt(set.questions, _answers, set.passPercent);
    final user = AuthService.currentUser;
    final profile = ProfileStore.instance.profile;
    bool saved = true;
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
      saved = false;
    }
    if (!mounted) return;
    if (!saved) {
      // Like React: a failed save keeps the user on the quiz with an error.
      setState(() => _submitting = false);
      showToast(
        context,
        AppLanguage.tr('Could not save your attempt. Check your connection.',
            'तपाईंको प्रयास सेभ हुन सकेन। इन्टरनेट हेर्नुहोस्।'),
        ToastVariant.error,
      );
      return;
    }
    if (auto && mounted) {
      showToast(
        context,
        AppLanguage.tr(
            'Time is up — your exam was submitted automatically.',
            'समय सकियो — तपाईंको परीक्षा स्वतः बुझाइयो।'),
        ToastVariant.info,
      );
    }
    setState(() {
      _submitted = true;
      _submitting = false;
    });
    _timer?.cancel();
    // replace(), not push(): the quiz is never reachable with Back.
    // Point 9: the score is computed here inside the submitting overlay, so
    // the summary renders instantly with no middle "Preparing" loading.
    context.pushReplacement(
      '/exam/${set.id}/summary'
      '?answers=${Uri.encodeComponent(jsonEncode(_answers))}'
      '&timeTaken=$timeTaken'
      '&title=${Uri.encodeComponent(set.title)}'
      '&percent=${score.percent}'
      '&marks=${score.marks}'
      '&correct=${score.correct}'
      '&wrong=${score.incorrect}'
      '&skipped=${score.skipped}'
      '&negative=${score.negativeMarks}'
      '&passed=${score.passed ? '1' : '0'}'
      '&passMark=${set.passPercent}'
      '&total=${set.questions.length}',
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

  /// Premium question card — the bookmark + report icons live on the card
  /// itself (top-right), next to the "Question" label.
  Widget _questionCard(ExpoPalette palette, ExamQuestion q) {
    final uid = AuthService.currentUser?.uid ?? '';
    final profile = ProfileStore.instance.profile;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppLanguage.tr('Question', 'प्रश्न'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: palette.textSecondary),
              ),
              const Spacer(),
              _QuizBookmarkButton(
                key: ValueKey('qbm_$_index'),
                uid: uid,
                setId: widget.setId,
                index: _index,
                question: q,
                examTitle: _set?.title ?? '',
                subcourseId: _set?.subcourseId ?? '',
                isPro: profile?.isPremium == true,
              ),
              IconButton(
                tooltip: AppLanguage.tr('Report', 'रिपोर्ट'),
                onPressed: _reportQuestion,
                icon: Icon(Icons.flag_outlined,
                    size: 20, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(q.question,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 26 / 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_submitted) {
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
        backgroundColor: palette.background,
        body: Stack(
          children: [
            Column(
              children: [
                // Reserve the header's height minus 24px: the body tucks
                // under the header's rounded bottom edge, which is painted
                // on top and hides the rail's sharp top corners.
                SizedBox(height: _headerReserve),
                Expanded(
                  child: _loading
                      ? PreloadingWidget(
                          tinted: false,
                          label: AppLanguage.tr(
                              'Loading Exam…', 'परीक्षा लोड हुँदै…'),
                        )
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(
                                      AppLanguage.tr(
                                          'This exam set has no questions yet.',
                                          'यस परीक्षामा अहिलेसम्म प्रश्न छैन।'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: palette.textSecondary),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text(AppLanguage.tr(
                                          'Go back', 'फर्कनुहोस्')),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _quizBody(palette),
                ),
              ],
            ),
            // Header painted last = on top, covering the rail's top edge.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: KeyedSubtree(
                key: _headerKey,
                child: _buildHeader(palette),
              ),
            ),
            if (_submitting)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: PreloadingWidget(
                      tinted: true,
                      label: AppLanguage.tr('Submitting your answers…',
                          'उत्तरहरू बुझाइँदै…'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Gradient header: back (leave-guarded), title + subcourse subtitle,
  /// theme toggle — mirrors quiz.tsx (24px bottom radius).
  Widget _buildHeader(ExpoPalette palette) {
    final courseInfo = ProfileStore.instance.courseInfo;
    final subLabel = courseInfo?.subcourseName ??
        courseInfo?.courseName ??
        '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1D4ED8),
          gradient: LinearGradient(
            colors: _gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (await _confirmLeave()) {
                      _canPop = true;
                      if (mounted) Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back,
                        size: 20, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _set?.title ?? widget.initialTitle ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subLabel.isNotEmpty)
                        Text(
                          subLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => ThemeService.toggle(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quizBody(ExpoPalette palette) {
    final set = _set!;
    final q = set.questions[_index];
    final total = set.questions.length;
    final lowTime = (_remaining ?? 61) <= 30;
    final timerColor =
        lowTime ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Question-number rail (52 wide, surfaceAlt — React parity).
              Container(
                width: 52,
                color: palette.surfaceAlt,
                child: ListView.builder(
                  // +24 top: the first 24px tuck under the header.
                  padding: const EdgeInsets.fromLTRB(6, 32, 6, 8),
                  itemCount: total,
                  itemBuilder: (c, i) {
                    final answered = _answers[i] >= 0;
                    final current = i == _index;
                    return GestureDetector(
                      onTap: () => setState(() => _index = i),
                      child: Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: current
                              ? palette.primary
                              : answered
                                  ? const Color(0xFF16A34A)
                                      .withValues(alpha: 0.13)
                                  : palette.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: current
                                ? palette.primary
                                : answered
                                    ? const Color(0xFF16A34A)
                                    : palette.border,
                            width: 1.5,
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
                                          ? const Color(0xFF16A34A)
                                          : palette.textSecondary)),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Question + options.
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      // +24 top: the first 24px tuck under the header.
                      // ValueKey(_index): every question change rebuilds the
                      // subtree fresh so the option entrance animation replays
                      // on ALL questions, not just the first.
                      child: ListView(
                        key: ValueKey('q$_index'),
                        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                        children: [
                          // Q pill + timer pill.
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: palette.primary
                                      .withValues(alpha: 0.09),
                                  borderRadius:
                                      BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Q ${_index + 1} / $total',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: palette.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: timerColor.withValues(alpha: 0.09),
                                  borderRadius:
                                      BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time,
                                        size: 13, color: timerColor),
                                    const SizedBox(width: 5),
                                    Text(_clock,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: timerColor)),
                                  ],
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Question card — bookmark + report live on it.
                          _questionCard(palette, q),
                          const SizedBox(height: 16),
                          ...List.generate(q.options.length, (oi) {
                            final selected = _answers[_index] == oi;
                            const letters = [
                              'A', 'B', 'C', 'D', 'E', 'F'
                            ];
                            final letter = oi < letters.length
                                ? letters[oi]
                                : '${oi + 1}';
                            // Point 11: the shared syllabus/profile entrance
                            // (380ms easeOut, 24px rise) on every option.
                            return SyllabusEntrance(
                              delayMs: (oi.clamp(0, 8)) * 60,
                              child: GestureDetector(
                              onTap: () => setState(() {
                                // Tap again to deselect.
                                _answers[_index] =
                                    _answers[_index] == oi ? -1 : oi;
                              }),
                              child: Container(
                                margin:
                                    const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? palette.primary
                                          .withValues(alpha: 0.07)
                                      : palette.surface,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? palette.primary
                                        : palette.border,
                                    width: 1.5,
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
                                            ? palette.primary
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: selected
                                              ? palette.primary
                                              : palette.border,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(letter,
                                            style: TextStyle(
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 12,
                                                color: selected
                                                    ? Colors.white
                                                    : palette
                                                        .textSecondary)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(q.options[oi],
                                            style: const TextStyle(
                                                fontSize: 14))),
                                  ],
                                ),
                              ),
                            ),
                            );
                          }),
                        ],
                      ),
                    ),
                    // Bottom bar.
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        border: Border(
                            top: BorderSide(
                                color: palette.divider, width: 1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_answeredCount / $total ${AppLanguage.tr('answered', 'उत्तर दिइयो')}',
                            style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (_index > 0)
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _index--),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 14),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                          color: palette.border,
                                          width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.chevron_left,
                                            size: 16,
                                            color: palette.textPrimary),
                                        const SizedBox(width: 6),
                                        Text(
                                            AppLanguage.tr('Previous',
                                                'अघिल्लो'),
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: palette
                                                    .textPrimary)),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_index > 0) const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _isLast
                                      ? _confirmSubmit
                                      : () => setState(() => _index++),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    decoration: BoxDecoration(
                                      color: _isLast
                                          ? const Color(0xFF16A34A)
                                          : palette.primary,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                            _isLast
                                                ? AppLanguage.tr(
                                                    'Submit', 'बुझाउनुहोस्')
                                                : AppLanguage.tr(
                                                    'Next', 'अर्को'),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.bold)),
                                        const SizedBox(width: 6),
                                        Icon(
                                            _isLast
                                                ? Icons.done_all
                                                : Icons.chevron_right,
                                            size: 16,
                                            color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bookmark toggle for one exam-quiz question. Same storage scheme as the
/// practice bookmark button (`exam__<ref>` docs under users/{uid}/bookmarks,
/// context "exam", kind "question") so the Bookmarks screen renders them with
/// no changes. Same free-tier cap: 15 per sub-course.
class _QuizBookmarkButton extends StatefulWidget {
  final String uid;
  final String setId;
  final int index;
  final ExamQuestion question;
  final String examTitle;
  final String subcourseId;
  final bool isPro;

  const _QuizBookmarkButton({
    super.key,
    required this.uid,
    required this.setId,
    required this.index,
    required this.question,
    required this.examTitle,
    required this.subcourseId,
    required this.isPro,
  });

  @override
  State<_QuizBookmarkButton> createState() => _QuizBookmarkButtonState();
}

class _QuizBookmarkButtonState extends State<_QuizBookmarkButton> {
  static const _freeLimit = 15;
  bool _saved = false;
  bool _busy = false;
  Timer? _saveTimer;
  int _opId = 0;

  String get _refId => '${widget.setId}#${widget.index}';

  String get _docId {
    var ref = _refId
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (ref.length > 90) ref = ref.substring(0, 90);
    if (ref.isEmpty) ref = 'item';
    return 'exam__$ref';
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
        idToken: idToken,
      );
      if (mounted) setState(() => _saved = doc != null);
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _onTap() {
    if (_busy || widget.uid.isEmpty) return;
    if (_saved) {
      _remove();
      return;
    }
    setState(() => _busy = true);
    _saveTimer?.cancel();
    final op = ++_opId;
    unawaited(_saveInBackground(op));
    _saveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saved = true;
      });
      showToast(context,
          AppLanguage.tr('Saved to bookmarks.', 'बुकमार्कमा बचत भयो।'),
          ToastVariant.success);
    });
  }

  Future<void> _saveInBackground(int op) async {
    final path = 'users/${widget.uid}/bookmarks/$_docId';
    try {
      final idToken = await AuthService.getValidIdToken();
      final rows = await FirestoreRest.listDocuments(
        'users/${widget.uid}/bookmarks',
        idToken: idToken,
      );
      final scoped = widget.subcourseId.isEmpty
          ? rows.length
          : rows
              .where((r) =>
                  (r['subcourseId'] ?? '') == widget.subcourseId)
              .length;
      if (scoped >= _freeLimit && !widget.isPro) {
        if (op != _opId || !mounted) return;
        _saveTimer?.cancel();
        setState(() => _busy = false);
        showToast(
            context,
            AppLanguage.tr('Bookmark limit reached for this sub-course',
                'यस उप-पाठ्यक्रमका लागि बुकमार्क सीमा पुग्यो'),
            ToastVariant.warning);
        return;
      }
      final q = widget.question;
      await FirestoreRest.setDocument(
        path,
        {
          'context': 'exam',
          'kind': 'question',
          'refId': _refId,
          'title': q.question,
          'preview': q.explanation,
          'sourceLabel': widget.examTitle,
          'subcourseId': widget.subcourseId,
          'payload': {
            'question': q.question,
            'options': q.options,
            'answerIndex': q.correctIndex,
            'explanation': q.explanation,
            'meta': widget.examTitle.isNotEmpty
                ? [
                    {'label': 'Exam', 'value': widget.examTitle}
                  ]
                : null,
          },
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        idToken: idToken,
      );
    } catch (_) {
      if (op != _opId || !mounted) return;
      _saveTimer?.cancel();
      setState(() {
        _busy = false;
        _saved = false;
      });
      showToast(
          context,
          AppLanguage.tr('Could not update the bookmark. Please try again.',
              'बुकमार्क अद्यावधिक हुन सकेन। कृपया पुनः प्रयास गर्नुहोस्।'),
          ToastVariant.error);
    }
  }

  Future<void> _remove() async {
    _opId++;
    _saveTimer?.cancel();
    setState(() => _busy = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument(
          'users/${widget.uid}/bookmarks/$_docId',
          idToken: idToken);
      if (!mounted) return;
      setState(() {
        _saved = false;
        _busy = false;
      });
      showToast(
          context,
          AppLanguage.tr(
              'Removed from bookmarks.', 'बुकमार्कबाट हटाइयो।'),
          ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(
          context,
          AppLanguage.tr('Could not update the bookmark. Please try again.',
              'बुकमार्क अद्यावधिक हुन सकेन। कृपया पुनः प्रयास गर्नुहोस्।'),
          ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return IconButton(
      tooltip: AppLanguage.tr('Bookmark', 'बुकमार्क'),
      onPressed: _onTap,
      icon: _busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: palette.textSecondary),
            )
          : Icon(
              _saved ? Icons.bookmark : Icons.bookmark_outline,
              size: 20,
              color: _saved ? palette.primary : palette.textSecondary,
            ),
    );
  }
}
