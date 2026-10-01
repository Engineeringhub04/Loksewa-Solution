import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import 'admin_review_dialogs.dart' show adminContentTitle;

/// Admin → Purchase Request Control: every exam + content purchase request in
/// one list. Mirrors app/admin/purchase-details/index.tsx. Each request
/// carries its requester's profile (photo/name/email), fetched best-effort.
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
  final Map<String, dynamic>? profile;
  _Item(this.kind, this.record, [this.profile]);
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
    final raws = <_Item>[
      for (final r in results[0]) _Item('exam', r),
      for (final r in results[1]) _Item('content', r),
    ];
    // Requester profiles, best-effort (a missing profile never blocks the
    // list) — mirrors the per-uid fetchUserProfile calls.
    final profiles = await Future.wait(raws.map((item) async {
      final uid = item.record['uid'];
      if (uid is! String || uid.isEmpty) return null;
      try {
        return await FirestoreRest.getDocument('users/$uid', idToken: token);
      } catch (_) {
        return null;
      }
    }));
    final items = <_Item>[
      for (var i = 0; i < raws.length; i++)
        _Item(raws[i].kind, raws[i].record, profiles[i]),
    ];
    items.sort((a, b) =>
        _date(b.record['submittedAt']).compareTo(_date(a.record['submittedAt'])));
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
                  'Purchase Request Control', 'खरिद अनुरोध नियन्त्रण')),
          Expanded(
            child: FutureBuilder<List<_Item>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  // Intro banner + track filter are part of the data view,
                  // so the whole body waits behind the loader together.
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
                    child: ElevatedButton(
                        onPressed: _refresh,
                        child: Text(
                            AppLanguage.tr('Retry', 'पुनः प्रयास'))),
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
                      _introBanner(),
                      const SizedBox(height: 12),
                      _trackSelector(),
                      const SizedBox(height: 12),
                      if (visible.isEmpty)
                        _emptyState()
                      else
                        for (var i = 0; i < visible.length; i++)
                          SyllabusEntrance(
                            delayMs: (i < 8 ? i : 8) * 60,
                            child: visible[i].kind == 'content'
                                ? _contentCard(visible[i])
                                : _examCard(visible[i]),
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

  Widget _introBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0x12 / 0xFF),
        border: Border.all(
            color: AppColors.navy.withValues(alpha: 0x30 / 0xFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined,
              color: AppColors.navy, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLanguage.tr(
                  'Review and manage individual exam purchase requests.',
                  'Individual exam purchase requests समीक्षा र व्यवस्थापन गर्नुहोस्।'),
              style:
                  const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackSelector() {
    final tracks = [
      (
        'all',
        AppLanguage.tr('All', 'सबै'),
        Icons.layers_outlined,
      ),
      (
        'exam',
        AppLanguage.tr('Exam Details', 'परीक्षा विवरण'),
        Icons.description_outlined,
      ),
      (
        'content',
        AppLanguage.tr('Content Details', 'सामग्री विवरण'),
        Icons.description_outlined,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tracks.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _trackItem(tracks[i])),
          ],
        ],
      ),
    );
  }

  Widget _trackItem((String, String, IconData) track) {
    final active = _track == track.$1;
    return GestureDetector(
      onTap: () => setState(() => _track = track.$1),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(track.$3,
                size: 15,
                color: active ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(track.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active ? FontWeight.bold : FontWeight.w600,
                      color: active ? Colors.white : Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final isContent = _track == 'content';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_outlined,
              size: 32, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            isContent
                ? AppLanguage.tr('No content purchase requests yet.',
                    'अहिलेसम्म सामग्री खरिद अनुरोध छैन।')
                : AppLanguage.tr('No exam purchase requests yet.',
                    'अहिलेसम्म exam purchase request छैन।'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _avatar(_Item item, Color fallbackTint) {
    final photoUrl = item.profile?['photoURL'] as String?;
    if (photoUrl?.isNotEmpty == true) {
      return CircleAvatar(
          radius: 24, backgroundImage: NetworkImage(photoUrl!));
    }
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fallbackTint.withValues(alpha: 0x15 / 0xFF),
      ),
      child: Icon(Icons.person, size: 20, color: fallbackTint),
    );
  }

  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0x18 / 0xFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 12, color: color),
          const SizedBox(width: 4),
          Text(_statusLabel(status),
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _examCard(_Item item) {
    final r = item.record;
    final status = '${r['status'] ?? 'pending'}';
    final name =
        '${item.profile?['name'] ?? r['userName'] ?? '—'}';
    final email =
        '${item.profile?['email'] ?? r['userEmail'] ?? '—'}';

    return GestureDetector(
      onTap: () =>
          context.push('/admin/exam-purchases/${r['id'] ?? ''}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(item, AppColors.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['examTitle'] ?? '—'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 19, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                      '${r['courseName'] ?? '—'} · ${r['subcourseName'] ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                _statusPill(status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'Rs. ${r['amount'] ?? '—'} · ${_fmtDate(r['submittedAt'])}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _contentCard(_Item item) {
    final r = item.record;
    final status = '${r['status'] ?? 'pending'}';
    final name =
        '${item.profile?['name'] ?? r['userName'] ?? '—'}';
    var title = adminContentTitle(r);
    if (title.isEmpty) {
      title =
          AppLanguage.tr('Content Purchase', 'सामग्री खरिद');
    }

    return GestureDetector(
      onTap: () =>
          context.push('/admin/content-purchases/${r['id'] ?? ''}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(item, Colors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      Text(
                          '${r['contentType'] ?? '—'} · ${r['courseId'] ?? '—'} · ${r['subcourseId'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 19, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    'Rs. ${r['amount'] ?? '—'} · ${_fmtDate(r['submittedAt'])}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                _statusPill(status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
