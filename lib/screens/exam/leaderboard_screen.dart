import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';

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
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
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
      appBar: AppBar(
        title: const Text('Leaderboard'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
    );
  }

  Widget _podium() {
    // Display order 2nd, 1st, 3rd.
    final order = [_rows.length > 1 ? _rows[1] : null,
        _rows.isNotEmpty ? _rows[0] : null,
        _rows.length > 2 ? _rows[2] : null];
    final medals = ['🥈', '🥇', '🥉'];
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
                    color: Colors.blue.shade700.withOpacity(0.12),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10)),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(medals[i],
                      style: const TextStyle(fontSize: 22)),
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
