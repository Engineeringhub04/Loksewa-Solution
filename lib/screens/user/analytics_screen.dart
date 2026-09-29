import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Analytics — mirrors app/analytics.tsx (simplified).
///
/// Reads the private per-subcourse documents at `users/{uid}/app_analytics`.
/// The Expo screen has 15 chart-heavy sections; without chart packages this
/// screen shows the same data faithfully as stat tiles, daily effort bars and
/// a per-day breakdown: hero (points, weighted %, streak), range switcher
/// (7/30/90 days), daily points bars, and day cards with QOTD / exam / daily
/// test / practice splits. Day bucket fields mirror analyticsSnapshot.ts:
/// p=points, pc=percent, s=foreground seconds, a=activities, qa/qc=QOTD
/// attempts/correct, ea/ep=exam attempts/avg %, da/dp=daily-test attempts/avg
/// %, ta/tc=practice attempted/correct.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _subcourseId;
  int _range = 30;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    final idToken = await AuthService.getValidIdToken();
    return FirestoreRest.listDocuments('users/$uid/app_analytics',
        idToken: idToken);
  }

  num _num(Map m, String k) {
    final v = m[k];
    return v is num ? v : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Performance Analytics'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const PreloadingWidget(
              tinted: false,
              label: 'Loading Analytics...',
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load analytics:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final docs = snap.data ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No analytics yet.\nPractice, take tests and exams — your progress will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          _subcourseId ??= (docs.first['subcourseId'] ?? '').toString();
          final doc = docs.firstWhere(
            (d) => (d['subcourseId'] ?? '').toString() == _subcourseId,
            orElse: () => docs.first,
          );
          final days = doc['days'];
          final Map<String, dynamic> dayMap =
              days is Map ? Map<String, dynamic>.from(days) : {};
          final sortedKeys = dayMap.keys.toList()..sort();
          final keys = sortedKeys.length > _range
              ? sortedKeys.sublist(sortedKeys.length - _range)
              : sortedKeys;

          final streak = doc['streak'];
          final Map streakMap =
              streak is Map ? streak : <String, dynamic>{};
          final maxP = keys.fold<double>(
              1,
              (m, k) =>
                  _num(dayMap[k] is Map ? dayMap[k] : {}, 'p')
                          .toDouble() >
                      m
                      ? _num(dayMap[k] is Map ? dayMap[k] : {}, 'p')
                          .toDouble()
                      : m);

          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (docs.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DropdownButtonFormField<String>(
                      value: _subcourseId,
                      decoration: const InputDecoration(
                        labelText: 'Subcourse',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final d in docs)
                          DropdownMenuItem(
                            value: (d['subcourseId'] ?? '').toString(),
                            child: Text(
                                (d['subcourseId'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _subcourseId = v),
                    ),
                  ),
                // Hero stats.
                Row(
                  children: [
                    _statTile('Points',
                        '${_num(doc, 'points').toInt()}', Icons.star),
                    const SizedBox(width: 8),
                    _statTile('Score',
                        '${_num(doc, 'percent').toStringAsFixed(1)}%',
                        Icons.percent),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statTile('Day streak',
                        '${_num(streakMap, 'current').toInt()}',
                        Icons.local_fire_department),
                    const SizedBox(width: 8),
                    _statTile('Best streak',
                        '${_num(streakMap, 'best').toInt()}',
                        Icons.emoji_events),
                  ],
                ),
                const SizedBox(height: 12),
                // Range switcher.
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7D')),
                    ButtonSegment(value: 30, label: Text('30D')),
                    ButtonSegment(value: 90, label: Text('90D')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) =>
                      setState(() => _range = s.first),
                ),
                const SizedBox(height: 12),
                const Text('Daily effort',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final k in keys)
                          _dayBar(k,
                              _num(dayMap[k] is Map ? dayMap[k] : {}, 'p').toDouble(),
                              maxP),
                        if (keys.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No activity in this range.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Day breakdown',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy)),
                const SizedBox(height: 8),
                for (final k in keys.reversed)
                  _dayCard(k,
                      dayMap[k] is Map ? Map.from(dayMap[k]) : {}),
              ],
            ),
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        color: AppColors.navy,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayBar(String dayKey, double points, double maxP) {
    final label = dayKey.length >= 10 ? dayKey.substring(5) : dayKey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 52,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxP <= 0 ? 0 : (points / maxP).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accent),
              ),
            ),
          ),
          SizedBox(
              width: 44,
              child: Text('${points.toInt()}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _dayCard(String dayKey, Map bucket) {
    num v(String k) => _num(bucket, k);
    final secs = v('s').toInt();
    final timeLabel =
        secs >= 3600 ? '${(secs / 3600).toStringAsFixed(1)}h' : '${(secs / 60).toStringAsFixed(0)}m';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(dayKey,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${v('p').toInt()} pts · ${v('pc').toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.navy)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _miniChip('⏱ $timeLabel'),
                _miniChip('⚡ ${v('a').toInt()} activities'),
                if (v('qa') > 0)
                  _miniChip('QOTD ${v('qc').toInt()}/${v('qa').toInt()}'),
                if (v('ea') > 0)
                  _miniChip(
                      'Exam ${v('ea').toInt()} · ${v('ep').toStringAsFixed(0)}%'),
                if (v('da') > 0)
                  _miniChip(
                      'Daily test ${v('da').toInt()} · ${v('dp').toStringAsFixed(0)}%'),
                if (v('ta') > 0)
                  _miniChip(
                      'Practice ${v('tc').toInt()}/${v('ta').toInt()}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
