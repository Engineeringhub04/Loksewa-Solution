// Push notification service — FCM version of the React app's
// pushNotifications.ts. Same Firestore structure:
//   - Signed-in:  users/{uid}/push_tokens/{deviceId}
//   - Signed-out: app_device_push_tokens/{deviceId}
//
// STABLE DEVICE ID (v1.0.60+): Uses ANDROID_ID which survives reinstalls,
// so one physical device = one document. No duplicates on reinstall.
// Account switches clean up the old user's token via last_uid tracking.
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'firestore_rest.dart';
import 'app_language.dart';

/// Background message handler — must be top-level.
/// The system tray shows the notification automatically.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;
  static String? _deviceId;

  static const _lastUidKey = 'push_last_uid';
  static const _legacyDeviceIdKey = 'push_device_id';

  /// Callback for notification taps — set by the router layer.
  static void Function(String? deepLink)? onNotificationTap;

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

    // Foreground messages: nothing to show manually — the inbox screen
    // already displays them; tray push is for background/terminated.
    FirebaseMessaging.onMessage.listen((_) {});

    // Tap while app is in background.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap?.call(message.data['deepLink'] as String?);
    });

    // Tap that cold-started the app from terminated state.
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        onNotificationTap?.call(message.data['deepLink'] as String?);
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
      if (uid != null && uid.isNotEmpty) {
        await _saveForUser(uid, deviceId, payload, idToken);
      } else {
        // Signed-out: anonymous collection (merge = update in place).
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
  static Future<void> onSignOut(String uid) async {
    try {
      final deviceId = await _getDeviceId();
      final idToken = await AuthService.getValidIdToken().catchError((_) => '');
      await FirestoreRest.deleteDocument(
        'users/$uid/push_tokens/$deviceId',
        idToken: idToken,
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
