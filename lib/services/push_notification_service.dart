// Push notification service — FCM version of the React app's
// pushNotifications.ts. Same Firestore structure:
//   - Signed-in:  users/{uid}/push_tokens/{deviceId}
//   - Signed-out: app_device_push_tokens/{deviceId}
// Tokens move between the two on login/logout (never duplicated).
// The admin website reads these paths and sends via FCM API.
import 'dart:io';

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

  /// Callback for notification taps — set by the router layer.
  static void Function(String? deepLink)? onNotificationTap;

  /// Stable per-install device id for token keying
  /// (mirrors getDeviceInstallationId in the React app).
  static Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    const key = 'push_device_id';
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(key);
    if (id == null || id.isEmpty) {
      id =
          '${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 1296).toRadixString(36)}';
      await prefs.setString(key, id);
    }
    _deviceId = id;
    return id;
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
        // Signed-in: save under user, clean up anonymous row.
        await FirestoreRest.setDocument(
          'users/$uid/push_tokens/$deviceId',
          payload,
          idToken: idToken,
          merge: true,
        ).catchError((_) {});
        await FirestoreRest.deleteDocument(
          'app_device_push_tokens/$deviceId',
          idToken: idToken,
        ).catchError((_) {});
      } else {
        // Signed-out: anonymous collection.
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
    await registerToken();
  }

  /// Call on sign-in: move token to the user collection.
  static Future<void> onSignIn() async {
    await registerToken();
  }
}
