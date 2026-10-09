import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import 'admin_review_dialogs.dart' show adminContentTitle;

/// Admin → Purchase Request Control: every exam + content purchase request in
/// one list. Mirrors app/admin/purchase-details/index.tsx. Each request
/// carries its requester's profile (photo/name/email), fetched best-effort.
///
/// PREMIUM layout (same treatment as the v1.0.31 Subscription Requests
/// redesign): gradient stat hero (Total / Awaiting / Approved) with
/// divider-separated numbers, a segmented All / Exam / Content filter, then
/// modern request cards — gradient avatar ring, name + item line, status
/// pill + date, and a bold amount on the right edge.
///
/// Logic is untouched: same fetch (exam + content purchases, best-effort
/// profiles) + newest-first sort, same three tracks, same card tap routes,
/// same loading / denied / error / empty states.
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

  /// Status tone through the theme palette (lifted variants in dark mode),
  /// so pills / avatars / glows stay legible in both themes.
  Color _tone(String status) {
    final palette = ExpoPalette.of(context);
    switch (status) {
      case 'active':
        return palette.success;
      case 'rejected':
        return palette.danger;
      default:
        return palette.warning;
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
                  'Purchase Request Control', 'खरिद अनुरोध नियन्त्रण')),
          Expanded(
            child: FutureBuilder<List<_Item>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  // The hero counts fetched records, so it stays behind the
                  // loader gate with everything else.
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr(
                        'Loading purchases...', 'खरिदहरू लोड हुँदैछ...'),
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
                final items = snap.data ?? [];
                final pending = items
                    .where((i) => '${i.record['status'] ?? 'pending'}' == 'pending')
                    .length;
                final approved = items
                    .where((i) => '${i.record['status'] ?? ''}' == 'active')
                    .length;
                final exams =
                    items.where((i) => i.kind == 'exam').length;
                final contents =
                    items.where((i) => i.kind == 'content').length;
                final visible = _track == 'all'
                    ? items
                    : items.where((i) => i.kind == _track).toList();
                return RefreshIndicator.adaptive(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _heroBand(items.length, pending, approved),
                      const SizedBox(height: 12),
                      _filterTrack(
                          items.length, exams, contents),
                      const SizedBox(height: 12),
                      if (visible.isEmpty)
                        _emptyState()
                      else
                        for (var i = 0; i < visible.length; i++)
                          SyllabusEntrance(
                            delayMs: (i < 8 ? i : 8) * 60,
                            child: _card(visible[i]),
                          ),
                      // Breathing room so the last card clears the bottom.
                      const SizedBox(height: 8),
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
    final palette = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.danger.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.cloud_off_outlined,
                  size: 30, color: palette.danger),
            ),
            const SizedBox(height: 14),
            Text(
              AppLanguage.tr('Could not load purchase requests.',
                  'खरिद अनुरोधहरू लोड गर्न सकिएन।'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  color: palette.info,
                  borderRadius:
                      BorderRadius.circular(ExpoRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: palette.info.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(ExpoRadius.pill),
                  onTap: _refresh,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    child: Text(
                      AppLanguage.tr('Retry', 'पुनः प्रयास'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Premium stat hero: deep blue gradient, decorative glass circles, shield
  /// badge + title, then Total / Awaiting / Approved separated by hairline
  /// dividers instead of boxed tiles.
  Widget _heroBand(int total, int pending, int approved) {
    return SyllabusEntrance(
      delayMs: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ExpoRadius.lg),
          gradient: const LinearGradient(
            colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF60A5FA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ExpoRadius.lg),
          child: Stack(
            children: [
              Positioned(
                top: -56,
                right: -40,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                bottom: -70,
                left: -30,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.35)),
                          ),
                          child: const Icon(Icons.shield_outlined,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguage.tr('Purchase Request Control',
                                    'खरिद अनुरोध नियन्त्रण'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.2),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                AppLanguage.tr(
                                    'Review and manage exam and content purchase requests.',
                                    'परीक्षा र सामग्री खरिद अनुरोधहरू समीक्षा र व्यवस्थापन गर्नुहोस्।'),
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.82),
                                    fontSize: 13,
                                    height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                            child: _heroStat('$total',
                                AppLanguage.tr('Total', 'जम्मा'),
                                Icons.layers_outlined)),
                        _heroDivider(),
                        Expanded(
                            child: _heroStat('$pending',
                                AppLanguage.tr('Awaiting', 'प्रतीक्षामा'),
                                Icons.schedule_outlined)),
                        _heroDivider(),
                        Expanded(
                            child: _heroStat('$approved',
                                AppLanguage.tr('Approved', 'स्वीकृत'),
                                Icons.check_circle_outlined)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroDivider() {
    return Container(
      width: 1,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.25),
    );
  }

  Widget _heroStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon,
            size: 19, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 11,
                letterSpacing: 0.6)),
      ],
    );
  }

  /// Premium segmented filter control: one surface track, the active track
  /// fills with its tone colour + glow, the rest sit quiet.
  Widget _filterTrack(int total, int exams, int contents) {
    final palette = ExpoPalette.of(context);
    final items = [
      _FilterItem('all', AppLanguage.tr('All', 'सबै'), total,
          const Color(0xFF2563EB)),
      _FilterItem('exam', AppLanguage.tr('Exam', 'परीक्षा'), exams,
          palette.info),
      _FilterItem('content', AppLanguage.tr('Content', 'सामग्री'), contents,
          palette.success),
    ];
    return SyllabusEntrance(
      delayMs: 60,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final item in items) Expanded(child: _segment(item)),
          ],
        ),
      ),
    );
  }

  Widget _segment(_FilterItem item) {
    final selected = _track == item.value;
    final palette = ExpoPalette.of(context);
    return GestureDetector(
      onTap: () => setState(() => _track = item.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? item.color : Colors.transparent,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: item.color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          '${item.label} (${item.count})',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : palette.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final palette = ExpoPalette.of(context);
    final message = _track == 'content'
        ? AppLanguage.tr('No content purchase requests yet.',
            'अहिलेसम्म सामग्री खरिद अनुरोध छैन।')
        : _track == 'exam'
            ? AppLanguage.tr('No exam purchase requests yet.',
                'अहिलेसम्म परीक्षा खरिद अनुरोध छैन।')
            : AppLanguage.tr('No purchase requests yet.',
                'अहिलेसम्म कुनै खरिद अनुरोध छैन।');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.info.withValues(alpha: 0.1),
            ),
            child:
                Icon(Icons.done_all_outlined, size: 30, color: palette.info),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary),
          ),
        ],
      ),
    );
  }

  /// Modern request card: gradient avatar (photo when available) with the
  /// requester's initial, requester + item line, then a bottom row of status
  /// pill + date … and the amount standing bold on the right edge.
  Widget _card(_Item item) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = item.record;
    final status = '${r['status'] ?? 'pending'}';
    final tone = _tone(status);
    final photoUrl = (item.profile?['photoURL'] as String?) ?? '';
    final name =
        '${item.profile?['name'] ?? r['userName'] ?? r['userEmail'] ?? '—'}';
    final initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final String title;
    final String sub;
    if (item.kind == 'exam') {
      title = '${r['examTitle'] ?? '—'}';
      sub =
          '${r['courseName'] ?? '—'} · ${r['subcourseName'] ?? '—'}';
    } else {
      var t = adminContentTitle(r);
      if (t.isEmpty) {
        t = AppLanguage.tr('Content Purchase', 'सामग्री खरिद');
      }
      title = t;
      sub =
          '${r['contentType'] ?? '—'} · ${r['courseId'] ?? '—'} · ${r['subcourseId'] ?? '—'}';
    }
    final date = _fmtDate(r['submittedAt']);
    final amount = '${r['amount'] ?? '—'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ExpoRadius.lg),
          onTap: () => context.push(item.kind == 'content'
              ? '/admin/content-purchases/${r['id'] ?? ''}'
              : '/admin/exam-purchases/${r['id'] ?? ''}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _avatar(photoUrl, initial, tone),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: palette.textPrimary)),
                          const SizedBox(height: 3),
                          Text(
                            '$title · $sub',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: ExpoType.bodySmall,
                                color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 20, color: palette.textDisabled),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatusPill(
                        label: _statusLabel(status),
                        color: tone,
                        icon: _statusIcon(status)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 13,
                              color: palette.textDisabled),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(date,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: ExpoType.bodySmall,
                                    color: palette.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                    Text('Rs. $amount',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: palette.info)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(String photoUrl, String initial, Color tone) {
    if (photoUrl.isNotEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: tone.withValues(alpha: 0.4), width: 2),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: CircleAvatar(
            radius: 25, backgroundImage: NetworkImage(photoUrl)),
      );
    }
    final deep = Color.lerp(tone, Colors.black, 0.25) ?? tone;
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [tone, deep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(initial,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold)),
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
