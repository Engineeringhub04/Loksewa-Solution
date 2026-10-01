import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';

/// Admin desk — every subscription request, newest first. A request is NEVER
/// removed from this list after review; it just changes tag (New → Approved
/// / Rejected), so the admin always has a full audit trail here. Mirrors
/// app/admin/subscriptions/index.tsx. Collection: app_subscriptions.
///
/// PREMIUM layout: gradient stat hero (Total / Awaiting / Approved) with
/// divider-separated numbers, a segmented filter control, then modern
/// request cards — gradient avatar ring, name + plan line, status pill +
/// date, and a bold amount on the right edge.
///
/// Logic is untouched: same fetch + newest-first sort, same four filters,
/// same card tap route, same loading / denied / error / empty states.
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

  /// Status tone through the theme palette (lifted variants in dark mode),
  /// so pills / avatars / glows stay legible in both themes.
  Color _tone(String status) {
    final palette = ExpoPalette.of(context);
    switch (status) {
      case 'active':
        return palette.success;
      case 'rejected':
        return palette.danger;
      case 'expired':
        return palette.textDisabled;
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
                          SyllabusEntrance(
                            delayMs: (i < 8 ? i : 8) * 60,
                            child: _card(filtered[i]),
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
              AppLanguage.tr('Could not load subscription requests.',
                  'सदस्यता अनुरोधहरू लोड गर्न सकिएन।'),
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
  Widget _heroBand(int total, int pending, int active) {
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
                                AppLanguage.tr('Subscription Requests',
                                    'सदस्यता अनुरोधहरू'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.2),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                AppLanguage.tr(
                                    'Approve or reject premium subscription payments.',
                                    'प्रिमियम सदस्यता भुक्तानी स्वीकृत वा अस्वीकृत गर्नुहोस्।'),
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
                            child: _heroStat('$active',
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

  /// Premium segmented filter control: one surface track, the active filter
  /// fills with its tone colour + glow, the rest sit quiet.
  Widget _filterTrack(int total, int pending, int active, int rejected) {
    final items = [
      _FilterItem('all', AppLanguage.tr('Total', 'जम्मा'), total,
          const Color(0xFF2563EB)),
      _FilterItem('pending', AppLanguage.tr('New', 'नयाँ'), pending,
          ExpoPalette.of(context).warning),
      _FilterItem('active', AppLanguage.tr('Approved', 'स्वीकृत'), active,
          ExpoPalette.of(context).success),
      _FilterItem('rejected', AppLanguage.tr('Rejected', 'अस्वीकृत'),
          rejected, ExpoPalette.of(context).danger),
    ];
    final palette = ExpoPalette.of(context);
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
    final selected = _filter == item.value;
    final palette = ExpoPalette.of(context);
    return GestureDetector(
      onTap: () => setState(() => _filter = item.value),
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
            AppLanguage.tr('No requests in this filter yet.',
                'यो फिल्टरमा कुनै अनुरोध छैन।'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary),
          ),
          if (_filter != 'all') ...[
            const SizedBox(height: 6),
            Text(
              AppLanguage.tr(
                  'Approve or reject premium subscription payments.',
                  'प्रिमियम सदस्यता भुक्तानी स्वीकृत वा अस्वीकृत गर्नुहोस्।'),
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// Modern request card: gradient avatar with the user's initial, name +
  /// plan line, then a bottom row of status pill + date … and the amount
  /// standing bold on the right edge.
  Widget _card(Map<String, dynamic> r) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = '${r['status'] ?? 'pending'}';
    final tone = _tone(status);
    final who = '${r['userName'] ?? r['userEmail'] ?? r['uid'] ?? '—'}';
    final initial =
        who.trim().isEmpty ? '?' : who.trim()[0].toUpperCase();
    final date = _fmtDate(r['submittedAt']);
    final plan = '${r['planName'] ?? '—'}';
    final method = '${r['method'] ?? ''}'.toUpperCase();
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
          onTap: () =>
              context.push('/admin/subscriptions/${r['id'] ?? ''}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _avatar(initial, tone),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: palette.textPrimary)),
                          const SizedBox(height: 3),
                          Text(
                            '$plan · $method',
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
                      child: date.isNotEmpty
                          ? Row(
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
                                          fontSize:
                                              ExpoType.bodySmall,
                                          color: palette.textSecondary)),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
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

  Widget _avatar(String initial, Color tone) {
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
