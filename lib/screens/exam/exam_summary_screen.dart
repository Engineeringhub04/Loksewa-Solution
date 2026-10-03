import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../tabs_screen.dart';

/// Result summary shown straight after submitting — mirrors
/// app/exam/[setId]/summary.tsx same-to-same.
///
/// Answers arrive via route params (JSON, exactly what was submitted) rather
/// than a re-read. Review Answers stays locked until the exam's own window
/// closes so finishing early can't leak answers.
class ExamSummaryScreen extends StatefulWidget {
  final String setId;
  final String? answers; // JSON array, -1 = skipped
  final int? timeTaken;

  /// Pre-computed result (passed from the quiz's submitting overlay so the
  /// summary renders instantly with no middle "Preparing" loading — point 9).
  /// When present the set is still fetched in the background for review
  /// navigation and unlock checks.
  final String? instantTitle;
  final int? instantPercent;
  final double? instantMarks;
  final int? instantCorrect;
  final int? instantIncorrect;
  final int? instantSkipped;
  final double? instantNegativeMarks;
  final bool? instantPassed;
  final int? instantPassMark;
  final int? instantTotalQuestions;

  bool get hasInstant =>
      instantPercent != null &&
      instantMarks != null &&
      instantCorrect != null &&
      instantIncorrect != null &&
      instantSkipped != null &&
      instantNegativeMarks != null &&
      instantPassed != null &&
      instantPassMark != null &&
      instantTotalQuestions != null;

  const ExamSummaryScreen({
    super.key,
    required this.setId,
    this.answers,
    this.timeTaken,
    this.instantTitle,
    this.instantPercent,
    this.instantMarks,
    this.instantCorrect,
    this.instantIncorrect,
    this.instantSkipped,
    this.instantNegativeMarks,
    this.instantPassed,
    this.instantPassMark,
    this.instantTotalQuestions,
  });

  @override
  State<ExamSummaryScreen> createState() => _ExamSummaryScreenState();
}

class _Verdict {
  final Color color;
  final IconData icon;
  final String title;
  final String message;
  const _Verdict(this.color, this.icon, this.title, this.message);
}

_Verdict _verdict(int percent, bool passed) {
  if (percent >= 85) {
    return _Verdict(
      const Color(0xFF16A34A),
      Icons.emoji_events_outlined,
      AppLanguage.tr('Outstanding!', 'उत्कृष्ट!'),
      AppLanguage.tr(
          'This is top-rank territory. Keep this consistency and the real exam will feel routine.',
          'यो शीर्ष स्थानको क्षेत्र हो। यो निरन्तरता राख्नुहोस्, वास्तविक परीक्षा सजिलो लाग्नेछ।'),
    );
  }
  if (percent >= 60) {
    return _Verdict(
      const Color(0xFF2563EB),
      Icons.military_tech_outlined,
      AppLanguage.tr('Well done!', 'राम्रो!'),
      AppLanguage.tr(
          'A solid, comfortable pass. Tighten the few topics you slipped on and you are in strong shape.',
          'राम्रोसँग उत्तीर्ण। चुक्नुभएका विषयहरू सुधार्नुहोस्, तपाईं बलियो अवस्थामा हुनुहुन्छ।'),
    );
  }
  if (passed) {
    return _Verdict(
      const Color(0xFFD97706),
      Icons.check_circle_outline,
      AppLanguage.tr('You passed', 'तपाईं उत्तीर्ण हुनुभयो'),
      AppLanguage.tr(
          'You are over the line, but there is real room to grow. Review the explanations and try again.',
          'तपाईं पास हुनुभयो, तर सुधार्ने ठाउँ धेरै छ। व्याख्या हेर्नुहोस् र पुनः प्रयास गर्नुहोस्।'),
    );
  }
  return _Verdict(
    const Color(0xFFDC2626),
    Icons.refresh,
    AppLanguage.tr('Not this time', 'यसपटक भएन'),
    AppLanguage.tr(
        'Every attempt shows you exactly what to study next. Read the explanations and re-attempt — this is how scores climb.',
        'हरेक प्रयासले के पढ्ने देखाउँछ। व्याख्या पढ्नुहोस् र पुनः प्रयास गर्नुहोस् — यसरी नै स्कोर बढ्छ।'),
  );
}

class _ExamSummaryScreenState extends State<ExamSummaryScreen> {
  ExamSet? _set;
  bool _loading = true;
  String? _error;

