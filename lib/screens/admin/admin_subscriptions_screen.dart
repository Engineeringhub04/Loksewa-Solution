import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/preloading.dart';
import '../../widgets/stagger_entrance.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';

/// Admin desk — every subscription request, newest first. A request is NEVER
/// removed from this list after review; it just changes tag (New → Approved
/// / Rejected), so the admin always has a full audit trail here. Mirrors
/// app/admin/subscriptions/index.tsx. Collection: app_subscriptions.
///
/// Layout hierarchy mirrors React: hero band with the numbers the admin came
/// for (total / awaiting / approved), the shared filter track with counts,
/// then request cards that lead with WHO is asking (tone spine on the left
/// edge reads the status at a glance).
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

  static Color _tone(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'expired':
        return Colors.grey;
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
      case 'expired':
        return AppLanguage.tr('Expired', 'म्याद सकिएको');
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
      case 'expired':
        return Icons.schedule;
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr(
                  'Subscription Requests', 'सदस्यता अनुरोधहरू')),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  // The hero counts fetched records, so it stays behind the
                  // loader gate with everything else.
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr(
                        'Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
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
                  return _errorState();
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
                      _heroBand(all.length, pending, active),
                      const SizedBox(height: 12),
                      _filterTrack(all.length, pending, active, rejected),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        _emptyState()
                      else
                        for (var i = 0; i < filtered.length; i++)
                          StaggerEntrance(
                            delayMs: (i < 8 ? i : 8) * 55,
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

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(AppLanguage.tr(
              'Could not load subscription requests.',
              'सदस्यता अनुरोधहरू लोड गर्न सकिएन।')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _refresh,
            child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास')),
          ),
        ],
      ),
    );
  }

  Widget _heroBand(int total, int pending, int active) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF93C5FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0x33 / 0xFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr('Subscription Requests',
                          'सदस्यता अनुरोधहरू'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLanguage.tr(
                          'Approve or reject premium subscription payments.',
                          'प्रिमियम सदस्यता भुक्तानी स्वीकृत वा अस्वीकृत गर्नुहोस्।'),
                      style: TextStyle(
                          color:
                              Colors.white.withValues(alpha: 0xCC / 0xFF),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statTile('$total',
                  AppLanguage.tr('Total', 'जम्मा'), Icons.layers_outlined),
              const SizedBox(width: 8),
              _statTile('$pending',
                  AppLanguage.tr('Awaiting', 'प्रतीक्षामा'), Icons.schedule,
                  tint: Colors.orange),
              const SizedBox(width: 8),
              _statTile('$active',
                  AppLanguage.tr('Approved', 'स्वीकृत'), Icons.check_circle,
                  tint: Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label, IconData icon,
      {Color? tint}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0x26 / 0xFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 18, color: tint ?? Colors.white),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0xCC / 0xFF),
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _filterTrack(int total, int pending, int active, int rejected) {
    final items = [
      _FilterItem('all', AppLanguage.tr('Total', 'जम्मा'), total,
          const Color(0xFF2563EB)),
      _FilterItem('pending', AppLanguage.tr('New', 'नयाँ'), pending,
          Colors.orange),
      _FilterItem('active', AppLanguage.tr('Approved', 'स्वीकृत'), active,
          Colors.green),
      _FilterItem('rejected', AppLanguage.tr('Rejected', 'अस्वीकृत'),
          rejected, Colors.red),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _filterChip(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(_FilterItem item) {
    final active = _filter == item.value;
    return GestureDetector(
      onTap: () => setState(() => _filter = item.value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active
              ? item.color
              : item.color.withValues(alpha: 0x14 / 0xFF),
          border: Border.all(
              color: item.color.withValues(alpha: 0x66 / 0xFF), width: 1.2),
        ),
        child: Text(
          '${item.label} (${item.count})',
          style: TextStyle(
            color: active ? Colors.white : item.color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.done_all_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            AppLanguage.tr('No requests in this filter yet.',
                'यो फिल्टरमा कुनै अनुरोध छैन।'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_filter != 'all') ...[
            const SizedBox(height: 6),
            Text(
              AppLanguage.tr(
                  'Approve or reject premium subscription payments.',
                  'प्रिमियम सदस्यता भुक्तानी स्वीकृत वा अस्वीकृत गर्नुहोस्।'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final tone = _tone(status);
    final who = '${r['userName'] ?? r['userEmail'] ?? r['uid'] ?? '—'}';
    final initial =
        who.trim().isEmpty ? '?' : who.trim()[0].toUpperCase();
    final date = _fmtDate(r['submittedAt']);

    return GestureDetector(
      onTap: () => context.push('/admin/subscriptions/${r['id'] ?? ''}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Tone spine: status reads at a glance down the left edge.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(color: tone),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone.withValues(alpha: 0x14 / 0xFF),
                        border: Border.all(
                            color: tone.withValues(alpha: 0x33 / 0xFF),
                            width: 0.5),
                      ),
                      child: Text(initial,
                          style: TextStyle(
                              color: tone,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(
                            '${r['planName'] ?? '—'} · Rs. ${r['amount'] ?? '—'} · ${'${r['method'] ?? ''}'.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              StatusPill(
                                  label: _statusLabel(status),
                                  color: tone,
                                  icon: _statusIcon(status)),
                              if (date.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(date,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterItem {
  final String value;
  final String label;
  final int count;
  final Color color;
  const _FilterItem(this.value, this.label, this.count, this.color);
}
