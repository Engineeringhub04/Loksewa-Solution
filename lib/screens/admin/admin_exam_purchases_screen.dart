import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Admin → exam purchase review queue. Mirrors
/// app/admin/exam-purchases/index.tsx. Collection: app_exam_purchases.
/// Statuses: pending (New), active (Approved), rejected.
class AdminExamPurchasesScreen extends StatefulWidget {
  const AdminExamPurchasesScreen({super.key});

  @override
  State<AdminExamPurchasesScreen> createState() =>
      _AdminExamPurchasesScreenState();
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
    docs.sort(
        (a, b) => _date(b['submittedAt']).compareTo(_date(a['submittedAt'])));
    return docs;
  }

  static DateTime _date(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _refresh() => setState(() => _future = _load());

  static Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return AppLanguage.tr('Approved', 'स्वीकृत');
      case 'rejected':
        return AppLanguage.tr('Rejected', 'अस्वीकृत');
      default:
        return AppLanguage.tr('New', 'नयाँ');
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.schedule;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr(
                  'Exam Purchase Review', 'Exam Purchase समीक्षा')),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading Subscription...',
                        'सदस्यता लोड हुँदैछ...'),
                    hint: AppLanguage.tr('Fetching your purchase history',
                        'खरिद इतिहास ल्याउँदै'),
                  );
                }
                if (snap.hasError) {
                  if (snap.error is _Denied) {
                    return Center(
                        child: Text(AppLanguage.tr(
                            'Access denied', 'पहुँच अस्वीकृत')));
                  }
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppLanguage.tr(
                            'Could not load purchase requests.',
                            'खरिद अनुरोधहरू लोड गर्न सकिएन।')),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _refresh,
                          child: Text(
                              AppLanguage.tr('Retry', 'पुनः प्रयास')),
                        ),
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
                return RefreshIndicator.adaptive(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(AppLanguage.tr('All', 'सबै'), 'all',
                              const Color(0xFF2563EB), null),
                          _chip(AppLanguage.tr('New', 'नयाँ'), 'pending',
                              Colors.orange, pendingCount),
                          _chip(AppLanguage.tr('Approved', 'स्वीकृत'),
                              'active', Colors.green, null),
                          _chip(AppLanguage.tr('Rejected', 'अस्वीकृत'),
                              'rejected', Colors.red, null),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        _emptyState()
                      else
                        for (var i = 0; i < filtered.length; i++)
                          SyllabusEntrance(
                            delayMs: (i < 8 ? i : 8) * 60,
                            child: _card(filtered[i]),
                          ),
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

  Widget _chip(String label, String value, Color color, int? count) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1.5),
          color: active ? color : color.withValues(alpha: 0x12 / 0xFF),
        ),
        child: Text(
          count != null ? '$label ($count)' : label,
          style: TextStyle(
            color: active ? Colors.white : color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.receipt_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            AppLanguage.tr('No exam purchase requests yet.',
                'अहिलेसम्म exam purchase request छैन।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final color = _statusColor(status);
    final who = '${r['userName'] ?? r['userEmail'] ?? r['uid'] ?? '—'}';

    return GestureDetector(
      onTap: () => context.push('/admin/exam-purchases/${r['id'] ?? ''}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0x17 / 0xFF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_statusIcon(status), size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['examTitle'] ?? '—'}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(
                    '${r['courseName'] ?? '—'} · ${r['subcourseName'] ?? '—'} · Rs. ${r['amount'] ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0x17 / 0xFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right,
                    size: 16, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
