import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/notification_tracks.dart';
import 'package:loksewa_solution/services/notification_badge.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/theme_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/theme_toggle.dart';
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
  /// Admin-only derived rows (reports, purchase requests, ...) — used by
  /// the track partition logic (see notification_tracks.dart). Normal
  /// user rows are always false.
  final bool adminOnly;
  // Exam-push rows: worker writes type='exam' to app_exam_notifications.
  // No expiresAt from the worker — the app computes expiry from the exam
  // set's real durationMinutes (see _load). Null = never expires (normal
  // notifications).
  final String? notifType;

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
    this.adminOnly = false,
  });
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
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Batch-fetch exam set durations (durationMinutes) for expiry computation.
/// Returns setId → durationMinutes. Missing/failed docs fall back to 60.
/// Best-effort: never throws.
Future<Map<String, int>> _fetchExamDurations(
    List<String> setIds, String idToken) async {
  final result = <String, int>{};
  if (setIds.isEmpty) return result;
  await Future.wait(setIds.map((setId) async {
    try {
      final doc = await FirestoreRest.getDocument(
        'app_exam_sets/$setId',
        idToken: idToken,
      );
      final dur = doc?['durationMinutes'];
      result[setId] =
          dur is num ? dur.toInt() : int.tryParse('$dur') ?? 60;
    } catch (_) {
      result[setId] = 60;
    }
  }));
  return result;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Notif>? _items;
  Object? _error;
  bool _autoOpenDone = false;
  // Active filter track (see notification_tracks.dart). Resolved against
  // the built tracks after every load so a vanished track never renders
  // an empty filter.
  String _selectedTrack = allTrack;

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
        // Exam-push rows: worker writes type='exam' rows (no expiresAt) to
        // app_exam_notifications. Readable by any signed-in user; expiry is
        // computed client-side from the exam set's durationMinutes below.
        FirestoreRest.listDocuments('app_exam_notifications', idToken: token),
        // Admin-only derived feeds for the track chips (see
        // notification_tracks.dart). Normal users never pay for these
        // queries. Pending items only — filtered client-side.
        isAdmin
            ? FirestoreRest.listDocuments('app_subscriptions',
                idToken: token, pageSize: 100)
            : Future.value(<Map<String, dynamic>>[]),
        isAdmin
            ? FirestoreRest.listDocuments('app_exam_purchases',
                idToken: token, pageSize: 100)
            : Future.value(<Map<String, dynamic>>[]),
        isAdmin
            ? FirestoreRest.listDocuments('app_content_purchases',
                idToken: token, pageSize: 100)
            : Future.value(<Map<String, dynamic>>[]),
        isAdmin
            ? FirestoreRest.listDocuments('app_deleterequest',
                idToken: token, pageSize: 100)
            : Future.value(<Map<String, dynamic>>[]),
        isAdmin
            ? FirestoreRest.listDocuments('app_exam_answers',
                idToken: token, pageSize: 100)
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      final personalRows = results[0] as List<Map<String, dynamic>>;
      final globalRows = results[1] as List<Map<String, dynamic>>;
      final reportRows = results[2] as List<Map<String, dynamic>>;
      final readIds = results[3] as Set<String>;
      final examRows = results[4] as List<Map<String, dynamic>>;
      final subscriptionRows = results[5] as List<Map<String, dynamic>>;
      final examPurchaseRows = results[6] as List<Map<String, dynamic>>;
      final contentPurchaseRows = results[7] as List<Map<String, dynamic>>;
      final deleteRequestRows = results[8] as List<Map<String, dynamic>>;
      final examAnswerRows = results[9] as List<Map<String, dynamic>>;

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
              adminOnly: true,
            );
          })
          .toList()
        ..sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      final adminTop =
          adminReports.length > 30 ? adminReports.sublist(0, 30) : adminReports;

      // Admin-only derived feeds for the remaining review queues — same
      // pattern as the report feed above. Pending items only (delete
      // requests have no status field: all are shown).
      final adminExtra = <_Notif>[];
      String strOf(dynamic v) => (v ?? '').toString().trim();
      for (final row in subscriptionRows) {
        if (strOf(row['status']) != 'pending') continue;
        final docId = strOf(row['id']);
        if (docId.isEmpty) continue;
        final name = strOf(row['userName']);
        final plan = strOf(row['planName']);
        final amount = strOf(row['amount']);
        adminExtra.add(_Notif(
          id: 'adminsub:$docId',
          title: 'नयाँ सब्सक्रिप्सन',
          preview:
              '${name.isEmpty ? 'कसैले' : name} — $plan (रु. $amount)',
          read: readIds.contains('adminsub:$docId'),
          createdAt: _asDate(row['submittedAt']) ?? _asDate(row['createdAt']),
          deepLink: '/admin/subscriptions/$docId',
          category: 'New Subscription',
          source: 'global',
          adminOnly: true,
        ));
      }
      for (final row in examPurchaseRows) {
        if (strOf(row['status']) != 'pending') continue;
        final docId = strOf(row['id']);
        if (docId.isEmpty) continue;
        final name = strOf(row['userName']);
        final title = strOf(row['examTitle']);
        final amount = strOf(row['amount']);
        adminExtra.add(_Notif(
          id: 'adminexamp:$docId',
          title: 'नयाँ खरिद अनुरोध',
          preview:
              '${name.isEmpty ? 'कसैले' : name} — $title (रु. $amount)',
          read: readIds.contains('adminexamp:$docId'),
          createdAt: _asDate(row['createdAt']),
          deepLink: '/admin/exam-purchases/$docId',
          category: 'New Purchase',
          source: 'global',
          adminOnly: true,
        ));
      }
      for (final row in contentPurchaseRows) {
        if (strOf(row['status']) != 'pending') continue;
        final docId = strOf(row['id']);
        if (docId.isEmpty) continue;
        final name = strOf(row['userName']);
        final title = strOf(row['contentTitle']);
        final amount = strOf(row['amount']);
        adminExtra.add(_Notif(
          id: 'admincontentp:$docId',
          title: 'नयाँ खरिद अनुरोध',
          preview:
              '${name.isEmpty ? 'कसैले' : name} — $title (रु. $amount)',
          read: readIds.contains('admincontentp:$docId'),
          createdAt: _asDate(row['createdAt']),
          deepLink: '/admin/content-purchases/$docId',
          category: 'New Purchase',
          source: 'global',
          adminOnly: true,
        ));
      }
      for (final row in deleteRequestRows) {
        final docId = strOf(row['id']);
        if (docId.isEmpty) continue;
        final name = strOf(row['name']);
        final email = strOf(row['email']);
        final reason = strOf(row['reason']);
        final who = name.isEmpty ? (email.isEmpty ? 'कसैले' : email) : name;
        adminExtra.add(_Notif(
          id: 'admindel:$docId',
          title: 'खाता मेटाउने अनुरोध',
          preview: '$who — ${reason.isEmpty ? 'कारण उल्लेख छैन' : reason}',
          read: readIds.contains('admindel:$docId'),
          createdAt: _asDate(row['createdAt']),
          deepLink: '/admin',
          category: 'Delete Request',
          source: 'global',
          adminOnly: true,
        ));
      }
      for (final row in examAnswerRows) {
        if (strOf(row['status']) != 'pending') continue;
        final docId = strOf(row['id']);
        if (docId.isEmpty) continue;
        final name = strOf(row['studentName']);
        final title = strOf(row['examSetTitle']);
        adminExtra.add(_Notif(
          id: 'admingrade:$docId',
          title: 'उत्तर ग्रेडिङ बाँकी',
          preview:
              '${name.isEmpty ? 'कसैले' : name} — $title',
          read: readIds.contains('admingrade:$docId'),
          createdAt: _asDate(row['createdAt']),
          deepLink: '/admin/exam-answer/$docId',
          category: 'Grading',
          source: 'global',
          adminOnly: true,
        ));
      }
      adminExtra.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));

      // Exam-push inbox rows: only type='exam' rows from
      // app_exam_notifications. Expiry is computed from the exam set's REAL
      // durationMinutes (not a hardcoded value): expiry = createdAt +
      // duration. Expired ones are hidden silently AND queued for background
      // deletion — the user never sees an "expired" label.
      //
      // Durations are batch-fetched once for all unique setIds (typically
      // <10 notifications), with a 60-minute fallback when a set doc can't
      // be read. Best-effort: expiry logic never breaks the list.
      final List<_Notif> expiredExam = [];
      final exams = <_Notif>[];
      final now = DateTime.now();
      // Temp lists so a mid-loop failure can't leave partial duplicates.
      final okExams = <_Notif>[];
      final okExpired = <_Notif>[];
      var computed = false;
      try {
        // Collect unique exam set IDs (first ID per notification).
        final setIds = <String>{};
        final examCandidates = <Map<String, dynamic>>[];
        for (final row in examRows) {
          if ((row['type'] ?? '').toString() != 'exam') continue;
          final docId = (row['id'] ?? '').toString();
          if (docId.isEmpty) continue;
          examCandidates.add(row);
          final ids = row['examSetIds'];
          if (ids is List && ids.isNotEmpty) {
            setIds.add(ids.first.toString());
          }
        }
        final durations =
            await _fetchExamDurations(setIds.toList(), token);
        for (final row in examCandidates) {
          final docId = (row['id'] ?? '').toString();
          final id = 'exam:$docId';
          final createdAt = _asDate(row['createdAt']);
          int durationMin = 60; // safe fallback
          final ids = row['examSetIds'];
          if (ids is List && ids.isNotEmpty) {
            durationMin = durations[ids.first.toString()] ?? 60;
          }
          // Null createdAt = can't compute expiry → keep visible (safe).
          final isExpired = createdAt != null &&
              now.isAfter(
                  createdAt.add(Duration(minutes: durationMin)));
          final item = _Notif(
            id: id,
            docId: docId,
            title: (row['title'] ?? 'New Model Set is Live!').toString(),
            preview: (row['bodyLogin'] ?? row['body'] ?? '').toString(),
            read: readIds.contains(id),
            createdAt: createdAt,
            deepLink: (row['deepLink'] as String?),
            category: 'Exam',
            imageUrl: (row['imageUrl'] as String?),
            source: 'exam',
            notifType: 'exam',
          );
          if (isExpired) {
            okExpired.add(item);
          } else {
            okExams.add(item);
          }
        }
        computed = true;
      } catch (_) {
        // Duration lookup failed entirely — fall through to the safe
        // fallback below (show all exam rows unexpired).
      }
      if (computed) {
        exams.addAll(okExams);
        expiredExam.addAll(okExpired);
      } else {
        for (final row in examRows) {
          if ((row['type'] ?? '').toString() != 'exam') continue;
          final docId = (row['id'] ?? '').toString();
          if (docId.isEmpty) continue;
          final id = 'exam:$docId';
          exams.add(_Notif(
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
          ));
        }
      }

      final all = [...personal, ...global, ...adminTop, ...adminExtra, ...exams];
      all.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));

      if (!mounted) return;
      setState(() {
        _items = all;
        _error = null;
      });
      // Keep the home header bell badge in sync with this inbox.
      NotificationBadge.set(all.where((i) => !i.read).length);

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
      // exam rows from app_exam_notifications so the inbox stays lean.
      // Failures are silently ignored; the rows stay hidden client-side
      // regardless.
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

  /// Fire-and-forget deletion of expired exam rows from
  /// app_exam_notifications. Best effort: failures are swallowed — rows
  /// stay hidden client-side regardless.
  void _cleanupExpiredExam(
      {required List<_Notif> examRows, required String token}) {
    Future(() async {
      for (final n in examRows) {
        final docId = n.docId;
        if (docId == null || docId.isEmpty) continue;
        try {
          await FirestoreRest.deleteDocument('app_exam_notifications/$docId',
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
    NotificationBadge.decrement();
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
    // The home header bell listens to this — the badge drops to zero
    // instantly, no home reload needed.
    NotificationBadge.clear();
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

    // Track partition (see notification_tracks.dart): admins get filter
    // chips (All | User | per-category); normal users have no admin-only
    // rows, so hasUsefulTracks is false and no chips are drawn —
    // byte-for-byte the page it has always been.
    List<NotificationTrack> tracks = const [];
    String activeTrack = allTrack;
    List<_Notif> visible = items ?? const [];
    if (items != null) {
      tracks = buildNotificationTracks(
        items
            .map((i) => TrackableRow(
                adminOnly: i.adminOnly, category: i.category))
            .toList(),
        allLabel: AppLanguage.tr('All', 'सबै'),
        userLabel: AppLanguage.tr('User', 'प्रयोगकर्ता'),
        otherLabel: AppLanguage.tr('Other', 'अन्य'),
      );
      activeTrack = resolveTrack(tracks, _selectedTrack);
      visible = filterByTrack<_Notif>(
        items,
        activeTrack,
        isAdminOnly: (i) => i.adminOnly,
        categoryOf: (i) => i.category,
      );
    }
    final showTracks = hasUsefulTracks(tracks);

    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
            title: 'Notifications',
            showThemeToggle: false,
            actions: [
              // Theme toggle first, then the mark-all pill — same order as
              // the Expo rightSlot (which also uses gap 4 between them).
              ThemeToggle(
                size: 36,
                isDark: Theme.of(context).brightness == Brightness.dark,
                onToggle: () => ThemeService.toggle(context),
                showCurrentMode: false,
                borderRadius: 10,
              ),
              const SizedBox(width: 4),
              _MarkAllButton(
                  hasUnread: hasUnread, onTap: _markAllRead),
            ],
          ),
          // Filter track chips (admin-only) — sits between the header and
          // the list, mirroring app/notifications.tsx.
          if (showTracks)
            NotificationTrackChips(
              tracks: tracks,
              active: activeTrack,
              onSelect: (value) =>
                  setState(() => _selectedTrack = value),
            ),
          Expanded(
            child: items == null && _error == null
                ? _loadingState(context)
                : _error != null && items == null
                    ? _errorState(context)
                    : RefreshIndicator.adaptive(
                        onRefresh: _load,
                        child: visible.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 120),
                                  _EmptyInbox(
                                      isFilterEmpty: items!.isNotEmpty),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                    top: 16, bottom: 32),
                                itemCount: visible.length,
                                itemBuilder: (context, i) =>
                                    _NotificationRow(
                                  key: ValueKey(
                                      '${visible[i].source}:${visible[i].id}'),
                                  item: visible[i],
                                  onTap: () => _open(visible[i]),
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

/// Horizontal filter-track chips (admin-only) — mirrors the FilterTrack
/// row in app/notifications.tsx. Sits between the header and the list.
///
/// Public for widget tests; the screen only renders it when
/// [hasUsefulTracks] is true (admin with admin-only rows).
class NotificationTrackChips extends StatelessWidget {
  final List<NotificationTrack> tracks;
  final String active;
  final ValueChanged<String> onSelect;

  const NotificationTrackChips({
    super.key,
    required this.tracks,
    required this.active,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final primary = palette.primary;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final track = tracks[i];
          final selected = track.value == active;
          return GestureDetector(
            onTap: () => onSelect(track.value),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? primary
                    : palette.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? primary : palette.divider,
                  width: 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.label,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : palette.textPrimary,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.25)
                          : primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${track.count}',
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  /// True when the inbox has rows but the active filter shows none —
  /// mirrors the two silences in app/notifications.tsx.
  final bool isFilterEmpty;

  const _EmptyInbox({this.isFilterEmpty = false});
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
          Text(
              isFilterEmpty
                  ? 'No notifications in this filter'
                  : 'No notifications yet',
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
