import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Daily test answer review — mirrors app/daily-test/[modelId]/review.tsx.
///
/// No entrance animations (perf on itel-class devices).
class DailyReviewScreen extends StatefulWidget {
  final String modelId;

  const DailyReviewScreen({super.key, required this.modelId});

  @override
  State<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

String _fmtNum(double v) {
  if (v == v.roundToDouble()) return '${v.toInt()}';
  var s = v.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

class _DailyReviewScreenState extends State<DailyReviewScreen> {
  DailyTestModel? _model;
  List<int>? _answers;
  int _timeTaken = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.go('/login');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final qp = GoRouterState.of(context).uri.queryParameters;
      List<int>? answers;
      int timeTaken = 0;
      final rawAnswers = qp['answers'];
      if (rawAnswers != null && rawAnswers.isNotEmpty) {
        try {
          final parsed = jsonDecode(rawAnswers);
          if (parsed is List) {
            answers = parsed.map((a) => (a as num?)?.toInt() ?? -1).toList();
          }
        } catch (_) {}
      }
      timeTaken = int.tryParse(qp['timeTaken'] ?? '') ?? 0;
      if (answers == null) {
        final saved = await fetchDailyTestResultForModel(uid, widget.modelId);
        if (saved != null) {
          answers = saved.answers;
          timeTaken = saved.timeTakenSeconds;
        }
      }
      final profile = await fetchUserProfile(uid);
      final subcourseId = profile?.subcourseId ?? '';
      DailyTestModel? model;
      if (subcourseId.isNotEmpty) {
        final models = await fetchDailyTestModels(subcourseId);
        for (final m in models) {
          if (m.id == widget.modelId) {
            model = m;
            break;
          }
        }
      }
      model ??= await fetchDailyTestModel(widget.modelId);
      if (!mounted) return;
      if (model == null || answers == null) {
        setState(() {
          _loading = false;
          _error = 'Could not load this review.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _model = model;
        _answers = answers;
        _timeTaken = timeTaken;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load the review. ${_cleanErr('$e')}';
      });
    }
  }

  /// Strips raw JSON/API dumps from an error so the UI never shows them.
  String _cleanErr(String raw) {
    var msg = raw.replaceFirst('Exception: ', '');
    final jsonStart = msg.indexOf('{');
    if (jsonStart >= 0) msg = msg.substring(0, jsonStart).trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160).trim()}…';
    return msg.isEmpty ? 'Please try again.' : msg;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            const SubpageHeader(title: 'Review Answers'),
            Expanded(child: _body(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _model == null || _answers == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error ?? 'Could not load this review.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
        ),
      );
    }
    final model = _model!;
    final answers = _answers!;
    final score =
        scoreDailyTest(model, model.questions, answers);
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final border =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE5E7EB);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final passColor = score.passed
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: model.questions.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _statsCard(model, score, surface, border, secondary,
              passColor, isDark);
        }
        final qi = i - 1;
        final q = model.questions[qi];
        final chosen = qi < answers.length ? answers[qi] : -1;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _questionCard(
              qi, q, chosen, surface, border, secondary, isDark),
        );
      },
    );
  }

  Widget _statsCard(
      DailyTestModel model,
      DailyScore score,
      Color surface,
      Color border,
      Color secondary,
      Color passColor,
      bool isDark) {
    final negLabel = model.negativeMarking
        ? 'Negative marking −${(model.negativeMarkPercent * 100).round()}%'
        : 'No negative marking';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR ATTEMPT',
              style: TextStyle(
                  color: secondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Text(model.displayName,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 78),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: passColor, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text('${score.percent}%',
                        style: TextStyle(
                            color: passColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(score.passed ? 'PASSED' : 'FAILED',
                        style: TextStyle(
                            color: passColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _miniStat('Correct', '${score.correct}',
                        const Color(0xFF16A34A), secondary),
                    _miniStat('Wrong', '${score.incorrect}',
                        const Color(0xFFDC2626), secondary),
                    _miniStat('Skipped', '${score.skipped}',
                        secondary, secondary),
                    _miniStat('Time',
                        formatDailyTestDuration(_timeTaken),
                        const Color(0xFF2563EB), secondary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Net marks ${_fmtNum(score.netMarks)} / ${_fmtNum(score.totalMarks)} · Accuracy ${score.accuracy}% · $negLabel',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
      String label, String value, Color color, Color secondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: secondary)),
      ],
    );
  }

  Widget _questionCard(int qi, DailyTestQuestion q, int chosen,
      Color surface, Color border, Color secondary, bool isDark) {
    final skipped = chosen < 0;
    final correct = !skipped && chosen == q.correctIndex;
    final Color verdictColor;
    final String verdictLabel;
    if (skipped) {
      verdictColor = const Color(0xFFD97706);
      verdictLabel = 'Skipped';
    } else if (correct) {
      verdictColor = const Color(0xFF16A34A);
      verdictLabel = 'Correct';
    } else {
      verdictColor = const Color(0xFFDC2626);
      verdictLabel = 'Wrong';
    }
    const green = Color(0xFF16A34A);
    const red = Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Q${qi + 1}',
                    style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: verdictColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(verdictLabel,
                    style: TextStyle(
                        color: verdictColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (q.category.isNotEmpty)
                Text(q.category,
                    style:
                        TextStyle(fontSize: 11, color: secondary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(q.question,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, height: 1.45)),
          const SizedBox(height: 10),
          ...List.generate(q.options.length, (oi) {
            final isCorrect = oi == q.correctIndex;
            final isChosen = !skipped && oi == chosen;
            Color? bg;
            Color? borderColor;
            if (isCorrect) {
              bg = green.withValues(alpha: 0.08);
              borderColor = green;
            } else if (isChosen) {
              bg = red.withValues(alpha: 0.08);
              borderColor = red;
            }
            String? tag;
            if (isCorrect && isChosen) {
              tag = 'Your answer · Correct';
            } else if (isCorrect) {
              tag = 'Correct answer';
            } else if (isChosen) {
              tag = 'Your answer';
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(
                    color: borderColor ??
                        (isDark
                            ? const Color(0xFF26314B)
                            : const Color(0xFFE5E7EB))),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${String.fromCharCode(65 + oi)}. ',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: borderColor ?? secondary)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(q.options[oi],
                            style: const TextStyle(
                                fontSize: 13, height: 1.4)),
                        if (tag != null) ...[
                          const SizedBox(height: 4),
                          Text(tag,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isCorrect ? green : red)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (skipped)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'You did not answer this question, so it scored zero.',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFFD97706)),
              ),
            ),
          if (q.explanation.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB)
                    .withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('EXPLANATION',
                      style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text(q.explanation,
                      style: const TextStyle(
                          fontSize: 13, height: 1.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
