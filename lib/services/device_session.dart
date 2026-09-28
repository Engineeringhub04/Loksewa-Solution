import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'firestore_rest.dart';
import 'prefs_service.dart';

/// One account = one device. Mirrors src/core/firebase/services/deviceSession.ts.
///
/// The claim lives in users/{uid}/session/active. Logging in elsewhere
/// overwrites it; the displaced phone signs itself out on next cold start.
/// A positive read naming a DIFFERENT device is the only thing that evicts —
/// doubt of any kind (offline, denied, malformed) leaves the session alone.
enum SessionVerdict { ok, evicted, skipped }

class SessionCheck {
  final SessionVerdict verdict;
  final String? deviceName;
  const SessionCheck(this.verdict, this.deviceName);
}

class DeviceSession {
  static String? _installationId;

  /// Stable per-install device id (mirrors getDeviceInstallationId).
  static Future<String> getDeviceId() async {
    if (_installationId != null) return _installationId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_installation_id');
    if (id == null) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await prefs.setString('device_installation_id', id);
    }
    _installationId = id;
    return id;
  }

  static Future<String> getDeviceName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model}'.trim();
    } catch (_) {
      return 'Android device';
    }
  }

  /// Called at login: claim the account for this device.
  static Future<void> claimSession(String uid) async {
    try {
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.setDocument(
        'users/$uid/session/active',
        {
          'deviceId': await getDeviceId(),
          'deviceName': await getDeviceName(),
          'claimedAt': FirestoreRest.serverTimestamp(),
        },
        idToken: idToken,
      );
    } catch (_) {
      // fail open — never lock anyone out
    }
  }

  /// Called on cold start (splash): check whether another device took over.
  static Future<SessionCheck> verifyDeviceSession(String uid) async {
    try {
      final idToken = await AuthService.getValidIdToken();
      final doc = await FirestoreRest.getDocument('users/$uid/session/active', idToken: idToken);
      if (doc == null) return const SessionCheck(SessionVerdict.ok, null);
      final deviceId = doc['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return const SessionCheck(SessionVerdict.ok, null);
      }
      final mine = await getDeviceId();
      if (deviceId == mine) return const SessionCheck(SessionVerdict.ok, null);
      return SessionCheck(SessionVerdict.evicted, doc['deviceName'] as String?);
    } catch (_) {
      // Doubt of any kind leaves the session alone.
      return const SessionCheck(SessionVerdict.skipped, null);
    }
  }

  /// Park the eviction notice so the login screen can explain the sign-out.
  static Future<void> markEvictionNotice(String? deviceName) async {
    if (deviceName != null) {
      await PrefsService.setString(PrefsService.evictionNotice, deviceName);
    } else {
      await PrefsService.setBool(PrefsService.evictionNotice, true);
    }
  }

  /// Consumes the parked eviction notice.
  /// Returns null when no notice was parked (login shows NO banner),
  /// '' when parked without a device name (generic banner),
  /// otherwise the other device's name.
  static Future<String?> consumeEvictionNotice() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(PrefsService.evictionNotice)) return null;
    final name = prefs.getString(PrefsService.evictionNotice);
    await prefs.remove(PrefsService.evictionNotice);
    return name ?? '';
  }
}
