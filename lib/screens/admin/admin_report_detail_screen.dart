import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';

/// Admin → review one report and answer the reporter. Mirrors
/// app/admin/report-history/[id].tsx. Collection: app_report_history.
/// Actions: resolved / reviewed / dismissed, each optionally with a message
/// appended to adminResponses.
class AdminReportDetailScreen extends StatefulWidget {
  final String id;
  const AdminReportDetailScreen({super.key, required this.id});

  @override
  State<AdminReportDetailScreen> createState() =>
      _AdminReportDetailScreenState();
}

class _Denied implements Exception {}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  Future<Map<String, dynamic>?>? _future;
  final _adminMessage = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _adminMessage.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    final record = await FirestoreRest.getDocument(
        'app_report_history/${widget.id}',
        idToken: token);
    if (record == null) return null;
    try {
      final reporterId = record['reporterId'];
      if (reporterId is String && reporterId.isNotEmpty) {
        record['_reporterProfile'] = await FirestoreRest.getDocument(
            'users/$reporterId',
            idToken: token);
      }
    } catch (_) {}
    return record;
  }

  void _refresh() => setState(() => _future = _load());

  static String _fmtDateTime(dynamic v) {
    DateTime? d;
    if (v is DateTime) d = v;
    if (v is String) d = DateTime.tryParse(v);
    if (d == null) return '—';
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _review(
      Map<String, dynamic> record, String status, String actionLabel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$actionLabel report'),
        content: Text('Mark this report as $actionLabel?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(actionLabel)),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final token = await AuthService.getValidIdToken();
      final message = _adminMessage.text.trim();
      final existing =
          (record['adminResponses'] as List?)?.toList() ?? [];
      final next = List<Map<String, dynamic>>.from(
          existing.map((e) => Map<String, dynamic>.from(e as Map)));
      if (message.isNotEmpty) {
        next.add({
          'id': 'response-${DateTime.now().millisecondsSinceEpoch}',
          'message': message,
          'status': status,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
      await FirestoreRest.setDocument(
        'app_report_history/${widget.id}',
        {
          'status': status,
          'adminMessage': message.isNotEmpty
              ? message
              : (record['adminMessage'] as String?),
          'adminResponses': next,
          'reviewedAt': FirestoreRest.serverTimestamp(),
        },
        idToken: token,
        merge: true,
      );
      _adminMessage.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Report marked as $actionLabel.')));
        _refresh();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Something went wrong.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Report Details'),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
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
          final record = snap.data;
          if (record == null) {
            return const Center(child: Text('This report was not found.'));
          }
          return _body(record);
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _body(Map<String, dynamic> record) {
    final status = '${record['status'] ?? 'pending'}';
    final Color color = status == 'pending'
        ? Colors.orange
        : status == 'resolved'
            ? Colors.green
            : status == 'dismissed'
                ? Colors.red
                : Colors.blue;
    final label = status == 'pending'
        ? 'New'
        : status[0].toUpperCase() + status.substring(1);
    final reporter =
        record['_reporterProfile'] as Map<String, dynamic>?;
    final responses =
        (record['adminResponses'] as List?) ?? [];

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Answer box FIRST — answering is the whole reason this page exists.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${record['contextLabel'] ?? record['source'] ?? ''}',
                            style:
                                const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _adminMessage,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Response to reporter (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _review(record, 'resolved', 'Resolve'),
                      child: const Text('Resolve'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _review(record, 'reviewed', 'Mark reviewed'),
                      child: const Text('Mark reviewed'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _review(record, 'dismissed', 'Dismiss'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reported content',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${record['targetTitle'] ?? record['targetType'] ?? '—'}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${record['targetAuthorName'] ?? ''} · ${_fmtDateTime(record['createdAt'])}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text('${record['targetPreview'] ?? '—'}'),
                    const Divider(height: 24),
                    _info('Target type', '${record['targetType'] ?? '—'}'),
                    _info('Report ID', '${record['targetId'] ?? '—'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Report message',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _info('Reason', '${record['reason'] ?? '—'}'),
                    _info('Details', '${record['description'] ?? '—'}'),
                    _info('Submitted on',
                        _fmtDateTime(record['createdAt'])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: (reporter?['photoURL'] as String?)?.isNotEmpty == true
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(
                            reporter!['photoURL'] as String))
                    : const CircleAvatar(child: Icon(Icons.person)),
                title: Text(
                    '${reporter?['name'] ?? record['reporterName'] ?? '—'}',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${reporter?['email'] ?? record['reporterEmail'] ?? '—'}\n'
                    '${record['reporterCourseId'] ?? '—'} · ${record['reporterSubcourseId'] ?? '—'}'),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 12),
            if (responses.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Response history',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      for (final resp in responses)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${(resp as Map)['status'] ?? ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  Text(
                                      _fmtDateTime(resp['createdAt']),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey)),
                                ],
                              ),
                              Text('${resp['message'] ?? ''}'),
                              const Divider(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No admin response yet.',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
        if (_busy)
          Container(
            color: Colors.black45,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
