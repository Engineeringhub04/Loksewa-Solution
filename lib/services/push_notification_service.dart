// Push notification service — FCM version of the React app's
// pushNotifications.ts. Same Firestore structure:
//   - Signed-in:  users/{uid}/push_tokens/{deviceId}
//   - Signed-out: app_device_push_tokens/{deviceId}
//
// STABLE DEVICE ID (v1.0.60+): Uses ANDROID_ID which survives reinstalls,
// so one physical device = one document. No duplicates on reinstall.
// Account switches clean up the old user's token via last_uid tracking.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'device_session_service.dart';
import 'firestore_rest.dart';
import 'app_language.dart';
import 'public_downloads.dart';

/// Background message handler — must be top-level.
/// The system tray shows the notification automatically.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

/// Notification id for download ALERTS (v1.0.123) — the pair of
/// pdfDownloadNotificationId (778899, declared in
/// pdf_download_dialog.dart), which carries the silent progress entry
/// on the low channel. This id lives ONLY on the high-importance
/// alert channel: it posts the one-shot start alert when a download
/// begins, and the completion post replaces it when the download
/// settles.
const int pdfDownloadAlertNotificationId = 778900;

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;
  static String? _deviceId;

  static const _lastUidKey = 'push_last_uid';
  static const _legacyDeviceIdKey = 'push_device_id';

  /// Android channel for foreground (app-open) notifications.
  static const _fgChannelId = 'loksewa_foreground';
  static const _fgChannelName = 'Loksewa Notifications';

  /// Android channel for download progress (v1.0.120) — low importance
  /// and silent: it re-posts on every percent tick. Since v1.0.123 the
  /// progress notification lives ONLY on this channel, under its own id
  /// (pdfDownloadNotificationId) — it never hops channels.
  static const _dlChannelId = 'downloads';
  static const _dlChannelName = 'Downloads';

  /// Android channel for download ALERTS (v1.0.121) — high importance
  /// with the default sound. Since v1.0.123 only the alert notification
  /// (pdfDownloadAlertNotificationId) rides it: the one-shot START alert
  /// when a download begins and the COMPLETION post when it settles.
  /// v1.0.121–v1.0.122 instead switched ONE id between this channel and
  /// the low channel above; Android locks/groups a notification by
  /// channel unpredictably in that setup, trapping the entry in the
  /// shade's SILENT section and swallowing the start alert — hence the
  /// split into two ids, one per channel.
  static const _dlAlertChannelId = 'download_alerts';
  static const _dlAlertChannelName = 'Download Alerts';

  /// Progress ids whose one-shot START alert already went out for the
  /// running download. Cleared when the download settles or is
  /// cancelled, so the next download alerts again.
  static final Set<int> _dlAlertPosted = <int>{};

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsReady = false;

  /// Callback for notification taps — set by the router layer.
  /// Receives the full FCM data payload as strings (deepLink,
  /// notificationId, examSetId, kind, type, ...).
  static void Function(Map<String, String?> data)? onNotificationTap;

  /// SharedPreferences keys for a tap that arrived while the app was
  /// terminated (cold start). The splash consumes these after the auth
  /// check; see main.dart for the full flow.
  static const pendingNotificationIdKey = 'pending_notification_id';
  static const pendingNotificationLinkKey = 'pending_notification_deeplink';

  /// FCM data values arrive as dynamic — normalize to strings.
  static Map<String, String?> _stringData(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, value?.toString()));

  /// Resolves the title/body to display for a foreground (app-open) FCM
  /// message. Pure logic — unit-testable.
  ///
  /// Prefers the FCM `notification` payload (sent by the server in English
  /// per the user's push-language rule — never translated or modified
  /// here), falls back to `data['title']`/`data['body']`/`data['message']`
  /// for data-only messages. Returns null when there is nothing sensible
  /// to show — callers skip gracefully instead of crashing.
  @visibleForTesting
  static ({String title, String body})? resolveForegroundContent(
      RemoteMessage message) {
    final n = message.notification;
    final data = message.data;
    String? pick(String? primary, List<String> keys) {
      final p = primary?.trim();
      if (p != null && p.isNotEmpty) return p;
      for (final k in keys) {
        final v = data[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final title = pick(n?.title, const ['title']);
    final body = pick(n?.body, const ['body', 'message']);
    if (title == null && body == null) return null;
    return (title: title ?? 'Loksewa Solution', body: body ?? '');
  }

  /// Encodes the FCM data payload for a local-notification tap payload.
  /// Pure logic — unit-testable.
  @visibleForTesting
  static String encodeTapPayload(Map<String, dynamic> data) =>
      jsonEncode(_stringData(data));

  /// Decodes a tap payload back to the string map the
  /// [onNotificationTap] callback expects. Never throws.
  @visibleForTesting
  static Map<String, String?> decodeTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return _stringData(decoded);
    } catch (_) {}
    return const {};
  }

  /// Initializes flutter_local_notifications (Android channel + iOS Darwin
  /// settings + tap routing). Best-effort: never throws, never blocks
  /// startup.
  ///
  /// iOS FUTURE-PROOFING: Push activates automatically once an APNs key is
  /// added in the Firebase console — no app update needed. Without the key,
  /// FCM token fetch fails gracefully (caught below) and the app runs fine.
  static Future<void> _initLocalNotifications() async {
    if (_localNotificationsReady) return;
    try {
      const androidInit = AndroidInitializationSettings('ic_notification');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          // Download-complete notifications carry the saved file's
          // content URI as their payload (v1.0.121): a tap opens THAT
          // file from the Downloads folder instead of routing like an
          // FCM tap.
          if (payload != null && payload.startsWith('content://')) {
            unawaited(
                PublicDownloads.openDownloadedFile(payload, 'application/pdf'));
            return;
          }
          final data = decodeTapPayload(payload);
          if (data.isNotEmpty) onNotificationTap?.call(data);
        },
      );
      const channel = AndroidNotificationChannel(
        _fgChannelId,
        _fgChannelName,
        description: 'Notifications received while the app is open',
        importance: Importance.max,
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _dlChannelId,
          _dlChannelName,
          description: 'File download progress',
          importance: Importance.low,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _dlAlertChannelId,
          _dlAlertChannelName,
          description: 'Download start and completion alerts',
          importance: Importance.high,
        ),
      );
      _localNotificationsReady = true;
    } catch (_) {
      // Foreground tray is a nice-to-have — never break startup.
    }
  }

  /// Shows a tray notification for a foreground FCM message, carrying the
  /// full FCM data payload so taps route exactly like background taps.
  /// Best-effort: never throws.
  static Future<void> _showForegroundNotification(
      RemoteMessage message) async {
    try {
      if (!_localNotificationsReady) await _initLocalNotifications();
      if (!_localNotificationsReady) return;
      final content = resolveForegroundContent(message);
      if (content == null) return;
      final id =
          (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch)
              .abs() %
              0x7fffffff;
      final androidDetails = AndroidNotificationDetails(
        _fgChannelId,
        _fgChannelName,
        channelDescription: 'Notifications received while the app is open',
        importance: Importance.max,
        priority: Priority.high,
        // Always carry an expanded (BigText) view so foreground
        // notifications can be expanded in the tray, like system ones.
        styleInformation: BigTextStyleInformation(
          content.body,
          contentTitle: content.title,
        ),
      );
      await _localNotifications.show(
        id: id,
        title: content.title,
        body: content.body,
        notificationDetails: NotificationDetails(android: androidDetails),
        payload: encodeTapPayload(message.data),
      );
    } catch (_) {}
  }

  /// Body copy for a download-progress notification: "Downloading…"
  /// while the total is unknown, "Downloading… {pct}%" once it is
  /// (clamped to 0–100). Pure logic — unit-testable.
  @visibleForTesting
  static String downloadProgressBody(int? percent) {
    final pct = percent?.clamp(0, 100);
    return pct == null ? 'Downloading…' : 'Downloading… $pct%';
  }

  /// Title/body/expanded-text for the download COMPLETION post
  /// (v1.0.123 copy design): the fixed status line is the title —
  /// "Download Complete 🎉" / "Download Failed ❌" — and the file name
  /// moves to the body; the expanded (BigText) view repeats the name
  /// and, for a public-Downloads save, adds where the file landed.
  /// Pure logic — unit-testable.
  @visibleForTesting
  static ({String title, String body, String bigText}) downloadCompletionCopy({
    required bool success,
    required String fileName,
    required bool toDownloads,
  }) {
    if (!success) {
      return (
        title: 'Download Failed ❌',
        body: fileName,
        bigText: fileName,
      );
    }
    return (
      title: 'Download Complete 🎉',
      body: fileName,
      bigText: toDownloads ? '$fileName\nSaved to Downloads' : fileName,
    );
  }

  /// Shows/updates the Android download-progress notification under
  /// the progress [id] (v1.0.120; split-id design v1.0.123). The
  /// progress entry lives ONLY on the low, silent channel — the file
  /// name is the title, the body reads "Downloading… {pct}%"
  /// ([percent] null → indeterminate) — and is visible in the shade
  /// from the first tick. On the FIRST call of a download it ALSO
  /// posts the one-shot START alert under
  /// [pdfDownloadAlertNotificationId] on the high-importance alert
  /// channel (sound + heads-up, like a normal notification) so the
  /// download start is actually noticed; the two ids never switch
  /// channels. Android only — iOS has no progress notifications, so
  /// this is a no-op there. Best-effort: never throws.
  static Future<void> showDownloadProgress({
    required int id,
    required String fileName,
    required int? percent,
  }) async {
    try {
      if (!Platform.isAndroid) return;
      if (!_localNotificationsReady) await _initLocalNotifications();
      if (!_localNotificationsReady) return;
      final pct = percent?.clamp(0, 100);
      final body = downloadProgressBody(percent);
      // Expandable style (v1.0.122): without a styleInformation the
      // shade shows no expand (⌄) caret on these notifications.
      final style = BigTextStyleInformation(body);
      // Progress post — ALWAYS the low channel, under the progress id.
      final progressDetails = AndroidNotificationDetails(
        _dlChannelId,
        _dlChannelName,
        channelDescription: 'File download progress',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: pct ?? 0,
        indeterminate: pct == null,
        ongoing: true,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        styleInformation: style,
      );
      await _localNotifications.show(
        id: id,
        title: fileName,
        body: body,
        notificationDetails: NotificationDetails(android: progressDetails),
      );
      // Set.add answers true only the first time the progress id is
      // seen for this download — that first call ALSO fires the
      // one-shot start alert on the alert id / alert channel.
      if (_dlAlertPosted.add(id)) {
        const startBody = 'Downloading…';
        const alertDetails = AndroidNotificationDetails(
          _dlAlertChannelId,
          _dlAlertChannelName,
          channelDescription: 'Download start and completion alerts',
          importance: Importance.high,
          priority: Priority.high,
          showProgress: false,
          ongoing: false,
          autoCancel: true,
          styleInformation: BigTextStyleInformation(startBody),
          // NOT onlyAlertOnce: this post has to actually alert.
        );
        await _localNotifications.show(
          id: pdfDownloadAlertNotificationId,
          title: fileName,
          body: startBody,
          notificationDetails:
              const NotificationDetails(android: alertDetails),
        );
      }
    } catch (_) {}
  }

  /// Settles a download (v1.0.120; split-id design + title copy
  /// v1.0.123). FIRST cancels the progress entry under [id] so nothing
  /// can stay stuck at "Downloading… 100%" in the shade (the v1.0.122
  /// single-id design's completion post could fail to replace it),
  /// THEN posts the completion on the alert id
  /// ([pdfDownloadAlertNotificationId]), replacing the start alert:
  /// title "Download Complete 🎉" / "Download Failed ❌", body = the
  /// file name (see [downloadCompletionCopy]). Arrives like a normal
  /// notification, with sound + heads-up. When [openUri] is given (the
  /// saved file's content URI) it becomes the tap payload; the tap
  /// opens that very file.
  static Future<void> finishDownloadNotification({
    required int id,
    required String fileName,
    required bool success,
    bool toDownloads = true,
    String? openUri,
  }) async {
    _dlAlertPosted.remove(id);
    try {
      if (!Platform.isAndroid) return;
      if (!_localNotificationsReady) await _initLocalNotifications();
      if (!_localNotificationsReady) return;
      // The progress entry must disappear before the completion post.
      await _localNotifications.cancel(id: id);
      final copy = downloadCompletionCopy(
        success: success,
        fileName: fileName,
        toDownloads: toDownloads,
      );
      final androidDetails = AndroidNotificationDetails(
        _dlAlertChannelId,
        _dlAlertChannelName,
        channelDescription: 'Download start and completion alerts',
        importance: Importance.high,
        priority: Priority.high,
        showProgress: false,
        ongoing: false,
        autoCancel: true,
        // Expandable style (v1.0.122) — see showDownloadProgress.
        styleInformation: BigTextStyleInformation(copy.bigText),
      );
      await _localNotifications.show(
        id: pdfDownloadAlertNotificationId,
        title: copy.title,
        body: copy.body,
        notificationDetails: NotificationDetails(android: androidDetails),
        payload: success ? openUri : null,
      );
    } catch (_) {}
  }

  /// Dismisses a download's notifications (user cancelled): BOTH the
  /// progress entry under [id] and the start alert under
  /// [pdfDownloadAlertNotificationId] (v1.0.123).
  static Future<void> cancelDownloadNotification({required int id}) async {
    _dlAlertPosted.remove(id);
    try {
      if (!Platform.isAndroid) return;
      await _localNotifications.cancel(id: id);
      await _localNotifications.cancel(id: pdfDownloadAlertNotificationId);
    } catch (_) {}
  }

  /// Reads and clears a stashed notification tap (see
  /// [pendingNotificationIdKey]). Returns the (notificationId, deepLink);
  /// either may be null when nothing was stashed. Callers decide what to
  /// do based on auth state — the splash (cold start) and main.dart (warm
  /// tap) both use this.
  static Future<({String? id, String? deepLink})> consumePendingTap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(pendingNotificationIdKey);
      final link = prefs.getString(pendingNotificationLinkKey);
      await prefs.remove(pendingNotificationIdKey);
      await prefs.remove(pendingNotificationLinkKey);
      return (
        id: (id != null && id.isNotEmpty) ? id : null,
        deepLink: (link != null && link.isNotEmpty) ? link : null,
      );
    } catch (_) {
      return (id: null, deepLink: null);
    }
  }

  /// Stable per-device id. ANDROID_ID survives reinstalls (unlike a random
  /// UUID), so reinstalling the app updates the SAME document instead of
  /// creating a duplicate. Falls back to persisted UUID on iOS/other.
  static Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    String? id;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        // ignore: avoid_dynamic_calls
        id = (info as dynamic).id as String?;
      }
    } catch (_) {}
    if (id == null || id.isEmpty) {
      // Fallback: persisted random UUID (iOS, or ANDROID_ID unavailable).
      final prefs = await SharedPreferences.getInstance();
      id = prefs.getString(_legacyDeviceIdKey);
      if (id == null || id.isEmpty) {
        id =
            '${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 1296).toRadixString(36)}';
        await prefs.setString(_legacyDeviceIdKey, id);
      }
    }
    _deviceId = id;
    return id;
  }

  /// Human-readable device model for the Login Devices screen, e.g.
  /// "samsung SM-A546E" on Android or the utsname machine string
  /// ("iPhone9,4") on iOS. Best-effort: null when unavailable — the
  /// caller omits the field so schema-locked rules still pass.
  static Future<String?> _getDeviceModel() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final model = '${info.manufacturer} ${info.model}'.trim();
        return model.isEmpty ? null : model;
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final machine = info.utsname.machine;
        return machine.isEmpty ? null : machine;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _getLastUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUidKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setLastUid(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid == null) {
        await prefs.remove(_lastUidKey);
      } else {
        await prefs.setString(_lastUidKey, uid);
      }
    } catch (_) {}
  }

  /// Call once at app startup (after Firebase.initializeApp).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    // Request permission (no-op on older Android, required on iOS/Android 13+).
    await _messaging.requestPermission();

    // Prepare the foreground tray channel early (best-effort, non-blocking).
    _initLocalNotifications();

    // Foreground messages: the system tray does NOT show anything while
    // the app is open, so display a local notification (same title/body
    // the server sent) with the FCM data payload attached — taps route
    // through onNotificationTap exactly like background taps.
    // ALSO: any foreground push is evidence the session claim may have
    // changed (e.g. an eviction push) — trigger a throttled recheck.
    FirebaseMessaging.onMessage.listen((message) {
      DeviceSessionService.requestRecheck();
      _showForegroundNotification(message);
    });

    // Tap while app is in background.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap?.call(_stringData(message.data));
    });

    // Tap that cold-started the app from terminated state.
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        onNotificationTap?.call(_stringData(message.data));
      }
    });

    // Token refresh → re-save.
    _messaging.onTokenRefresh.listen((_) => registerToken());

    // Initial registration for current auth state.
    await registerToken();
  }

  /// Registers this device's FCM token in Firestore for the current
  /// auth state. Call on startup and whenever the uid changes.
  /// `uid` null → anonymous collection. Best-effort: never throws.
  ///
  /// NEW FLOW (v1.0.64+): User tokens carry `courseId`, `subcourseId` and
  /// `userName` so the push worker can filter by subcourse WITHOUT a
  /// batchGet — the token doc is self-contained.
  static Future<String?> registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return null;
      final uid = AuthService.currentUser?.uid;
      final deviceId = await _getDeviceId();
      final idToken = await AuthService.getValidIdToken().catchError((_) => '');
      final payload = <String, dynamic>{
        'token': token,
        'deviceId': deviceId,
        'language': AppLanguage.current.value,
        'platform': Platform.operatingSystem,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      // Human-readable device model for the Login Devices screen
      // (Security Settings). Best-effort: omitted when unavailable so the
      // schema-locked push_tokens rules (hasOnly allowlist) still pass.
      final deviceModel = await _getDeviceModel();
      if (deviceModel != null && deviceModel.isNotEmpty) {
        payload['deviceModel'] = deviceModel;
      }
      if (uid != null && uid.isNotEmpty) {
        // Logged in: attach course info so the worker can filter directly.
        final courseInfo = await _getUserCourseInfo(uid, idToken);
        payload['courseId'] = courseInfo['courseId'];
        payload['subcourseId'] = courseInfo['subcourseId'];
        payload['userName'] = courseInfo['userName'];
        await _saveForUser(uid, deviceId, payload, idToken);
      } else {
        // Signed-out: anonymous collection (merge = update in place).
        // No course info — guest has no user doc.
        await FirestoreRest.setDocument(
          'app_device_push_tokens/$deviceId',
          payload,
          idToken: idToken,
          merge: true,
        ).catchError((_) {});
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort fetch of the user's course info for the token payload.
  /// Returns empty strings when unavailable — never throws.
  static Future<Map<String, String>> _getUserCourseInfo(
    String uid,
    String idToken,
  ) async {
    try {
      final doc = await FirestoreRest.getDocument('users/$uid', idToken: idToken)
          .catchError((_) => null);
      final data = doc is Map<String, dynamic> ? doc : <String, dynamic>{};
      return {
        'courseId': '${data['courseId'] ?? ''}',
        'subcourseId': '${data['subcourseId'] ?? ''}',
        'userName': '${data['name'] ?? data['displayName'] ?? ''}',
      };
    } catch (_) {
      return {'courseId': '', 'subcourseId': '', 'userName': ''};
    }
  }

  /// Saves token for a user: cleans up old user's doc (account switch),
  /// removes guest doc, saves to new user's doc. All merge/best-effort.
  static Future<void> _saveForUser(
    String uid,
    String deviceId,
    Map<String, dynamic> payload,
    String idToken,
  ) async {
    // 1. Account switch? Remove from the previous user's collection.
    final lastUid = await _getLastUid();
    if (lastUid != null && lastUid.isNotEmpty && lastUid != uid) {
      await FirestoreRest.deleteDocument(
        'users/$lastUid/push_tokens/$deviceId',
        idToken: idToken,
      ).catchError((_) {});
    }
    // 2. Remove guest doc (no duplicate across collections).
    await FirestoreRest.deleteDocument(
      'app_device_push_tokens/$deviceId',
      idToken: idToken,
    ).catchError((_) {});
    // 3. Save to the current user's collection (merge = update in place).
    await FirestoreRest.setDocument(
      'users/$uid/push_tokens/$deviceId',
      payload,
      idToken: idToken,
      merge: true,
    ).catchError((_) {});
    // 4. Remember this uid for the next switch.
    await _setLastUid(uid);
  }

  /// Call on sign-out: remove from user collection, save as anonymous.
  /// Pass the idToken captured BEFORE the session was cleared — after logout
  /// getValidIdToken() returns empty and Firestore denies the writes.
  static Future<void> onSignOut(String uid, {String idToken = ''}) async {
    try {
      final deviceId = await _getDeviceId();
      final token = idToken.isNotEmpty
          ? idToken
          : await AuthService.getValidIdToken().catchError((_) => '');
      await FirestoreRest.deleteDocument(
        'users/$uid/push_tokens/$deviceId',
        idToken: token,
      ).catchError((_) {});
    } catch (_) {}
    await _setLastUid(null);
    await registerToken();
  }

  /// Call on sign-in: move token to the user collection.
  static Future<void> onSignIn() async {
    await registerToken();
  }
}
