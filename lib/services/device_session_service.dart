// DeviceSessionService — one account = one device.
//
// Ports src/core/firebase/services/deviceSession.ts from the React (Expo) app.
//
// Round-1 Cloudflare migration: the claim now lives server-side behind the
// loksewa-api worker (POST /auth/session/claim + GET /auth/session/check),
// whose rows name the `deviceId` that currently holds the account. Logging
// in somewhere else overwrites that claim, and the displaced phone signs
// itself out the next time it checks (splash, foreground return, or push).
// The two endpoints cannot say WHO holds the claim or when it was last
// active, so the takeover dialog now appears only when this phone had
// claimed before and lost the claim (generic device copy); a first-ever
// claim on a new phone takes over silently and the displaced phone finds
// out on its next check — the eviction half is unchanged.
//
// The push is an accelerator, never the source of truth: the new device sends
// it on its way in via the Cloudflare worker (FCM server key NEVER lives in
// the app). A device that never receives the push still finds out on its next
// foreground, route change, or cold start.
//
// Fail-open on purpose: a positive read naming a DIFFERENT device is the only
// thing that evicts. Doubt of any kind (offline, denied, malformed) leaves the
// session alone — a denied read must never lock anyone out.
//
// Admins are exempt (role == 'admin'), and the whole mechanism can be toggled
// from the admin panel ("App Setting" → "Single Device login", stored at
// meta/app_config.singleDeviceLogin). Missing config → enforced (default ON).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/auth/app_info_screen.dart';
import 'cf_api.dart';

/// Outcome of [DeviceSessionService.checkDeviceSessionForLogin].
enum LoginSessionOutcome { ok, conflict }

class DeviceSessionConflict {
  final String deviceName;
  final String platformLabel;
  final String lastActiveLabel;
  const DeviceSessionConflict({
    required this.deviceName,
    required this.platformLabel,
    required this.lastActiveLabel,
  });
}

class LoginSessionCheck {
  final LoginSessionOutcome outcome;
  final DeviceSessionConflict? existing;
  const LoginSessionCheck.ok()
      : outcome = LoginSessionOutcome.ok,
        existing = null;
  const LoginSessionCheck.conflict(this.existing)
      : outcome = LoginSessionOutcome.conflict;
}

/// Outcome of [DeviceSessionService.verifyDeviceSession].
enum SessionVerdict { ok, evicted, skipped }

class SessionCheck {
  final SessionVerdict verdict;
  final String? deviceName;
  const SessionCheck(this.verdict, this.deviceName);
}

/// Parked "you were signed out" notice for the login screen.
class EvictionNotice {
  final String? deviceName;
  final int at;
  const EvictionNotice({required this.deviceName, required this.at});
}

class DeviceSessionService {
  // ------------------------------------------------------------------ consts
  static const _evictionPushTitle = '🔐 New Sign-In Detected';
  static const _evictionNoticeKey = 'loksewa:deviceEviction:notice';
  static const _evictionNoticeMaxAgeMs = 24 * 60 * 60 * 1000;
  static const _verifyThrottleMs = 60 * 1000;
  /// The window used when the app comes back to the foreground.
  static const foregroundVerifyThrottleMs = 10 * 1000;
  static const _touchIntervalMs = 15 * 60 * 1000;
  static const _claimWindowMs = 2 * 60 * 1000;
  static const _configCacheMs = 5 * 60 * 1000;

  // ------------------------------------------------------------------- state
  static String? _deviceId;
  static int _claimDeadline = 0;
  static int _lastTouchedAt = 0;
  static int _lastVerifiedAt = 0;
  static int _configCheckedAt = 0;
  static bool? _configCached;
  static final Map<String, bool> _adminCache = {};
  static final Map<String, String> _nameCache = {};
  static final Set<void Function()> _recheckListeners = {};

  // ------------------------------------------------------------- device info
  /// Stable per-device id — ANDROID_ID survives reinstalls (mirrors
  /// PushNotificationService._getDeviceId).
  static Future<String> getDeviceId() async {
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
      final prefs = await SharedPreferences.getInstance();
      id = prefs.getString('device_installation_id');
      if (id == null || id.isEmpty) {
        id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        await prefs.setString('device_installation_id', id);
      }
    }
    _deviceId = id;
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

