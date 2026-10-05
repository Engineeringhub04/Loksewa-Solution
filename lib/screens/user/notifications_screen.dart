import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/theme_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../learn/exam_tab.dart';
import '../tabs_screen.dart';

/// Notification inbox — mirrors app/notifications.tsx +
/// src/core/firebase/services/notifications.ts.
///
/// Merges the personal inbox (`users/{uid}/notifications`, durable
/// server-side `read` field) with the global feed (`app_global_notification`,
/// `segment == 'nonlogin'` campaigns excluded, read state kept locally per
/// account under `loksewa:globalNotificationReadIds:{uid}` — the exact key the
/// Expo app uses). Admins additionally see derived report rows built from
/// `app_report_history` (newest 30, read state shared with the global set).
/// Rows sort newest-first by createdAt.
class NotificationsScreen extends StatefulWidget {
  /// When set (notification-tap flow), the list auto-opens the matching
  /// notification's details once loaded. Falls back to [fallbackDeepLink]
  /// when the id isn't found in the inbox.
  final String? autoOpenId;
  final String? fallbackDeepLink;

  const NotificationsScreen({
    super.key,
    this.autoOpenId,
    this.fallbackDeepLink,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _Notif {
  final String id;
  final String? docId; // personal doc id — null for global/admin rows
  final String title;
  final String preview;
  bool read;
  final DateTime? createdAt;
  final String? deepLink;
  final String category;
  final String? imageUrl;
  final String source; // 'personal' | 'global' | 'exam'
  final bool updatedNotice;
  // Exam-push auto-expiry (Point 3): worker sets type='exam' + expiresAt
  // (ISO8601, ~60 min after creation) on app_notifications rows. Null =
  // never expires (normal notifications).
  final String? notifType;
  final DateTime? expiresAt;

  _Notif({
    required this.id,
    this.docId,
    required this.title,
    required this.preview,
    required this.read,
    this.createdAt,
    this.deepLink,
    required this.category,
    this.imageUrl,
    required this.source,
    this.updatedNotice = false,
    this.notifType,
    this.expiresAt,
  });

  /// Silent expiry check — expired exam rows are hidden, never shown with
  /// an "expired" label. Missing/null expiresAt = never expires.
  bool get isExpired {
    if (notifType != 'exam') return false;
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isBefore(DateTime.now());
  }
}

String _normalizeCategory(dynamic value) {
  if (value == 'app') return 'App Notice';
  if (value == 'user') return 'User / Personal';
  if (value == 'other') return 'Other';
  final s = (value ?? '').toString().trim();
  return s.isEmpty ? 'App Notice' : s;
}

DateTime? _asDate(dynamic v) {
  if (v is DateTime) return v;
  // Backward compat: old docs saved expiresAt as ISO string (worker bug).
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Notif>? _items;
  Object? _error;
  bool _autoOpenDone = false;

  String get _globalReadKey =>
      'loksewa:globalNotificationReadIds:${AuthService.currentUser?.uid ?? 'guest'}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Set<String>> _getGlobalReadIds() async {
    try {
      final raw = await PrefsService.getString(_globalReadKey);
      if (raw == null || raw.isEmpty) return {};
      final List list = json.decode(raw);
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveGlobalReadIds(Set<String> ids) async {
    try {
      await PrefsService.setString(_globalReadKey, json.encode(ids.toList()));
    } catch (_) {
      // Local read-state is best effort; a failed write only leaves the row unread.
    }
  }

  Future<void> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _items = [];
        _error = null;
      });
      return;
    }
    try {
      final token = await AuthService.getValidIdToken();
      final profile =
          await FirestoreRest.getDocument('users/$uid', idToken: token);
      final isAdmin = profile?['isAdmin'] == true;

      final results = await Future.wait([
        FirestoreRest.listDocuments('users/$uid/notifications',
            idToken: token),
        FirestoreRest.listDocuments('app_global_notification',
            idToken: token),
        isAdmin
            ? FirestoreRest.listDocuments('app_report_history',
                idToken: token, pageSize: 100)
            : Future.value(<Map<String, dynamic>>[]),
        _getGlobalReadIds(),
        // Exam-push rows (Point 3): worker writes type='exam' + expiresAt
        // (~60 min after creation) to app_notifications. Readable by any
        // signed-in user; filtered client-side below.
        FirestoreRest.listDocuments('app_notifications', idToken: token),
      ]);

      final personalRows = results[0] as List<Map<String, dynamic>>;
      final globalRows = results[1] as List<Map<String, dynamic>>;
      final reportRows = results[2] as List<Map<String, dynamic>>;
      final readIds = results[3] as Set<String>;
      final examRows = results[4] as List<Map<String, dynamic>>;

      final personal = personalRows
          .map((row) => _Notif(
                id: (row['id'] ?? '').toString(),
                docId: (row['id'] ?? '').toString(),
                title: (row['title'] ?? 'Notification').toString(),
                preview: (row['preview'] ?? '').toString(),
                read: row['read'] == true,
                createdAt: _asDate(row['createdAt']),
                deepLink: (row['deepLink'] as String?),
                category: _normalizeCategory(row['category']),
                imageUrl: (row['imageUrl'] as String?),
                source: 'personal',
                updatedNotice: row['updatedNotice'] == true,
              ))
          .toList();

      final global = globalRows
          .where((row) => (row['segment'] ?? '').toString() != 'nonlogin')
          .map((row) {
        final docId = (row['id'] ?? '').toString();
        final id = 'global:$docId';
        return _Notif(
          id: id,
          title: (row['title'] ?? 'Notification').toString(),
          // Mirrors notifications.ts: global rows fall back through bodyLogin/body.
          preview: (row['preview'] ?? row['bodyLogin'] ?? row['body'] ?? '')
              .toString(),
          read: readIds.contains(id),
          createdAt: _asDate(row['createdAt']),
          deepLink: (row['deepLink'] as String?),
          category: _normalizeCategory(row['category']),
          imageUrl: (row['imageUrl'] as String?),
          source: 'global',
          updatedNotice: row['updatedNotice'] == true,
        );
      }).toList();

      // Admin-only derived report feed — mirrors fetchAdminReportNotifications.
      final adminReports = reportRows
          .map((row) {
            final docId = (row['id'] ?? '').toString();
            final id = 'adminreport:$docId';
            final reporter =
                (row['reporterName'] ?? 'A user').toString().trim();
            final reporterName = reporter.isEmpty ? 'A user' : reporter;
            final context = (row['contextLabel'] ?? '').toString().trim();
            final reason = (row['reason'] ?? '').toString().trim();
            final target = (row['targetTitle'] ?? '').toString().trim();
            final status = (row['status'] ?? 'pending').toString();
            final parts = <String>[
              '$reporterName reported${reason.isNotEmpty ? ': $reason' : ' an issue'}.'
            ];
            if (target.isNotEmpty) parts.add('On: $target');
            if (status != 'pending') parts.add('($status)');
            return _Notif(
              id: id,
              title: context.isNotEmpty
                  ? 'New report \u00b7 $context'
                  : 'New report received',
              preview: parts.join(' '),
              read: readIds.contains(id),
              createdAt: _asDate(row['createdAt']),
              deepLink: '/admin/report-history/$docId',
              category: 'New Report',
              source: 'global',
            );
          })
          .toList()
        ..sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      final adminTop =
          adminReports.length > 30 ? adminReports.sublist(0, 30) : adminReports;

      // Exam-push inbox rows (Point 3): only type='exam' rows from
      // app_notifications. Expired ones are hidden silently AND queued for
      // background deletion — the user never sees an "expired" label.
      final List<_Notif> expiredExam = [];
      final exams = <_Notif>[];
      for (final row in examRows) {
        if ((row['type'] ?? '').toString() != 'exam') continue;
        final docId = (row['id'] ?? '').toString();
        if (docId.isEmpty) continue;
        final id = 'exam:$docId';
        final item = _Notif(
          id: id,
          docId: docId,
          title: (row['title'] ?? 'New Model Set is Live!').toString(),
          preview: (row['bodyLogin'] ?? row['body'] ?? '').toString(),
          read: readIds.contains(id),
          createdAt: _asDate(row['createdAt']),
          deepLink: (row['deepLink'] as String?),
          category: 'Exam',
          imageUrl: (row['imageUrl'] as String?),
          source: 'exam',
          notifType: 'exam',
          expiresAt: _asDate(row['expiresAt']),
        );
        if (item.isExpired) {
          expiredExam.add(item);
        } else {
          exams.add(item);
        }
      }

      final all = [...personal, ...global, ...adminTop, ...exams];
      all.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));

