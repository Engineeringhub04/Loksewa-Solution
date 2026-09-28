import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Admin → Report Details Control: every report from every user, newest first.
/// Mirrors app/admin/report-history/index.tsx. Collection: app_report_history.
/// Tracks: all | question | discussion (source != 'question').
class AdminReportHistoryScreen extends StatefulWidget {
  const AdminReportHistoryScreen({super.key});

  @override
  State<AdminReportHistoryScreen> createState() =>
      _AdminReportHistoryScreenState();
}

class _Denied implements Exception {}

class _AdminReportHistoryScreenState extends State<AdminReportHistoryScreen> {
  String _track = 'all'; // all | question | discussion
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    final docs = await FirestoreRest.listDocuments('app_report_history',
        idToken: token, pageSize: 300);
    docs.sort(
        (a, b) => _date(b['createdAt']).compareTo(_date(a['createdAt'])));
    return docs;
  }

  static DateTime _date(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _fmtDate(dynamic v) {
    final d = _date(v).toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Details Control')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (snap.error is _Denied) {
              return const Center(child: Text('Access denied'));
            }
            return Center(
              child: ElevatedButton(
                  onPressed: _refresh, child: const Text('Retry')),
            );
          }
          final all = snap.data ?? [];
          final records = _track == 'all'
              ? all
              : all.where((r) => _track == 'question'
                  ? r['source'] == 'question'
                  : r['source'] != 'question').toList();
          final pending =
              all.where((r) => r['status'] == 'pending').length;
          final resolved =
              all.where((r) => r['status'] == 'resolved').length;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _stat('${all.length}', 'All', Icons.layers_outlined,
                        Colors.blue),
                    const SizedBox(width: 8),
                    _stat('$pending', 'New', Icons.schedule_outlined,
                        Colors.orange),
                    const SizedBox(width: 8),
                    _stat('$resolved', 'Resolved',
                        Icons.check_circle_outline, Colors.green),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'question', label: Text('Question')),
                    ButtonSegment(
                        value: 'discussion', label: Text('Discussion')),
                  ],
                  selected: {_track},
                  onSelectionChanged: (s) =>
                      setState(() => _track = s.first),
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No reports.')),
                  ),
                for (final r in records) _card(r),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final isNew = status == 'pending';
    final Color color = isNew
        ? Colors.orange
        : status == 'resolved'
            ? Colors.green
            : status == 'dismissed'
                ? Colors.red
                : Colors.blue;
    final label = isNew
        ? 'New'
        : status[0].toUpperCase() + status.substring(1);
    final target = '${r['targetTitle'] ?? r['targetPreview'] ?? r['contextLabel'] ?? '—'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: isNew
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.orange, width: 1.2),
            )
          : null,
      child: ListTile(
        leading: (r['reporterPhoto'] as String?)?.isNotEmpty == true
            ? CircleAvatar(
                backgroundImage: NetworkImage(r['reporterPhoto'] as String))
            : const CircleAvatar(child: Icon(Icons.person)),
        title: Text('${r['reporterName'] ?? '—'}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r['reporterEmail'] ?? '—'}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(target,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtDate(r['createdAt']),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: false,
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            context.push('/admin/report-history/${r['id'] ?? ''}'),
      ),
    );
  }
}