  // ------------------------------------------------------------ config check
  /// Whether single-device enforcement is on. Reads `singleDeviceLogin`
  /// from the API config object (GET /config); missing field → true
  /// (enforce). Cached 5 min. Fail-open: any error → true (keep enforcing;
  /// never silently disable).
  static Future<bool> isSingleDeviceEnabled() async {
    if (_configCached != null &&
        DateTime.now().millisecondsSinceEpoch - _configCheckedAt < _configCacheMs) {
      return _configCached!;
    }
    try {
      final config = await CfApi.getConfig();
      final value = config['singleDeviceLogin'];
      _configCached = value == null ? true : CfJson.asBool(value, fallback: true);
    } catch (_) {
      _configCached = true;
    }
    _configCheckedAt = DateTime.now().millisecondsSinceEpoch;
    return _configCached!;
  }

  /// Forgets cached config (call after admin changes the toggle).
  static void resetConfigCache() {
    _configCached = null;
    _configCheckedAt = 0;
  }

  // ---------------------------------------------------------- account facts
  static Future<bool> _isAdmin(String uid) async {
    final cached = _adminCache[uid];
    if (cached != null) return cached;
    try {
      // /me is the signed-in user's own profile — in practice [uid] is
      // always the current user wherever this is called.
      final me = await CfApi.getMe();
      final isAdmin = me?['role'] == 'admin';
      _adminCache[uid] = isAdmin;
      final name = me?['name']?.toString() ?? '';
      if (name.isNotEmpty) _nameCache[uid] = name;
      return isAdmin;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _userName(String uid) async {
    if (_nameCache.containsKey(uid)) return _nameCache[uid]!;
    await _isAdmin(uid); // populates name cache as a side effect
    return _nameCache[uid] ?? '';
  }

  static void resetCaches() {
    _adminCache.clear();
    _nameCache.clear();
    _configCached = null;
    _configCheckedAt = 0;
    _lastTouchedAt = 0;
    _lastVerifiedAt = 0;
    _claimDeadline = 0;
  }

  // -------------------------------------------------------------- claim I/O
  /// Local marker that THIS phone has held the claim for [uid] at least
  /// once. The CF check endpoint only answers "is this device active?" —
  /// the marker is what distinguishes "nobody claimed yet" (first opener
  /// takes it silently) from "we held it and lost it" (takeover dialog /
  /// eviction), mirroring the empty-vs-other-device distinction the old
  /// Firestore claim doc gave us.
  static const _claimedFlagPrefix = 'cf:deviceClaimed:';

  static Future<bool> _hasLocalClaim(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_claimedFlagPrefix$uid') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _setLocalClaim(String uid, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_claimedFlagPrefix$uid', value);
    } catch (_) {}
  }

  /// True when the server names THIS device as the account's active one.
  static Future<bool> _checkActive() async {
    final deviceId = await getDeviceId();
    return CfApi.sessionCheck(deviceId);
  }

  /// Claims this device server-side (also the "touch" — the worker stamps
  /// claimedAt/lastActiveAt itself) and remembers the claim locally.
  static Future<void> _writeClaim(String uid) async {
    final deviceId = await getDeviceId();
    String osVersion = '';
    try {
      osVersion = (await DeviceInfoPlugin().androidInfo).version.release;
    } catch (_) {}
    await CfApi.sessionClaim({
      'deviceId': deviceId,
      'deviceName': await getDeviceName(),
      'platform': 'android',
      'osVersion': osVersion,
      'appVersion': AppInfoScreen.appVersion,
    });
    await _setLocalClaim(uid, true);
    _lastTouchedAt = DateTime.now().millisecondsSinceEpoch;
    _lastVerifiedAt = _lastTouchedAt;
  }

