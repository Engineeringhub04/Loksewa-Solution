import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Review Answers — mirrors app/exam/[setId]/review.tsx same-to-same.
///
/// Every question with all options colour-coded against the pick: the right
/// option always green with a "Correct" tag, the wrong pick red with "Wrong",
/// the explanation underneath. Lazy list, NO entering animations (low-end
/// perf: the page transition IS the animation). Same unlock gate as summary.
class ExamReviewScreen extends StatefulWidget {
  final String setId;
  final String? answers; // JSON array, -1 = skipped
  final String? attemptLabel;
  final String? attemptDate;

  const ExamReviewScreen({
    super.key,
    required this.setId,
    this.answers,
    this.attemptLabel,
    this.attemptDate,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  ExamSet? _set;
  List<int> _answers = const [];
  bool _loading = true;
  String? _error;

  static const _correct = Color(0xFF16A34A);
  static const _wrong = Color(0xFFDC2626);

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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      List<int> answers = _parseAnswers(widget.answers);
      if (answers.isEmpty) {
        // Fallback: latest attempt.
        final uid = AuthService.currentUser?.uid ?? '';
        final attempts = uid.isEmpty
            ? <ExamAttempt>[]
            : await fetchAttemptsForSet(uid, widget.setId);
        if (attempts.isNotEmpty) {
          attempts.sort(
              (a, b) => b.attemptNumber.compareTo(a.attemptNumber));
          answers = attempts.first.answers;
        }
      }
      final padded = List<int>.filled(set.questions.length, -1);
      for (var i = 0; i < padded.length && i < answers.length; i++) {
        padded[i] = answers[i];
      }
      if (!mounted) return;
      setState(() {
        _set = set;
        _answers = padded;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Answers unavailable', 'उत्तरहरू उपलब्ध छैनन्');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Review Answers', 'उत्तर समीक्षा')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr(
                        'Loading Answers…', 'उत्तरहरू लोड हुँदै…'),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => context.pop(),
                              child: Text(AppLanguage.tr(
                                  'Go back', 'फर्कनुहोस्')),
                            ),
                          ],
                        ),
                      )
                    : _locked()
                        ? _lockedBody(palette)
                        : _answers.isEmpty
                            ? Center(
                                child: Text(AppLanguage.tr(
                                    'No attempt found for this exam.',
                                    'यस परीक्षाको प्रयास भेटिएन।')))
                            : _list(palette),
          ),
        ],
      ),
    );
  }

  bool _locked() =>
      _set != null && !areResultsUnlocked(_set!, DateTime.now());

  Widget _lockedBody(ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline,
                  size: 32, color: palette.primary),
            ),
            const SizedBox(height: 16),
            Text(
              AppLanguage.tr(
                  'Answers are locked', 'उत्तरहरू लक छन्'),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              AppLanguage.tr(
                  'Answer review unlocks after the exam window closes, so nobody gains an advantage by finishing early.',
                  'परीक्षा समय सकिएपछि उत्तर समीक्षा खुल्नेछ।'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.pop(),
              child:
                  Text(AppLanguage.tr('Go back', 'फर्कनुहोस्')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(ExpoPalette palette) {
    final set = _set!;
    final breakdown =
        scoreExamAttempt(set.questions, _answers, set.passPercent);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      // Keep the first paint light.
      itemCount: set.questions.length + 1,
      itemBuilder: (c, i) {
        if (i == 0) return _listHeader(palette, set, breakdown);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _questionCard(
              palette, set.questions[i - 1], _answers[i - 1], i),
        );
      },
    );
  }

  Widget _listHeader(
      ExpoPalette palette, ExamSet set, ScoreBreakdown b) {
    final stats = [
      _MiniStat(AppLanguage.tr('Total', 'जम्मा'), '${set.questions.length}',
          palette.textPrimary),
      _MiniStat(AppLanguage.tr('Correct', 'सही'), '${b.correct}', _correct),
      _MiniStat(AppLanguage.tr('Incorrect', 'गलत'), '${b.incorrect}', _wrong),
      _MiniStat(AppLanguage.tr('Skipped', 'छोडियो'), '${b.skipped}',
          palette.textSecondary),
      _MiniStat(AppLanguage.tr('Score', 'स्कोर'), '${b.percent}%',
          palette.primary),
    ];
    final sub = [
      if (widget.attemptLabel != null &&
          widget.attemptLabel!.isNotEmpty)
        widget.attemptLabel!,
      if (widget.attemptDate != null && widget.attemptDate!.isNotEmpty)
        widget.attemptDate!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(set.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        fontSize: 12, color: palette.textSecondary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 10,
                children: stats
                    .map((s) => Container(
                          constraints:
                              const BoxConstraints(minWidth: 54),
                          child: Column(
                            children: [
                              Text(s.value,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: s.color)),
                              const SizedBox(height: 2),
                              Text(s.label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: palette.textSecondary)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLanguage.tr(
              'Question Answer Details', 'प्रश्न उत्तर विवरण'),
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _questionCard(
      ExpoPalette palette, ExamQuestion q, int chosen, int number) {
    final skipped = chosen < 0;
    final gotItRight = chosen == q.correctIndex;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$number',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: palette.primary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(q.question,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 22 / 14)),
              ),
              Icon(
                skipped
                    ? Icons.remove_circle_outline
                    : gotItRight
                        ? Icons.check_circle
                        : Icons.cancel,
                size: 20,
                color: skipped
                    ? palette.textSecondary
                    : gotItRight
                        ? _correct
                        : _wrong,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(q.options.length, (oi) {
            final isCorrectOption = oi == q.correctIndex;
            final isUserPick = oi == chosen;
            // The right option is always highlighted green, even when the
            // user skipped — that is the point of a review.
            final Color? tone =
                isCorrectOption ? _correct : isUserPick ? _wrong : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: tone != null
                    ? tone.withValues(alpha: 0.07)
                    : palette.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: tone ?? palette.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone ?? Colors.transparent,
                      border: Border.all(
                          color: tone ?? palette.border, width: 1.5),
                    ),
                    child: Center(
                      child: Text(String.fromCharCode(65 + oi),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: tone != null
                                  ? Colors.white
                                  : palette.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(q.options[oi],
                          style: const TextStyle(fontSize: 13))),
                  if (isCorrectOption)
                    _tag(AppLanguage.tr('Correct', 'सही'), _correct),
                  if (isUserPick && !isCorrectOption)
                    _tag(AppLanguage.tr('Wrong', 'गलत'), _wrong),
                ],
              ),
            );
          }),
          if (skipped)
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: palette.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    AppLanguage.tr('You skipped this question',
                        'तपाईंले यो प्रश्न छोड्नुभयो'),
                    style: TextStyle(
                        fontSize: 12, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          if (q.explanation.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.info.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 15, color: palette.info),
                      const SizedBox(width: 6),
                      Text(
                        AppLanguage.tr('Explanation', 'व्याख्या'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: palette.info),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(q.explanation,
                      style: TextStyle(
                          fontSize: 13,
                          height: 20 / 13,
                          color: palette.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _MiniStat {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);
}
