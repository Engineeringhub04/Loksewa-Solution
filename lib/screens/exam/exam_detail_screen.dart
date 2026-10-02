import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Exam set detail — mirrors app/exam/[setId]/index.tsx same-to-same.
///
/// Meta card (title + subcourse + pills), the Your Ranking / Re-Attempt
/// action row, Attempts History with tone-tinted attempt cards (tapping one
/// opens the review with THAT attempt's answers), and the warning notice
/// while the exam window is still closed. Ranking + per-attempt review stay
/// lock-gated with an info toast.
class ExamDetailScreen extends StatefulWidget {
  final String setId;
  const ExamDetailScreen({super.key, required this.setId});

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  ExamSet? _set;
  List<ExamAttempt> _attempts = const [];
  bool _loading = true;
  String? _error;

  static const _pass = Color(0xFF16A34A);
  static const _fail = Color(0xFFDC2626);

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
      final uid = AuthService.currentUser?.uid ?? '';
      final attempts = uid.isEmpty
          ? <ExamAttempt>[]
          : await fetchAttemptsForSet(uid, widget.setId);
      attempts.sort((a, b) => b.attemptNumber.compareTo(a.attemptNumber));
      if (!mounted) return;
      setState(() {
        _set = set;
        _attempts = attempts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load exam details.', 'परीक्षा विवरण लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  bool get _unlocked =>
      _set != null && areResultsUnlocked(_set!, DateTime.now());

  String _unlockTime() {
    final unlock = resultsUnlockAt(_set!, DateTime.now());
    final k = unlock.toUtc().add(const Duration(hours: 5, minutes: 45));
    final h12 = k.hour % 12 == 0 ? 12 : k.hour % 12;
    final mm = k.minute.toString().padLeft(2, '0');
    final ampm = k.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ampm';
  }

  /// Gate shared by ranking + per-attempt review (React: requireUnlocked).
  void _requireUnlocked(VoidCallback action) {
    if (_unlocked) {
      action();
      return;
    }
    showToast(
      context,
      AppLanguage.tr(
          'Unlocks at ${_unlockTime()}.', 'अहिले उपलब्ध छैन।'),
      ToastVariant.info,
    );
  }

  void _goRanking() {
    _requireUnlocked(
        () => context.push('/exam/${widget.setId}/ranking'));
  }

  void _reviewAttempt(ExamAttempt attempt) {
    _requireUnlocked(() {
      final date = attempt.createdAt;
      final dateStr = date == null
          ? ''
          : '${date.day}/${date.month}/${date.year} · ${_hm(date)}';
      context.push(
        '/exam/${widget.setId}/review'
        '?answers=${Uri.encodeComponent(jsonEncode(attempt.answers))}'
        '&attemptLabel=${Uri.encodeComponent('Attempt ${attempt.attemptNumber}')}'
        '&attemptDate=${Uri.encodeComponent(dateStr)}',
      );
    });
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

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Exam Details', 'परीक्षा विवरण')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading Exam Details…',
                        'परीक्षा विवरण लोड हुँदै…'),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(AppLanguage.tr(
                                'Exam not found', 'परीक्षा भेटिएन')),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _load,
                              child: Text(AppLanguage.tr(
                                  'Retry', 'पुनः प्रयास')),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _body(palette),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _body(ExpoPalette palette) {
    final set = _set!;
    final courseInfo = ProfileStore.instance.courseInfo;
    final subLabel = courseInfo?.subcourseName ??
        courseInfo?.courseName ??
        '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Exam details card.
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
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (subLabel.isNotEmpty)
                Text(subLabel,
                    style: TextStyle(
                        fontSize: 13, color: palette.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metaPill(palette, Icons.help_outline,
                      '${set.totalQuestions} ${AppLanguage.tr('Questions', 'प्रश्नहरू')}'),
                  _metaPill(palette, Icons.access_time_outlined,
                      '${set.durationMinutes} ${AppLanguage.tr('min', 'मिनेट')}'),
                  _metaPill(palette, Icons.emoji_events_outlined,
                      '${AppLanguage.tr('Pass', 'उत्तीर्ण')} ${set.passPercent}%'),
                  _metaPill(
                      palette,
                      Icons.bar_chart_outlined,
                      set.difficulty.isEmpty
                          ? ''
                          : set.difficulty[0].toUpperCase() +
                              set.difficulty.substring(1)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Actions row.
        Row(
          children: [
            Expanded(
              child: _secondaryBtn(
                palette,
                icon: _unlocked ? Icons.emoji_events_outlined : Icons.lock_outline,
                iconColor: const Color(0xFFD97706),
                label: AppLanguage.tr('Your Ranking', 'तपाईंको र्याङ्किङ'),
                onTap: _goRanking,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () =>
                    context.push('/exam/${widget.setId}/quiz'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Re-Attempt',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(AppLanguage.tr('Attempts History', 'प्रयास इतिहास'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_attempts.isEmpty)
          _emptyState(palette)
        else
          ..._attempts.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _attemptCard(palette, a),
              )),
        if (!_unlocked) ...[
          const SizedBox(height: 4),
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
                    size: 16, color: palette.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLanguage.tr(
                        'Answer review and rankings unlock once the exam window closes.',
                        'परीक्षा समय सकिएपछि उत्तर समीक्षा र र्याङ्किङ खुल्नेछ।'),
                    style: TextStyle(
                        fontSize: 12, color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _metaPill(ExpoPalette palette, IconData icon, String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary)),
        ],
      ),
    );
  }

  Widget _secondaryBtn(ExpoPalette palette,
      {required IconData icon,
      required Color iconColor,
      required String label,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ExpoPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined,
              size: 44, color: palette.textDisabled),
          const SizedBox(height: 12),
          Text(AppLanguage.tr('No attempts yet', 'अहिलेसम्म प्रयास छैन'),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            AppLanguage.tr(
                'Your attempts will appear here with their scores once you finish this exam.',
                'परीक्षा सकिएपछि तपाईंका प्रयासहरू स्कोरसहित यहाँ देखिनेछन्।'),
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _attemptCard(ExpoPalette palette, ExamAttempt a) {
    final tone = a.passed ? _pass : _fail;
    final date = a.createdAt;
    final dateLabel =
        date == null ? '' : '${date.day}/${date.month}/${date.year} · ${_hm(date)}';
    return GestureDetector(
      onTap: () => _reviewAttempt(a),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: tone.withValues(alpha: 0.33), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              child: Center(
                child: Text('${a.attemptNumber}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${AppLanguage.tr('Attempt', 'प्रयास')} ${a.attemptNumber}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    '$dateLabel${dateLabel.isNotEmpty ? ' · ' : ''}${_duration(a.timeTakenSeconds)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: palette.textSecondary),
                  ),
                  Text(
                    '${a.correct} ${AppLanguage.tr('correct', 'सही')} · '
                    '${a.incorrect} ${AppLanguage.tr('wrong', 'गलत')} · '
                    '${a.skipped} ${AppLanguage.tr('skipped', 'छोडियो')}',
                    style: TextStyle(
                        fontSize: 12, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${a.score}%',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: tone)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(
                      a.passed
                          ? AppLanguage.tr('PASS', 'उत्तीर्ण')
                          : AppLanguage.tr('FAIL', 'अनुत्तीर्ण'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 16, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}