      if (!mounted) return;
      setState(() {
        _items = all;
        _error = null;
      });

      // Notification-tap flow (Point 1): auto-open the tapped notification
      // once the list is ready. Runs once only — pull-to-refresh must not
      // re-trigger it.
      if (widget.autoOpenId != null && !_autoOpenDone) {
        _autoOpenDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoOpenNotification();
        });
      }

      // Background cleanup (best effort, never blocks UI): delete expired
      // exam rows so the inbox stays lean. Non-admins get a permission
      // error until the firebase.rules update is published — silently
      // ignored; the rows stay hidden client-side regardless.
      if (expiredExam.isNotEmpty) {
        _cleanupExpiredExam(examRows: expiredExam, token: token);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
      });
    }
  }

  /// Fire-and-forget deletion of expired exam rows. Best effort: failures
  /// (e.g. non-admin before the rules update) are swallowed — rows stay
  /// hidden client-side regardless.
  void _cleanupExpiredExam(
      {required List<_Notif> examRows, required String token}) {
    Future(() async {
      for (final n in examRows) {
        final docId = n.docId;
        if (docId == null || docId.isEmpty) continue;
        try {
          await FirestoreRest.deleteDocument('app_notifications/$docId',
              idToken: token);
        } catch (_) {
          // Best effort — keep going with the rest.
        }
      }
    });
  }

  Future<void> _markRead(_Notif item) async {
    if (item.read) return;
    final uid = AuthService.currentUser?.uid;
    setState(() => item.read = true);
    if (uid == null) return;
    try {
      // Exam rows share the local read-id set with global rows (same key
      // the home-tab badge uses).
      if (item.source == 'global' || item.source == 'exam') {
        final ids = await _getGlobalReadIds();
        ids.add(item.id);
        await _saveGlobalReadIds(ids);
      } else if (item.docId != null) {
        // Durable server-side read — mirrors markNotificationRead's
        // updateDocument('users/{uid}/notifications/{id}', { read: true }).
        final token = await AuthService.getValidIdToken();
        await FirestoreRest.updateDocument(
            'users/$uid/notifications/${item.docId}', {'read': true},
            idToken: token);
      }
    } catch (_) {
      // Best effort — the row already looks read.
    }
  }

  Future<void> _markAllRead() async {
    final items = _items;
    final uid = AuthService.currentUser?.uid;
    if (items == null || uid == null) return;
    if (!items.any((i) => !i.read)) return;
    setState(() {
      for (final i in items) {
        i.read = true;
      }
    });
    showToast(context, 'All notifications marked as read', ToastVariant.success);
    try {
      final token = await AuthService.getValidIdToken();
      final globalIds = items
          .where((i) => i.source == 'global' || i.source == 'exam')
          .map((i) => i.id)
          .toList();
      final ids = await _getGlobalReadIds();
      ids.addAll(globalIds);
      await _saveGlobalReadIds(ids);
      // Mirrors markAllNotificationsRead: batched merge writes of
      // { read: true } in chunks of 400 (chunking lives in commitWrites).
      final writes = items
          .where((i) => i.source == 'personal' && i.docId != null)
          .map((i) => FirestoreWrite(
              'users/$uid/notifications/${i.docId}', {'read': true},
              merge: true))
          .toList();
      await FirestoreRest.commitWrites(writes, idToken: token);
    } catch (_) {
      // Best effort.
    }
  }

  void _open(_Notif item) {
    _markRead(item);
    context.push(
      '/notification/${Uri.encodeComponent(item.id)}',
      extra: {
        'title': item.title,
        'body': item.preview,
        'category': item.category,
        'imageUrl': item.imageUrl ?? '',
        'deepLink': item.deepLink ?? '',
        'updatedNotice': item.updatedNotice,
        'createdAtMs': item.createdAt?.millisecondsSinceEpoch ?? 0,
      },
    );
  }

  /// Notification-tap flow (Point 1): open the tapped notification's
  /// details. Matches by raw id, document id, or the derived `exam:` /
  /// `global:` prefixed ids. When the item isn't in the inbox (e.g. the
  /// push arrived before the inbox write), falls back to the FCM deep link
  /// so the user still lands on the right exam page.
  void _autoOpenNotification() {
    final targetId = widget.autoOpenId;
    if (targetId == null || targetId.isEmpty) return;
    final items = _items;
    if (items == null) return;
    _Notif? match;
    for (final item in items) {
      if (item.id == targetId || item.docId == targetId) {
        match = item;
        break;
      }
    }
    match ??= () {
      for (final item in items) {
        if (item.id == 'exam:$targetId' || item.id == 'global:$targetId') {
          return item;
        }
      }
      return null;
    }();
    if (match != null) {
      _open(match);
      return;
    }
    final fallback = widget.fallbackDeepLink;
    if (fallback != null && fallback.isNotEmpty) {
      _openExamFallback(fallback);
    }
  }

  /// Fallback when the tapped notification isn't in the inbox: follow its
  /// deep link. Exam links open the exam tab scrolled to the set's card;
  /// anything else pushes the link as-is.
  void _openExamFallback(String deepLink) {
    final examMatch = RegExp(r'^/exam/([^/?#]+)$').firstMatch(deepLink);
    if (examMatch != null) {
      final setId = examMatch.group(1)!;
      ExamTab.pendingHighlightSetId = setId;
      TabsScreen.tabIndex.value = 1; // Exam tab
      context.go('/');
      return;
    }
    context.push(deepLink);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasUnread = items?.any((i) => !i.read) ?? false;
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
            title: 'Notifications',
            showThemeToggle: false,
            actions: [
              // Theme toggle first, then the mark-all pill — same order as
              // the Expo rightSlot (which also uses gap 4 between them).
              GestureDetector(
                onTap: () => ThemeService.toggle(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _MarkAllButton(
                  hasUnread: hasUnread, onTap: _markAllRead),
            ],
          ),
          Expanded(
            child: items == null && _error == null
                ? _loadingState(context)
                : _error != null && items == null
                    ? _errorState(context)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: items!.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 120),
                                  _EmptyInbox(),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                    top: 16, bottom: 32),
                                itemCount: items.length,
                                itemBuilder: (context, i) =>
                                    _NotificationRow(
                                  key: ValueKey(
                                      '${items[i].source}:${items[i].id}'),
                                  item: items[i],
                                  onTap: () => _open(items[i]),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _loadingState(BuildContext context) {
    return const PreloadingWidget(
      tinted: false,
      label: 'Loading Notifications...',
      hint: 'Checking your inbox',
    );
  }

  Widget _errorState(BuildContext context) {
    final palette = ExpoPalette.of(context);
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
              onTap: () {
                setState(() {
                  _error = null;
                  _items = null;
                });
                _load();
              },
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
                    Icon(Icons.refresh, size: 15, color: Colors.white),
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

/// The "Mark all read" pill — mirrors styles.markAllButton in
/// app/notifications.tsx: height 36, paddingHorizontal 10, radius 10,
/// rgba(255,255,255,0.2) fill + white 35% hairline border, checkmark-done
/// 15px + 11px bold label (letterSpacing 0.1, maxWidth 78 so the pill never
/// resizes). Dimmed to 0.45 when nothing is unread, 0.75 while pressed.
class _MarkAllButton extends StatefulWidget {
  final bool hasUnread;
  final VoidCallback onTap;

  const _MarkAllButton({required this.hasUnread, required this.onTap});

  @override
  State<_MarkAllButton> createState() => _MarkAllButtonState();
}

class _MarkAllButtonState extends State<_MarkAllButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: !widget.hasUnread ? 0.45 : (_pressed ? 0.75 : 1.0),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.hasUnread ? widget.onTap : null,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.done_all,
                  size: 15, color: Colors.white),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 78),
                child: const Text(
                  'Mark all read',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();
  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 64, color: palette.textDisabled),
          const SizedBox(height: 12),
          Text('No notifications yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

IconData _categoryIcon(String category) {
  final v = category.toLowerCase();
  if (v.contains('course') || v.contains('class')) {
    return Icons.school_outlined;
  }
  if (v.contains('mcq') || v.contains('test') || v.contains('exam')) {
    return Icons.assignment_outlined;
  }
  // Before 'update': "Report Update" must show the flag, not the download glyph.
  if (v.contains('report')) return Icons.flag_outlined;
  if (v.contains('update') || v.contains('version')) {
    return Icons.cloud_download_outlined;
  }
  if (v.contains('problem') || v.contains('maintenance')) {
    return Icons.build_outlined;
  }
  if (v.contains('result') || v.contains('achievement')) {
    return Icons.emoji_events_outlined;
  }
  if (v.contains('user') || v.contains('personal')) {
    return Icons.person_outlined;
  }
  return Icons.notifications_outlined;
}

const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'
];

/// Mirrors formatTimeAgo in src/core/notifications/timeAgo.ts (English).
String _timeAgo(DateTime? createdAt) {
  if (createdAt == null) return '';
  final diff = DateTime.now().difference(createdAt);
  if (diff.isNegative) return 'Just now';
  final mins = diff.inMinutes;
  if (mins < 1) return 'Just now';
  final hours = mins ~/ 60;
  final days = hours ~/ 24;
  // Older than a month → absolute date, en-GB style.
  if (days > 30) {
    return '${createdAt.day} ${_enMonths[createdAt.month - 1]} ${createdAt.year}';
  }
  final String time;
  if (days >= 1) {
    time = '${days}d';
  } else if (hours >= 1) {
    time = '${hours}h';
  } else {
    time = '${mins}m';
  }
  return '$time ago';
}

/// One inbox row — mirrors NotificationRow in
/// src/components/cards/NotificationRow.tsx.
class _NotificationRow extends StatefulWidget {
  final _Notif item;
  final VoidCallback onTap;

  const _NotificationRow(
      {super.key, required this.item, required this.onTap});

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final item = widget.item;
    final unread = !item.read;
    final primary = palette.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ExpoRadius.lg),
            border: Border.all(
              color: unread
                  ? primary.withValues(alpha: 0x55 / 0xFF)
                  : palette.divider,
              width: 0.5,
            ),
            color: _pressed
                ? palette.surfaceAlt
                : unread
                    ? primary.withValues(alpha: 0x10 / 0xFF)
                    : palette.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary.withValues(alpha: 0x1A / 0xFF),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_categoryIcon(item.category),
                        size: 20, color: primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: ExpoType.body,
                                  fontWeight: unread
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (unread) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (item.preview.isNotEmpty)
                          Text(
                            item.preview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: ExpoType.bodySmall,
                              height: 18 / 12,
                            ),
                          ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            if (item.category.isNotEmpty)
                              Text(
                                item.category,
                                style: TextStyle(
                                  color: primary,
                                  fontSize: ExpoType.caption,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (item.updatedNotice) ...[
                              if (item.category.isNotEmpty)
                                const SizedBox(width: 9),
                              Text(
                                'Updated Notice',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: ExpoType.caption,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            Builder(builder: (_) {
                              final ts = _timeAgo(item.createdAt);
                              if (ts.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    ts,
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: ExpoType.caption,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(ExpoRadius.md),
                    child: Container(
                      color: palette.surfaceAlt,
                      child: Image.network(
                        item.imageUrl!,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