  static String _formatLastActive(dynamic value) {
    int? ms;
    if (value is int) {
      ms = value;
    } else if (value is Map && value['seconds'] is int) {
      ms = (value['seconds'] as int) * 1000;
    }
    if (ms == null) return 'recently';
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 20 * 60 * 1000) return 'a few minutes ago';
    final minutes = (diff / 60000).round();
    if (minutes < 60) return 'about $minutes minutes ago';
    final hours = (minutes / 60).round();
    if (hours < 24) return 'about $hours hour${hours == 1 ? '' : 's'} ago';
    final days = (hours / 24).round();
    return '$days day${days == 1 ? '' : 's'} ago';
  }

  // -------------------------------------------------------- login-side check
  /// Runs right after a successful sign-in, before navigating.
  /// Returns `ok` when the account is free, already ours, exempt, or the
  /// feature is disabled. Returns `conflict` when another phone holds it —
  /// the caller MUST resolve with [takeOverDeviceSession] or sign out.
  static Future<LoginSessionCheck> checkDeviceSessionForLogin(String uid) async {
    try {
      if (!await isSingleDeviceEnabled()) return const LoginSessionCheck.ok();
      if (await _isAdmin(uid)) return const LoginSessionCheck.ok();

      final active = await _checkActive();
      if (active) {
        // Already ours — re-claim as a touch and go.
        await _writeClaim(uid);
        _claimDeadline = 0;
        return const LoginSessionCheck.ok();
      }

      if (await _hasLocalClaim(uid)) {
        // This phone held the account before and lost it: another device
        // holds the claim now. The CF endpoints can't name the holder or
        // its last-active time, so the dialog uses generic copy.
        // Hold the guard off while the dialog is on screen.
        _claimDeadline = DateTime.now().millisecondsSinceEpoch + _claimWindowMs;
        return const LoginSessionCheck.conflict(
          DeviceSessionConflict(
            deviceName: 'Another device',
            platformLabel: 'Android',
            lastActiveLabel: 'recently',
          ),
        );
      }

      // Never claimed from this phone (first login here, or a reinstall):
      // first opener takes the claim, mirroring the old empty-claim path.
      // A displaced holder finds out on its next verify and signs out.
      await _writeClaim(uid);
      _claimDeadline = 0;
      return const LoginSessionCheck.ok();
    } catch (_) {
      // Fail open — logging in matters more than enforcing.
      _claimDeadline = 0;
      return const LoginSessionCheck.ok();
    }
  }

  /// Confirms a takeover: this device becomes the claim holder, the displaced
  /// device is told over FCM push (via worker), and its push token row is
  /// removed so notifications follow the account. Returns false when the
  /// claim could not be written.
  static Future<bool> takeOverDeviceSession(String uid) async {
    try {
      final deviceId = await getDeviceId();
      await _writeClaim(uid);
      // Best-effort push to the displaced phone via the API's
      // eviction-push endpoint (the server fans out over the D1 token
      // registrations). The old holder's token row is not deleted here:
      // the CF endpoints don't reveal the previous device id, and the
      // row is the only address the notification has.
      await _notifyDisplacedDevice(uid, deviceId);
      _claimDeadline = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tells the displaced phone right now, over FCM via the worker.
  ///
  /// Differentiated messages (user request):
  /// - OTHER devices get the security alert ("🔐 New Sign-In Detected").
  /// - THIS device gets a confirmation ("✅ Signed In on This Device") for
  ///   the premium feel, plus an in-app toast from the caller.
  ///
  /// Phase-5: the token fan-out moved server-side — the app used to read
  /// the Firestore push_tokens rows itself, split them self/other, and
  /// POST each chunk to the old worker's /send (with a /send-to-uid
  /// broadcast fallback). Now ONE POST /device-session/eviction-push
  /// carries the uid, this device's id and the exact composed copy; the
  /// server reads the D1 token registrations, splits and sends (and
  /// owns the no-tokens fallback). No deepLink on either message — a
  /// tap must open the app normally so splash runs the session check.
  static Future<void> _notifyDisplacedDevice(
      String uid, String selfDeviceId) async {
    try {
      final name = await _userName(uid);
      final who = name.trim().isEmpty ? 'there' : name.trim();
      await CfApi.postEvictionPush({
        'uid': uid,
        'selfDeviceId': selfDeviceId,
        'userName': who,
        'alertTitle': _evictionPushTitle,
        'alertBody': evictionPushBody(who),
        'confirmTitle': '✅ Signed In on This Device',
        'confirmBody': takeOverConfirmBody(who),
        'fallbackBody':
            'Hi $who, you were signed in on another device. Open the app.',
      });
    } catch (_) {}
  }

  /// Security-alert body for the DISPLACED device.
  @visibleForTesting
  static String evictionPushBody(String who) =>
      'Hi $who, your account was just signed in on another device.';

  /// Confirmation body for the NEW device (this phone).
  @visibleForTesting
  static String takeOverConfirmBody(String who) =>
      'Hi $who, this device is now your active login. Your other device has been signed out.';

  // ------------------------------------------------------- displaced-device
  /// True while a login screen is showing the takeover dialog.
  static bool isClaimInProgress() =>
      DateTime.now().millisecondsSinceEpoch < _claimDeadline;

  /// The displaced device's check: called on cold start, foreground return,
  /// route changes, and push-triggered rechecks. `evicted` is returned ONLY
  /// on a positive read naming a different device — never on error.
  static Future<SessionCheck> verifyDeviceSession(
    String uid, {
    int? throttleMs,
  }) async {
    if (isClaimInProgress()) return const SessionCheck(SessionVerdict.skipped, null);
    final throttle = throttleMs ?? _verifyThrottleMs;
    if (DateTime.now().millisecondsSinceEpoch - _lastVerifiedAt < throttle) {
      return const SessionCheck(SessionVerdict.skipped, null);
    }
    try {
      if (!await isSingleDeviceEnabled()) {
        return const SessionCheck(SessionVerdict.skipped, null);
      }
      if (await _isAdmin(uid)) {
        return const SessionCheck(SessionVerdict.skipped, null);
      }
      final active = await _checkActive();
      if (!active) {
        if (!await _hasLocalClaim(uid)) {
          // Never claimed from this phone (pre-feature account, reinstall,
          // or a claim that failed to write) — first opener takes it.
          await _writeClaim(uid);
          return const SessionCheck(SessionVerdict.ok, null);
        }
        // We held the claim and lost it: another device took the account.
        // The CF endpoints don't reveal the holder's name — the eviction
        // notice shows its generic copy.
        return const SessionCheck(SessionVerdict.evicted, null);
      }
      // Ours: touch the claim (throttled, best-effort) so lastActiveAt and
      // the local-claim marker stay fresh.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastTouchedAt >= _touchIntervalMs) {
        _lastTouchedAt = now;
        await _writeClaim(uid).catchError((_) {});
      }
      _lastVerifiedAt = now;
      return const SessionCheck(SessionVerdict.ok, null);
    } catch (_) {
      return const SessionCheck(SessionVerdict.skipped, null);
    }
  }

  /// Drops this device's claim marker on deliberate sign-out. The CF API
  /// has no "unclaim" endpoint this round, so the server-side claim row
  /// keeps naming this device until another login overwrites it — only
  /// the local marker is cleared, which is also what stops a later
  /// sign-out on a displaced phone from mattering (it holds no marker).
  static Future<void> releaseDeviceSession(String uid) async {
    await _setLocalClaim(uid, false);
  }

  // ------------------------------------------------------- eviction notices
  static Future<void> markEvictionNotice(String? deviceName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'deviceName': deviceName,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString(_evictionNoticeKey, payload);
    } catch (_) {}
  }

  /// Reads and REMOVES the parked notice (shows exactly once). Null when
  /// none parked or expired (>24h).
  static Future<EvictionNotice?> consumeEvictionNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_evictionNoticeKey);
      if (raw == null) return null;
      await prefs.remove(_evictionNoticeKey);
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final at = (parsed['at'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > _evictionNoticeMaxAgeMs) {
        return null;
      }
      return EvictionNotice(
          deviceName: parsed['deviceName']?.toString(), at: at);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearEvictionNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_evictionNoticeKey);
    } catch (_) {}
  }

  // ------------------------------------------------------- recheck channel
  /// Listeners wanting "check the claim RIGHT NOW" (push arrival, etc.).
  static void onRecheck(void Function() listener) {
    _recheckListeners.add(listener);
  }

  static void offRecheck(void Function() listener) {
    _recheckListeners.remove(listener);
  }

  static void requestRecheck() {
    for (final l in List.of(_recheckListeners)) {
      try {
        l();
      } catch (_) {}
    }
  }

  // ------------------------------------------------------- pure-logic hooks
  /// Formats last-active label — exposed for unit tests.
  static String formatLastActiveForTest(dynamic value) => _formatLastActive(value);

  /// Builds the eviction push body — exposed for unit tests.
  static String evictionPushBodyForTest(String name) {
    final who = name.trim().isEmpty ? 'there' : name.trim();
    return 'Hi $who, you were signed in on another device. Open the app.';
  }
}
