import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Daily test summary — mirrors app/daily-test/[modelId]/summary.tsx.
///
/// Answers arrive via query params; the score is RECOMPUTED from the model
/// with scoreDailyTest — params are never trusted for marks.
class DailySummaryScreen extends StatefulWidget {
  final String modelId;

  const DailySummaryScreen({super.key, required this.modelId});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _Verdict {
  final String title;
  final String message;
  final Color color;
  final IconData icon;

  const _Verdict(this.title, this.message, this.color, this.icon);
}

_Verdict _verdictFor(int percent, bool passed) {
  if (percent >= 85) {
    return const _Verdict('Outstanding!', 'A near-perfect warm-up. Come back tomorrow for the next one.', Color(0xFF16A34A), Icons.emoji_events);
  }
  // A11: React's exact verdict messages.
  if (percent >= 60) {
    return const _Verdict('Well done!', 'A solid run. Review your answers to lock in the few you missed.', Color(0xFF2563EB), Icons.workspace_premium);
  }
  if (passed) {
    return const _Verdict('Passed — just', 'You cleared the pass mark. Review the explanations and tomorrow gets easier.', Color(0xFFD97706), Icons.check_circle);
  }
  return const _Verdict('Keep going', 'Every daily test teaches something. Review your answers and you will climb fast.', Color(0xFFDC2626), Icons.refresh);
}

String _fmtNum(double v) {
  if (v == v.roundToDouble()) return '${v.toInt()}';
  var s = v.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
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

      // Fall back to the saved result when params are absent (deep links).
      // C2/C3: the saved-result fetch and the profile fetch are independent —
      // run them together. (The model-list fetch still depends on the
      // profile's subcourseId, so it stays sequential.)
      final loaded = await Future.wait([
        answers == null
            ? fetchDailyTestResultForModel(uid, widget.modelId)
            : Future<DailyTestResult?>.value(null),
        fetchUserProfile(uid),
      ]);
      final saved = loaded[0] as DailyTestResult?;
      final profile = loaded[1] as UserProfile?;
      if (saved != null) {
        answers = saved.answers;
        timeTaken = saved.timeTakenSeconds;
      }

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
          _error = 'Could not load this result.';
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
        _error = 'Couldn\'t load the result. ${_cleanErr('$e')}';
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

  void _goReview() {
    final uri = Uri(
      path: '/daily-test/${widget.modelId}/review',
      queryParameters: {
        'answers': jsonEncode(_answers),
        'timeTaken': '$_timeTaken',
      },
    );
    context.push(uri.toString());
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/daily-test');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA),
      body: SafeArea(
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
        child: Column(
          children: [
            SubpageHeader(title: 'Your Result', onBackPress: _goBack),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Could not load this result.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _goBack,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: const Text('Back to Daily Test',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    final model = _model!;
    final answers = _answers!;
    // Recomputed from the model — never trusts the params for marks.
    final score =
        scoreDailyTest(model, model.questions, answers);
    final verdict = _verdictFor(score.percent, score.passed);
    final passPercent = model.passPercent > 0 ? model.passPercent : 40;
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final border =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE5E7EB);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Score card.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  model.displayName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8),
                ),
                const SizedBox(height: 16),
                _ProgressRing(
                    percent: score.percent,
                    color: verdict.color,
                    correct: score.correct,
                    total: model.questions.length),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: verdict.color.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  // B16: React's verdict pill carries a trophy when passed,
                  // a refresh icon when failed.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          score.passed
                              ? Icons.emoji_events
                              : Icons.refresh,
                          size: 15,
                          color: verdict.color),
                      const SizedBox(width: 6),
                      Text(
                        '${score.passed ? 'PASSED' : 'FAILED'} · pass mark $passPercent%',
                        style: TextStyle(
                            color: verdict.color,
                            fontSize: 13,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(verdict.icon,
                        size: 20, color: verdict.color),
                    const SizedBox(width: 8),
                    Text(verdict.title,
                        style: TextStyle(
                            color: verdict.color,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(verdict.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: secondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Stat cards (2-col).
          Row(
            children: [
              Expanded(
                  child: _statCard('Correct', '${score.correct}',
                      Icons.check_circle, const Color(0xFF16A34A),
                      surface, border, secondary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Incorrect', '${score.incorrect}',
                      Icons.cancel, const Color(0xFFDC2626),
                      surface, border, secondary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _statCard('Skipped', '${score.skipped}',
                      Icons.remove_circle, secondary,
                      surface, border, secondary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Time taken',
                      formatDailyTestDuration(_timeTaken),
                      Icons.access_time, const Color(0xFF2563EB),
                      surface, border, secondary)),
            ],
          ),
          const SizedBox(height: 14),
          // Marks breakdown.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MARKS BREAKDOWN',
                    style: TextStyle(
                        color: secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
                const SizedBox(height: 12),
                _markRow('Marks earned', '+${_fmtNum(score.marksEarned)}',
                    const Color(0xFF16A34A), secondary),
                if (model.negativeMarking)
                  _markRow(
                      'Penalty (−${(model.negativeMarkPercent * 100).round()}% per wrong answer)',
                      '−${_fmtNum(score.marksLost)}',
                      const Color(0xFFDC2626),
                      secondary),
                _markRow(
                    'Net marks',
                    '${_fmtNum(score.netMarks)} / ${_fmtNum(score.totalMarks)}',
                    null,
                    secondary,
                    bold: true),
                _markRow('Accuracy', '${score.accuracy}%', null,
                    secondary,
                    bold: true),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _goReview,
              icon: const Icon(Icons.list_alt,
                  size: 18, color: Colors.white),
              label: const Text('Review Answers',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            // B17: React's "Back to Daily Test" carries the home icon.
            child: OutlinedButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.home_outlined,
                  size: 18, color: Color(0xFF2563EB)),
              label: const Text('Back to Daily Test',
                  style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(
                    color: Color(0xFF2563EB), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon,
      Color color, Color surface, Color border, Color secondary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 12, color: secondary)),
        ],
      ),
    );
  }

  Widget _markRow(String label, String value, Color? valueColor,
      Color secondary,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: secondary,
                      fontWeight:
                          bold ? FontWeight.w600 : FontWeight.w400))),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: valueColor)),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final int percent;
  final Color color;
  final int correct;
  final int total;

  const _ProgressRing(
      {required this.percent,
      required this.color,
      required this.correct,
      required this.total});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: CircularProgressIndicator(
              value: percent.clamp(0, 100) / 100,
              strokeWidth: 13,
              backgroundColor: isDark
                  ? const Color(0xFF26314B)
                  : const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          // B15: the "{correct} / {total}" caption under the percent.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$percent%',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: color)),
              Text('$correct / $total',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondary)),
            ],
          ),
        ],
      ),
    );
  }
}
