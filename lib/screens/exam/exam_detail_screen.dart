import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Exam set detail — mirrors app/exam/[setId]/index.tsx.
///
/// Meta card + Re-Attempt + Your Ranking (lock-gated with a toast until the
/// exam window closes) + full attempts history — tapping an attempt opens the
/// review with THAT attempt's answers. An unlock notice shows while locked.
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
  bool _unlocked = false;

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
        _unlocked = areResultsUnlocked(set, DateTime.now());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load exam details.', 'परीक्षा विवरण लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  void _reAttempt() {
    if (_set?.contentType == 'pdf') {
      final uri = _set!.pdfUrl ?? '';
      context.push(
        '/pdf/${Uri.encodeComponent(_set!.id)}'
        '?uri=${Uri.encodeComponent(uri)}'
        '&title=${Uri.encodeComponent(_set!.title)}',
      );
      return;
    }
    context.push('/exam/${widget.setId}/quiz');
  }

  void _goRanking() {
    final set = _set!;
    if (!areResultsUnlocked(set, DateTime.now())) {
      final unlock = resultsUnlockAt(set, DateTime.now());
      final k = unlock.toUtc().add(const Duration(hours: 5, minutes: 45));
      showToast(
        context,
        AppLanguage.tr(
            'Ranking unlocks after the exam window closes (${k.hour}:${k.minute.toString().padLeft(2, '0')}).',
            'परीक्षा समय सकिएपछि र्याङ्किङ खुल्नेछ।'),
        ToastVariant.warning,
      );
      return;
    }
    context.push('/exam/${widget.setId}/ranking');
  }

  void _reviewAttempt(ExamAttempt attempt) {
    final set = _set!;
    if (!areResultsUnlocked(set, DateTime.now())) {
      showToast(
        context,
        AppLanguage.tr(
            'Answers unlock after the exam window closes.',
            'परीक्षा समय सकिएपछि उत्तरहरू खुल्नेछन्।'),
        ToastVariant.warning,
      );
      return;
    }
    final answersParam = attempt.answers.map((a) => '$a').join(',');
    final date = attempt.createdAt;
    final dateStr = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    context.push(
      '/exam/${set.id}/review'
      '?answers=${Uri.encodeComponent(answersParam)}'
      '&label=${Uri.encodeComponent('Attempt ${attempt.attemptNumber}')}'
      '&date=${Uri.encodeComponent(dateStr)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: AppLanguage.tr('Exam Details', 'परीक्षा विवरण')),
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
                    : _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final set = _set!;
    final best = _attempts.isEmpty
        ? null
        : _attempts.reduce((a, b) => a.score >= b.score ? a : b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(set.title,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (set.isPro)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('PRO',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.help_outline,
                        '${set.totalQuestions} ${AppLanguage.tr('Questions', 'प्रश्न')}'),
                    _chip(Icons.timer_outlined,
                        '${set.durationMinutes} ${AppLanguage.tr('min', 'मिनेट')}'),
                    _chip(Icons.flag_outlined,
                        '${AppLanguage.tr('Pass', 'उत्तीर्ण')} ${set.passPercent}%'),
                    _chip(Icons.speed_outlined, set.difficulty.toUpperCase()),
                  ],
                ),
                if (best != null) ...[
                  const SizedBox(height: 12),
                  Text(
                      '${AppLanguage.tr('Best score', 'उत्कृष्ट स्कोर')}: '
                      '${best.score}% (${best.correct}/${best.totalQuestions} '
                      '${AppLanguage.tr('correct', 'सही')})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!_unlocked) _unlockNotice(),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _reAttempt,
          icon: const Icon(Icons.play_arrow),
          label: Text(set.contentType == 'pdf'
              ? AppLanguage.tr('Open PDF', 'PDF खोल्नुहोस्')
              : AppLanguage.tr('Re-Attempt', 'पुनः प्रयास')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _goRanking,
          icon: Icon(_unlocked
              ? Icons.leaderboard_outlined
              : Icons.lock_outline),
          label: Text(AppLanguage.tr('Your Ranking', 'तपाईंको र्याङ्किङ')),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 20),
        Text(AppLanguage.tr('Your Attempts', 'तपाईंका प्रयासहरू'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_attempts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(AppLanguage.tr(
                  'No attempts yet. Take the exam to see your history here.',
                  'अहिलेसम्म प्रयास छैन।')),
            ),
          )
        else
          ..._attempts.map(_attemptRow),
      ],
    );
  }

  Widget _unlockNotice() {
    final set = _set!;
    final unlock = resultsUnlockAt(set, DateTime.now());
    final k = unlock.toUtc().add(const Duration(hours: 5, minutes: 45));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline,
              size: 20, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLanguage.tr(
                  'Results unlock after the exam window closes (${k.hour}:${k.minute.toString().padLeft(2, '0')}).',
                  'परीक्षा समय सकिएपछि नतिजा खुल्नेछ।'),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1E40AF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attemptRow(ExamAttempt a) {
    final date = a.createdAt;
    final dateStr = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final passColor =
        a.passed ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _reviewAttempt(a),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: passColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('${a.score}%',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: passColor)),
          ),
        ),
        title: Text(
            '${AppLanguage.tr('Attempt', 'प्रयास')} ${a.attemptNumber}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${a.correct}/${a.totalQuestions} ${AppLanguage.tr('correct', 'सही')}'
            ' • ${_timeLabel(a.timeTakenSeconds)}'
            '${dateStr.isNotEmpty ? ' • $dateStr' : ''}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: passColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                  a.passed
                      ? AppLanguage.tr('Pass', 'उत्तीर्ण')
                      : AppLanguage.tr('Fail', 'अनुत्तीर्ण'),
                  style: TextStyle(
                      color: passColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  String _timeLabel(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
      );
}
