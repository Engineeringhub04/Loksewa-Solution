import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Main leaderboard — mirrors app/leaderboard.tsx.
/// Podium top 3 (pinned), "your standing" card, then the scrolling ranks.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<MainLeaderboardRow> _rows = const [];
  bool _loading = true;
  String? _error;

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
      final uid = AuthService.currentUser?.uid ?? '';
      final profile = uid.isEmpty ? null : await fetchUserProfile(uid);
      final subcourseId = profile?.subcourseId ?? '';
      if (uid.isEmpty || subcourseId.isEmpty) {
        throw Exception('Set up your course to see the leaderboard.');
      }
      final rows = await fetchMainLeaderboard(subcourseId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Never leak raw Firestore/API errors to the user. The only expected
      // throw here is the missing-course setup message; anything else gets a
      // generic friendly message.
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _error = msg == 'Set up your course to see the leaderboard.'
            ? msg
            : 'Couldn\'t load the leaderboard right now. Please try again.';
        _loading = false;
      });
    }
  }

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '0m';
  }

  String _formatPercent(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()}%'
        : '${rounded.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.currentUser?.uid ?? '';
    final myIndex = uid.isEmpty ? -1 : _rows.indexWhere((r) => r.uid == uid);
    final myRow = myIndex >= 0 ? _rows[myIndex] : null;
    final pointsToNext = myIndex > 0
        ? (_rows[myIndex - 1].points - _rows[myIndex].points)
            .clamp(0, 1 << 30)
        : null;

    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: 'Leaderboard', actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
          Expanded(
            child: _loading
          ? const PreloadingWidget(
            tinted: false,
            label: 'Loading Leaderboard...',
          )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _podium(),
                      const SizedBox(height: 12),
                      _myCard(myRow, myIndex, pointsToNext),
                      const SizedBox(height: 12),
                      const Text('Rankings',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_rows.length <= 3)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('No more rankings yet.'),
                          ),
                        ),
                      ...List.generate(_rows.length > 3 ? _rows.length - 3 : 0,
                          (i) {
                        final row = _rows[i + 3];
                        final isMe = row.uid == uid;
                        return Card(
                          color: isMe ? Colors.green.shade50 : null,
                          child: ListTile(
                            leading: CircleAvatar(
                                child: Text('${i + 4}')),
                            title: Row(
                              children: [
                                Expanded(child: Text(row.name)),
                                if (row.isPro)
                                  const Icon(Icons.verified,
                                      size: 16, color: Colors.blue),
                              ],
                            ),
                            subtitle: Text(
                                '${row.points} pts · ${_formatTime(row.usageSeconds)}'),
                            trailing: Text(
                                _formatPercent(row.percent),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _podium() {
    // Display order 2nd, 1st, 3rd.
    final order = [_rows.length > 1 ? _rows[1] : null,
        _rows.isNotEmpty ? _rows[0] : null,
        _rows.length > 2 ? _rows[2] : null];
    // Medal colors (no emojis in UI): gold / silver / bronze.
    const medalColors = [
      Color(0xFF9AA5B1), // silver — 2nd
      Color(0xFFF5B301), // gold — 1st
      Color(0xFFCD7F32), // bronze — 3rd
    ];
    const medalInk = [
      Color(0xFF3A4552),
      Color(0xFF5C4300),
      Color(0xFF5A3410),
    ];
    final heights = [110.0, 150.0, 90.0];
    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final row = order[i];
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (row != null) ...[
                  CircleAvatar(
                    radius: 22,
                    child: Text(row.name.isNotEmpty
                        ? row.name[0].toUpperCase()
                        : '?'),
                  ),
                  const SizedBox(height: 4),
                  Text(row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(_formatPercent(row.percent),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('${row.points} pts',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                ] else
                  const Text('Open spot',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                Container(
                  height: heights[i],
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10)),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: medalColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                          width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i == 0 ? 2 : i == 1 ? 1 : 3}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: medalInk[i])),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _myCard(
      MainLeaderboardRow? myRow, int myIndex, int? pointsToNext) {
    return Card(
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.green),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: myRow == null
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Not ranked yet',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Attempt some tests to appear on the leaderboard.'),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        child: Text('${myIndex + 1}'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Your standing',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            Text(myRow.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _miniStat(_formatPercent(myRow.percent), 'Percent'),
                      _miniStat('${myRow.points}', 'Points'),
                      _miniStat(_formatTime(myRow.usageSeconds),
                          'Study time'),
                    ],
                  ),
                  if (pointsToNext != null) ...[
                    const SizedBox(height: 8),
                    Text('$pointsToNext pts to reach #${myIndex}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.green)),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _miniStat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
