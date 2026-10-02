import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Exam ranking — mirrors app/exam/[setId]/ranking.tsx.
///
/// Fixed dark-blue palette (like React — deliberately not theme-aware),
/// podium for the top 3 (order 2nd, 1st, 3rd), a "Your Position" card, and
/// the rest of the list. Locked until the exam window closes (fairness —
/// anyone could otherwise see answers early). Best score per user, ties
/// broken by faster time.
class ExamRankingScreen extends StatefulWidget {
  final String setId;
  const ExamRankingScreen({super.key, required this.setId});

  @override
  State<ExamRankingScreen> createState() => _ExamRankingScreenState();
}

class _ExamRankingScreenState extends State<ExamRankingScreen> {
  List<RankingRow> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _lockedMessage;

  static const _navy = Color(0xFF0F172A);
  static const _blue = Color(0xFF1E3A8A);
  static const _gold = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _lockedMessage = null;
    });
    try {
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      if (!areResultsUnlocked(set, DateTime.now())) {
        final unlock = resultsUnlockAt(set, DateTime.now());
        final k = unlock.toUtc().add(const Duration(hours: 5, minutes: 45));
        if (!mounted) return;
        setState(() {
          _loading = false;
          _lockedMessage = AppLanguage.tr(
              'Ranking unlocks after the exam window closes (${k.hour}:${k.minute.toString().padLeft(2, '0')}).',
              'परीक्षा समय सकिएपछि र्याङ्किङ खुल्नेछ।');
        });
        return;
      }
      final rows = await fetchExamRanking(widget.setId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load the ranking.', 'र्याङ्किङ लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  String _time(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          SubpageHeader(
            title: AppLanguage.tr('Ranking', 'र्याङ्किङ'),
            actions: [
              IconButton(
                tooltip: AppLanguage.tr('Refresh', 'रिफ्रेश'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const PreloadingWidget(
                    tinted: false,
                    label: 'Loading Ranking...',
                  )
                : _lockedMessage != null
                    ? _lockedBody()
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
                        : _rows.isEmpty
                            ? Center(
                                child: Text(AppLanguage.tr(
                                    'No rankings yet. Be the first!',
                                    'अहिलेसम्म र्याङ्किङ छैन।')))
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: _rankingBody(),
                              ),
          ),
        ],
      ),
    );
  }

  Widget _lockedBody() {
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
                color: _blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  size: 32, color: _blue),
            ),
            const SizedBox(height: 16),
            Text(_lockedMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: _navy)),
          ],
        ),
      ),
    );
  }

  Widget _rankingBody() {
    final uid = AuthService.currentUser?.uid ?? '';
    final myIndex = _rows.indexWhere((r) => r.uid == uid);
    final podium = _rows.take(3).toList();
    final rest = _rows.skip(3).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (podium.isNotEmpty) _podium(podium),
        if (myIndex >= 0) _myPositionCard(myIndex, _rows[myIndex]),
        if (rest.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(AppLanguage.tr('All Rankings', 'सबै र्याङ्किङ'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _navy)),
          ),
          ...List.generate(rest.length, (i) => _rowCard(i + 3, rest[i])),
        ],
      ],
    );
  }

  /// Podium — order 2nd, 1st, 3rd like React.
  Widget _podium(List<RankingRow> podium) {
    Widget place(int rank, RankingRow row, double height, Color medal) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: medal, width: 3),
              ),
              child: Center(
                child: Text(
                  row.name.isNotEmpty
                      ? row.name.trim()[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _navy),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: _navy)),
            Text('${row.score}%',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: medal,
                    fontSize: 14)),
            const SizedBox(height: 6),
            Container(
              height: height,
              decoration: BoxDecoration(
                color: rank == 0 ? _gold : _blue.withValues(alpha: 0.75),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
              ),
              child: Center(
                child: Text('${rank + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    final second = podium.length > 1 ? podium[1] : null;
    final first = podium[0];
    final third = podium.length > 2 ? podium[2] : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _blue],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(AppLanguage.tr('Top Performers', 'उत्कृष्ट प्रदर्शनकर्ता'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (second != null)
                place(1, second, 90, const Color(0xFFC0C0C0))
              else
                const Expanded(child: SizedBox()),
              place(0, first, 120, _gold),
              if (third != null)
                place(2, third, 70, const Color(0xFFCD7F32))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _myPositionCard(int index, RankingRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLanguage.tr('Your Position', 'तपाईंको स्थान'),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
                Text(row.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ],
            ),
          ),
          Text('${row.score}%',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ],
      ),
    );
  }

  Widget _rowCard(int index, RankingRow row) {
    final uid = AuthService.currentUser?.uid ?? '';
    final isMe = row.uid == uid;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isMe ? const Color(0xFFFFFBEB) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isMe
            ? const BorderSide(color: _gold)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: SizedBox(
          width: 32,
          child: Center(
            child: Text('${index + 1}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _navy)),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(row.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: _navy)),
            ),
            if (row.isPro)
              const Icon(Icons.verified, size: 16, color: _blue),
          ],
        ),
        subtitle: Text(
            '${AppLanguage.tr('Time', 'समय')}: ${_time(row.timeTakenSeconds)}',
            style: const TextStyle(color: Color(0xFF64748B))),
        trailing: Text('${row.score}%',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: _navy)),
      ),
    );
  }
}
