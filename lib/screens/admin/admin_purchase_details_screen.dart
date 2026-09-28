import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Admin → Purchase Request Control: every exam + content purchase request in
/// one list. Mirrors app/admin/purchase-details/index.tsx.
class AdminPurchaseDetailsScreen extends StatefulWidget {
  const AdminPurchaseDetailsScreen({super.key});

  @override
  State<AdminPurchaseDetailsScreen> createState() =>
      _AdminPurchaseDetailsScreenState();
}

class _Denied implements Exception {}

class _Item {
  final String kind; // 'exam' | 'content'
  final Map<String, dynamic> record;
  _Item(this.kind, this.record);
}

class _AdminPurchaseDetailsScreenState
    extends State<AdminPurchaseDetailsScreen> {
  String _track = 'all'; // all | exam | content
  Future<List<_Item>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Item>> _load() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    final results = await Future.wait([
      FirestoreRest.listDocuments('app_exam_purchases',
          idToken: token, pageSize: 300),
      FirestoreRest.listDocuments('app_content_purchases',
          idToken: token, pageSize: 300),
    ]);
    final items = <_Item>[
      for (final r in results[0]) _Item('exam', r),
      for (final r in results[1]) _Item('content', r),
    ];
    items.sort(
        (a, b) => _date(b.record['submittedAt']).compareTo(_date(a.record['submittedAt'])));
    return items;
  }

  static DateTime _date(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _fmtDate(dynamic v) {
    final d = _date(v);
    if (d.millisecondsSinceEpoch == 0) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Request Control')),
      body: FutureBuilder<List<_Item>>(
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
          final items = snap.data ?? [];
          final visible = _track == 'all'
              ? items
              : items.where((i) => i.kind == _track).toList();
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.06),
                    border: Border.all(
                        color: AppColors.navy.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.navy),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Review every purchase request. Approving or rejecting keeps the request in the list as an audit trail.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'exam', label: Text('Exam')),
                    ButtonSegment(value: 'content', label: Text('Content')),
                  ],
                  selected: {_track},
                  onSelectionChanged: (s) =>
                      setState(() => _track = s.first),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No purchase requests.')),
                  ),
                for (final item in visible) _card(item),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(_Item item) {
    final r = item.record;
    final status = '${r['status'] ?? 'pending'}';
    final Color color = status == 'active'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : Colors.orange;
    final label = status == 'active'
        ? 'Approved'
        : status == 'rejected'
            ? 'Rejected'
            : 'New';
    final title = item.kind == 'exam'
        ? '${r['examTitle'] ?? '—'}'
        : '${r['contentTitleNe'] ?? r['contentTitle'] ?? '—'}';
    final route = item.kind == 'exam'
        ? '/admin/exam-purchases/${r['id'] ?? ''}'
        : '/admin/content-purchases/${r['id'] ?? ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r['userName'] ?? '—'}'),
            Text(
              item.kind == 'exam'
                  ? '${r['courseName'] ?? '—'} · ${r['subcourseName'] ?? '—'}'
                  : '${r['contentType'] ?? '—'} · ${r['courseId'] ?? '—'}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Rs. ${r['amount'] ?? '—'} · ${_fmtDate(r['submittedAt'])}',
                    style: const TextStyle(fontSize: 12)),
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
        onTap: () => context.push(route),
      ),
    );
  }
}