  List<int> _parseAnswers(String? param) {
    if (param == null || param.isEmpty) return [];
    try {
      final parsed = jsonDecode(param);
      if (parsed is List) {
        return parsed
            .map((v) => v is num ? v.toInt() : int.tryParse('$v') ?? -1)
            .toList();
      }
    } catch (_) {}
    // Fallback for legacy comma-separated params.
    return param
        .replaceAll(RegExp(r'[\[\]\s]'), '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s.trim()) ?? -1)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.hasInstant) {
      // Point 9: result already computed in the quiz's submitting overlay —
      // render instantly, no middle "Preparing" loading. The set still loads
      // in the background for review navigation + unlock checks.
      _loading = false;
      _loadSetBackground();
    } else {
      _load();
    }
  }

  /// Background set fetch for the instant path (review + unlock only).
  Future<void> _loadSetBackground() async {
    try {
      final set = await fetchExamSet(widget.setId);
      if (!mounted) return;
      setState(() => _set = set);
    } catch (_) {
      // Instant result already shows; review just stays gated.
    }
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
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Result unavailable', 'नतिजा उपलब्ध छैन');
        _loading = false;
      });
    }
  }

  String _hm(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  void _openReview() {
    final set = _set;
    if (set == null) {
      // Background fetch still in flight — ask for a beat.
      showToast(
        context,
        AppLanguage.tr('Loading…', 'लोड हुँदै…'),
        ToastVariant.info,
      );
      return;
    }
    final now = DateTime.now();
    if (!areResultsUnlocked(set, now)) {
      final unlock = resultsUnlockAt(set, now);
      showToast(
        context,
        AppLanguage.tr(
            'Answers unlock at ${_hm(unlock.toUtc().add(const Duration(hours: 5, minutes: 45)))}.',
            'उत्तरहरू अहिले उपलब्ध छैनन्।'),
        ToastVariant.info,
      );
      return;
    }
    context.push(
      '/exam/${set.id}/review'
      '?answers=${Uri.encodeComponent(jsonEncode(_parseAnswers(widget.answers)))}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    if (_loading) {
      // No header while loading — header + result arrive together in one step.
      return Scaffold(
        backgroundColor: palette.background,
        body: PreloadingWidget(
          tinted: false,
          label: AppLanguage.tr(
              'Preparing your result…', 'तपाईंको नतिजा तयार हुँदै…'),
        ),
      );
    }
    if (_error != null || (_set == null && !widget.hasInstant)) {
      return Scaffold(
        backgroundColor: palette.background,
        body: Column(
          children: [
            SubpageHeader(title: AppLanguage.tr('Result', 'नतिजा')),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? ''),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => context.go('/'),
                      child: Text(
                          AppLanguage.tr('Back to Exams', 'परीक्षामा फर्कनुहोस्')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Back goes to the exam detail screen: the quiz was replaced (not
          // pushed), so the detail screen is still underneath.
          SubpageHeader(title: AppLanguage.tr('Your Result', 'तपाईंको नतिजा')),
          Expanded(child: _body(palette)),
        ],
      ),
    );
  }

  Widget _body(ExpoPalette palette) {
    final set = _set;
    final answers = _parseAnswers(widget.answers);
    // Instant path (point 9): breakdown already computed by the quiz.
    final ScoreBreakdown breakdown;
    final int totalQuestions;
    final int passPercent;
    if (set != null) {
      final padded = List<int>.filled(set.questions.length, -1);
      for (var i = 0; i < padded.length && i < answers.length; i++) {
        padded[i] = answers[i];
      }
      breakdown =
          scoreExamAttempt(set.questions, padded, set.passPercent);
      totalQuestions = set.questions.length;
      passPercent = set.passPercent;
    } else {
      breakdown = ScoreBreakdown(
        correct: widget.instantCorrect!,
        incorrect: widget.instantIncorrect!,
        skipped: widget.instantSkipped!,
        marks: widget.instantMarks!,
        percent: widget.instantPercent!,
        negativeMarks: widget.instantNegativeMarks!,
        passed: widget.instantPassed!,
      );
      totalQuestions = widget.instantTotalQuestions!;
      passPercent = widget.instantPassMark!;
    }
    final band = _verdict(breakdown.percent, breakdown.passed);
    // Before the background set fetch lands, review stays gated.
    final unlocked = set != null && areResultsUnlocked(set, DateTime.now());
    final unlockAt =
        set != null ? resultsUnlockAt(set, DateTime.now()) : DateTime.now();
    final elapsed = widget.timeTaken ?? 0;

    final stats = [
      _Stat(Icons.check_circle, AppLanguage.tr('Correct', 'सही'),
          '${breakdown.correct}', const Color(0xFF16A34A)),
      _Stat(Icons.cancel, AppLanguage.tr('Incorrect', 'गलत'),
          '${breakdown.incorrect}', const Color(0xFFDC2626)),
      _Stat(Icons.remove_circle_outline, AppLanguage.tr('Skipped', 'छोडियो'),
          '${breakdown.skipped}', palette.textSecondary),
      _Stat(Icons.access_time, AppLanguage.tr('Time taken', 'लागेको समय'),
          _duration(elapsed), const Color(0xFF2563EB)),
      _Stat(Icons.trending_down,
          AppLanguage.tr('Negative marking', 'नकारात्मक अंक'),
          '-${breakdown.negativeMarks.toStringAsFixed(2)}',
          const Color(0xFFD97706)),
      _Stat(Icons.military_tech_outlined,
          AppLanguage.tr('Pass mark', 'उत्तीर्णांक'),
          '$passPercent%', const Color(0xFF7C3AED)),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Score card.
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: CircularProgressIndicator(
                        value: breakdown.percent / 100,
                        strokeWidth: 13,
                        backgroundColor:
                            band.color.withValues(alpha: 0.15),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(band.color),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${breakdown.percent}%',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: band.color)),
                        Text(
                          '${breakdown.marks.toStringAsFixed(2)} / $totalQuestions',
                          style: TextStyle(
                              fontSize: 12,
                              color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: band.color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(band.icon, size: 16, color: band.color),
                    const SizedBox(width: 6),
                    Text(
                      breakdown.passed
                          ? AppLanguage.tr('PASSED', 'उत्तीर्ण')
                          : AppLanguage.tr('FAILED', 'अनुत्तीर्ण'),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: band.color),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(band.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(band.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      height: 21 / 14,
                      color: palette.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Stats grid.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: stats
              .map((s) => _statCard(palette, s))
              .toList(),
        ),
        const SizedBox(height: 16),
        // Lock notice.
        if (!unlocked)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: palette.warning.withValues(alpha: 0.27),
                  width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline,
                    size: 18, color: palette.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLanguage.tr(
                        'Answer review and rankings unlock once the exam window closes at ${_hm(unlockAt.toUtc().add(const Duration(hours: 5, minutes: 45)))}.',
                        'परीक्षा समय सकिएपछि उत्तर समीक्षा र र्याङ्किङ खुल्नेछ।'),
                    style: TextStyle(
                        fontSize: 13, color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (!unlocked) const SizedBox(height: 16),
        // Actions.
        GestureDetector(
          onTap: _openReview,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: unlocked ? palette.primary : palette.textDisabled,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(unlocked ? Icons.visibility_outlined : Icons.lock_outline,
                    size: 17, color: Colors.white),
                const SizedBox(width: 8),
                Text(AppLanguage.tr('Review Answers', 'उत्तर समीक्षा'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _secondaryAction(
          palette,
          icon: Icons.list_outlined,
          label: AppLanguage.tr(
              'Exam Details & Attempts', 'परीक्षा विवरण र प्रयासहरू'),
          onTap: () => context.push('/exam/${widget.setId}'),
        ),
        const SizedBox(height: 10),
        _secondaryAction(
          palette,
          icon: Icons.grid_view_outlined,
          label: AppLanguage.tr(
              'Practice Other Exams', 'अन्य परीक्षा अभ्यास'),
          onTap: () {
            TabsScreen.tabIndex.value = 1;
            context.go('/');
          },
        ),
        const SizedBox(height: 16),
        Text(
          AppLanguage.tr('Negative marking: 0.25 per wrong answer',
              'नकारात्मक अंक: गलत उत्तरमा ०.२५'),
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
      ],
    );
  }

  Widget _statCard(ExpoPalette palette, _Stat s) {
    // ~3 per row (flexBasis 30%).
    final width =
        (MediaQuery.of(context).size.width - 32 - 20) / 3;
    return Container(
      width: width,
      padding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          Icon(s.icon, size: 18, color: s.color),
          const SizedBox(height: 3),
          Text(s.value,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: palette.textSecondary)),
        ],
      ),
    );
  }

  Widget _secondaryAction(ExpoPalette palette,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: palette.textPrimary),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _Stat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Stat(this.icon, this.label, this.value, this.color);
}
