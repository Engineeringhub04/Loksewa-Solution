import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/home/notice_card.dart';
import 'package:loksewa_solution/widgets/home/notice_date.dart';
import 'package:loksewa_solution/widgets/home/notice_visual.dart';
import 'package:loksewa_solution/widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Dedicated Notices page — mirrors app/notices.tsx.
///
/// Firestore-backed `app_notices` (newest first by publishedAt, `status ==
/// 'hidden'` dropped, targeted notices filtered client-side against the
/// user's enrolled subcourse — exactly like fetchNotices in
/// src/core/firebase/services/notices.ts). Opens with the intro card
/// (icon tile + title + intro line + count/latest pills); rows are the
/// shared PremiumNoticeCard (NoticeCard). Pull-to-refresh forces a refetch.
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Mirrors noticeTargetsSubcourse(): empty target list = everyone;
  /// otherwise only the enrolled subcourse sees it.
  bool _visibleTo(Map<String, dynamic> n, String? subcourseId) {
    final targets = n['targetSubcourseIds'];
    final List list = targets is List ? targets : const [];
    if (list.isEmpty) return true;
    if (subcourseId == null || subcourseId.isEmpty) return false;
    return list.map((e) => e.toString()).contains(subcourseId);
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final idToken = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid;
    String? subcourseId;
    if (uid != null) {
      try {
        final userDoc =
            await FirestoreRest.getDocument('users/$uid', idToken: idToken);
        subcourseId = userDoc?['subcourseId'] as String?;
      } catch (_) {}
    }
    final rows = await FirestoreRest.listDocuments('app_notices',
        idToken: idToken, pageSize: 30);
    final items = rows
        .where((n) =>
            (n['status'] ?? '').toString() != 'hidden' &&
            _visibleTo(n, subcourseId))
        .toList();
    items.sort((a, b) {
      final pa = a['publishedAt'];
      final pb = b['publishedAt'];
      final ta = pa is DateTime ? pa.millisecondsSinceEpoch : 0;
      final tb = pb is DateTime ? pb.millisecondsSinceEpoch : 0;
      return tb.compareTo(ta);
    });
    return items;
  }

  /// Admin-typed Nepali date wins; blank falls back to the publish instant,
  /// which stays in English — mirrors formatLatest in app/notices.tsx.
  String _dateLabel(Map<String, dynamic> n) {
    final label = (n['dateLabel'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    final p = n['publishedAt'];
    if (p is DateTime) return noticeNeDate(p);
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          const SubpageHeader(title: 'Notices'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _loadingState(palette);
                }
                if (snap.hasError) {
                  return _errorState(context, palette);
                }
                final items = snap.data ?? [];
                return RefreshIndicator(
                  onRefresh: () async {
                    final next = _load();
                    setState(() => _future = next);
                    await next;
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(
                        ExpoSpacing.screenPadding),
                    children: [
                      _introCard(context, palette, items),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: StatusPill(
                              label: 'No notices yet',
                              color: palette.textSecondary,
                              icon: Icons.campaign_outlined,
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          Builder(builder: (_) {
                            final n = items[i];
                            return NoticeCard(
                              title:
                                  (n['title'] ?? 'Notice').toString(),
                              date: _dateLabel(n),
                              kind: n['kind'] as String?,
                              description:
                                  (n['excerpt'] as String?),
                              onPress: () => context.push(
                                  '/notice/${n['id']}',
                                  extra: n),
                            );
                          }),
                        ],
                      const SizedBox(height: 24),
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

  /// The intro block: plain card with icon tile + title + one line,
  /// then the count + latest pills — mirrors app/notices.tsx.
  Widget _introCard(BuildContext context, ExpoPalette palette,
      List<Map<String, dynamic>> items) {
    final primary = palette.primary;
    final latest = items.isNotEmpty ? items.first : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: palette.divider, width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0x17 / 0xFF),
              borderRadius:
                  BorderRadius.circular(ExpoRadius.md),
            ),
            alignment: Alignment.center,
            child:
                Icon(Icons.campaign, size: 22, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notices',
                    style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: ExpoType.h3,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Announcements, app updates and exam schedules \u2014 newest first.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: ExpoType.caption),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      label: '${items.length} notice(s)',
                      color: noticeToneBase('info', palette),
                      icon: Icons.list_outlined,
                    ),
                    if (latest != null &&
                        _dateLabel(latest).isNotEmpty)
                      StatusPill(
                        label:
                            'Latest \u00b7 ${_dateLabel(latest)}',
                        color:
                            noticeToneBase('success', palette),
                        icon: Icons.access_time,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingState(ExpoPalette palette) {
    return const PreloadingWidget(
      tinted: false,
      label: 'Loading Notices...',
      hint: 'Fetching your content',
    );
  }

  Widget _errorState(BuildContext context, ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: palette.textDisabled),
            const SizedBox(height: 12),
            Text('Data Not Found',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text("We couldn't load this content. Please try again.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 14)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () =>
                  setState(() => _future = _load()),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh,
                        size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Try Again',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


