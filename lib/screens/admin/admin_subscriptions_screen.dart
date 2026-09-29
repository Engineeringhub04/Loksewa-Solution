import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Admin desk — every subscription request, newest first. A request is NEVER
/// removed after review; it just changes tag. Mirrors
/// app/admin/subscriptions/index.tsx. Collection: app_subscriptions.
class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  State<AdminSubscriptionsScreen> createState() =>
      _AdminSubscriptionsScreenState();
}

class _Denied implements Exception {}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen> {
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
    final docs = await FirestoreRest.listDocuments('app_subscriptions',
        idToken: token, pageSize: 300);
    docs.sort((a, b) =>
        _date(b['submittedAt']).compareTo(_date(a['submittedAt'])));
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
    final d = _date(v);
    if (d.millisecondsSinceEpoch == 0) return '';
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
      body: Column(
        children: [
          const SubpageHeader(title: 'Subscription Review'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const PreloadingWidget(
              tinted: false,
              label: 'Loading Subscriptions...',
            );
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
          final pending =
              all.where((r) => r['status'] == 'pending').length;
          final active =
              all.where((r) => r['status'] == 'active').length;
          final rejected =
              all.where((r) => r['status'] == 'rejected').length;
          final filtered = _filter == 'all'
              ? all
              : all.where((r) => r['status'] == _filter).toList();
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _stat('${all.length}', 'Total', Colors.blue),
                    const SizedBox(width: 8),
                    _stat('$pending', 'Awaiting', Colors.orange),
                    const SizedBox(width: 8),
                    _stat('$active', 'Approved', Colors.green),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('All (${all.length})', 'all'),
                    _chip('New ($pending)', 'pending'),
                    _chip('Approved ($active)', 'active'),
                    _chip('Rejected ($rejected)', 'rejected'),
                  ],
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No subscription requests.')),
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

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final Color color = status == 'active'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : status == 'expired'
                ? Colors.grey
                : Colors.orange;
    final label = status == 'active'
        ? 'Approved'
        : status == 'rejected'
            ? 'Rejected'
            : status == 'expired'
                ? 'Expired'
                : 'New';
    final who = '${r['userName'] ?? r['userEmail'] ?? r['uid'] ?? '—'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(who.trim().isEmpty ? '?' : who.trim()[0].toUpperCase(),
              style:
                  TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(who,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${r['planName'] ?? '—'} · Rs. ${r['amount'] ?? '—'} · ${'${r['method'] ?? ''}'.toUpperCase()}'),
            const SizedBox(height: 4),
            Row(
              children: [
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
                const SizedBox(width: 8),
                Text(_fmtDate(r['submittedAt']),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
        isThreeLine: false,
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            context.push('/admin/subscriptions/${r['id'] ?? ''}'),
      ),
    );
  }
}
