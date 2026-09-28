import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Admin → exam purchase review queue. Mirrors app/admin/exam-purchases/index.tsx.
/// Collection: app_exam_purchases. Statuses: pending (New), active (Approved), rejected.
class AdminExamPurchasesScreen extends StatefulWidget {
  const AdminExamPurchasesScreen({super.key});

  @override
  State<AdminExamPurchasesScreen> createState() => _AdminExamPurchasesScreenState();
}

class _Denied implements Exception {}

class _AdminExamPurchasesScreenState extends State<AdminExamPurchasesScreen> {
  String _filter = 'all'; // all | pending | active | rejected
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
    final docs = await FirestoreRest.listDocuments('app_exam_purchases',
        idToken: token, pageSize: 300);
    docs.sort((a, b) =>
        _date(b['submittedAt']).compareTo(_date(a['submittedAt'])));
    return docs;
  }

  static DateTime _date(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Exam Purchase Review'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load purchase requests.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          final records = snap.data ?? [];
          final pendingCount =
              records.where((r) => r['status'] == 'pending').length;
          final filtered = _filter == 'all'
              ? records
              : records.where((r) => r['status'] == _filter).toList();
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('All', 'all', null),
                    _chip('New ($pendingCount)', 'pending', Colors.orange),
                    _chip('Approved', 'active', Colors.green),
                    _chip('Rejected', 'rejected', Colors.red),
                  ],
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No exam purchase requests.')),
                  ),
                for (final r in filtered) _card(r),
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

  Widget _chip(String label, String value, Color? color) {
    final active = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: (color ?? AppColors.navy).withValues(alpha: 0.2),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final Color color = status == 'active'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : Colors.orange;
    final label =
        status == 'active' ? 'Approved' : status == 'rejected' ? 'Rejected' : 'New';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            status == 'active'
                ? Icons.check_circle
                : status == 'rejected'
                    ? Icons.cancel
                    : Icons.schedule,
            color: color,
          ),
        ),
        title: Text('${r['examTitle'] ?? '—'}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${r['userName'] ?? r['userEmail'] ?? r['uid'] ?? '—'}\n'
          '${r['courseName'] ?? '—'} · ${r['subcourseName'] ?? '—'} · Rs. ${r['amount'] ?? '—'}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
        onTap: () =>
            context.push('/admin/exam-purchases/${r['id'] ?? ''}'),
      ),
    );
  }
}
