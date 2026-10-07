// DeviceSessionService — one account = one device.
//
// Ports src/core/firebase/services/deviceSession.ts from the React (Expo) app.
//
// The claim lives in a single document — users/{uid}/session/active — whose
// `deviceId` names the phone that currently holds the account. Logging in
// somewhere else overwrites that document, and the displaced phone signs
// itself out the next time it checks (splash, foreground return, or push).
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
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'firestore_rest.dart';

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
  static const _workerBase = 'https://loksewa-push-worker.loksewasolutionapi.workers.dev';
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
  /// Whether single-device enforcement is on. Reads meta/app_config
  /// `singleDeviceLogin`; missing doc/field → true (enforce). Cached 5 min.
  /// Fail-open: any error → true (keep enforcing; never silently disable).
  static Future<bool> isSingleDeviceEnabled() async {
    if (_configCached != null &&
        DateTime.now().millisecondsSinceEpoch - _configCheckedAt < _configCacheMs) {
      return _configCached!;
    }
    try {
      final idToken = await AuthService.getValidIdToken().catchError((_) => '');
      final doc = await FirestoreRest.getDocument('meta/app_config', idToken: idToken);
      final value = doc?['singleDeviceLogin'];
      _configCached = value is bool ? value : true;
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
      final idToken = await AuthService.getValidIdToken().catchError((_) => '');
      final doc = await FirestoreRest.getDocument('users/$uid', idToken: idToken);
      final isAdmin = doc?['role'] == 'admin';
      _adminCache[uid] = isAdmin;
      final name = doc?['name']?.toString() ?? '';
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
  static String _sessionPath(String uid) => 'users/$uid/session/active';

  static Future<Map<String, dynamic>?> _readActiveSession(String uid) async {
    final idToken = await AuthService.getValidIdToken().catchError((_) => '');
    return FirestoreRest.getDocument(_sessionPath(uid), idToken: idToken);
  }

  static Future<void> _writeClaim(String uid) async {
    final idToken = await AuthService.getValidIdToken().catchError((_) => '');
    final deviceId = await getDeviceId();
    String osVersion = '';
    try {
      osVersion = (await DeviceInfoPlugin().androidInfo).version.release;
    } catch (_) {}
    await FirestoreRest.setDocument(
      _sessionPath(uid),
      {
        'deviceId': deviceId,
        'deviceName': await getDeviceName(),
        'platform': 'android',
        'osVersion': osVersion,
        'claimedAt': FirestoreRest.serverTimestampValue(),
        'lastActiveAt': FirestoreRest.serverTimestampValue(),
      },
      idToken: idToken,
    );
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

      final results = await Future.wait([_readActiveSession(uid), getDeviceId()]);
      final record = results[0] as Map<String, dynamic>?;
      final deviceId = results[1] as String;
      final claimedBy = record?['deviceId']?.toString() ?? '';
      if (claimedBy.isEmpty || claimedBy == deviceId) {
        await _writeClaim(uid);
        _claimDeadline = 0;
        return const LoginSessionCheck.ok();
      }

      // Hold the guard off while the dialog is on screen.
      _claimDeadline = DateTime.now().millisecondsSinceEpoch + _claimWindowMs;
      return LoginSessionCheck.conflict(
        DeviceSessionConflict(
          deviceName: record?['deviceName']?.toString().isNotEmpty == true
              ? record!['deviceName'].toString()
              : 'Another device',
          platformLabel: 'Android',
          lastActiveLabel: _formatLastActive(record?['lastActiveAt']),
        ),
      );
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
      final previous = await _readActiveSession(uid).catchError((_) => null);
      final deviceId = await getDeviceId();
      await _writeClaim(uid);
      // Notify BEFORE deleting the token row — the row is the only address
      // we have for the displaced phone. AWAITED: the delete below must not
      // win the race, or no push ever reaches the old device.
      await _notifyDisplacedDevice(uid, deviceId);
      final prevId = previous?['deviceId']?.toString() ?? '';
      if (prevId.isNotEmpty && prevId != deviceId) {
        final idToken = await AuthService.getValidIdToken().catchError((_) => '');
        await FirestoreRest.deleteDocument('users/$uid/push_tokens/$prevId',
                idToken: idToken)
            .catchError((_) {});
      }
      _claimDeadline = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tells the displaced phone right now, over FCM via the Cloudflare worker.
  ///
  /// MUST be awaited by the caller BEFORE deleting the old token row — the
  /// row is the only address we have for the displaced phone. (Race fix:
  /// fire-and-forget let the delete win, so no push ever reached the old
  /// device.)
  ///
  /// Differentiated messages (user request):
  /// - OTHER devices get the security alert ("🔐 New Sign-In Detected").
  /// - THIS device gets a confirmation ("✅ Signed In on This Device") for
  ///   the premium feel, plus an in-app toast from the caller.
  /// Falls back to the old /send-to-uid broadcast if the token read fails.
  static Future<void> _notifyDisplacedDevice(
      String uid, String selfDeviceId) async {
    try {
        final name = await _userName(uid);
        final who = name.trim().isEmpty ? 'there' : name.trim();
        final idToken =
            await AuthService.getValidIdToken().catchError((_) => '');
        List<Map<String, dynamic>> tokenDocs = [];
        try {
          tokenDocs = await FirestoreRest.listDocuments(
            'users/$uid/push_tokens',
            idToken: idToken,
            pageSize: 100,
          );
        } catch (_) {
          // Fall through to the legacy broadcast below.
        }
        if (tokenDocs.isEmpty) {
          await _sendToUid(uid, _evictionPushTitle,
              'Hi $who, you were signed in on another device. Open the app.');
          return;
        }
        final otherTokens = <String>[];
        final selfTokens = <String>[];
        for (final d in tokenDocs) {
          final token = d['token']?.toString() ?? '';
          if (token.isEmpty) continue;
          final did = (d['deviceId']?.toString() ?? d['id']?.toString() ?? '');
          if (did == selfDeviceId) {
            selfTokens.add(token);
          } else {
            otherTokens.add(token);
          }
        }
        // 1. Displaced devices → security alert.
        if (otherTokens.isNotEmpty) {
          await _sendToTokens(
            otherTokens,
            _evictionPushTitle,
            evictionPushBody(who),
          );
        }
        // 2. This device → confirmation (premium feel). No deepLink — tap
        // opens the app normally.
        if (selfTokens.isNotEmpty) {
          await _sendToTokens(
            selfTokens,
            '✅ Signed In on This Device',
            takeOverConfirmBody(who),
          );
        }
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

  /// POSTs to {worker}/send with an explicit token list (500/chunk).
  static Future<void> _sendToTokens(
      List<String> tokens, String title, String body) async {
    for (var i = 0; i < tokens.length; i += 500) {
      final chunk = tokens.sublist(
          i, i + 500 > tokens.length ? tokens.length : i + 500);
      try {
        await http
            .post(
              Uri.parse('$_workerBase/send'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'tokens': chunk,
                'title': title,
                'body': body,
                // No deepLink on purpose — tap must open the app normally so
                // splash runs the session check on its way to login.
              }),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
  }

  /// Legacy fallback: broadcast via /send-to-uid (worker fans out itself).
  static Future<void> _sendToUid(String uid, String title, String body) async {
    try {
      await http
          .post(
            Uri.parse('$_workerBase/send-to-uid'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'uid': uid, 'title': title, 'body': body}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

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
      final results = await Future.wait([_readActiveSession(uid), getDeviceId()]);
      final record = results[0] as Map<String, dynamic>?;
      final deviceId = results[1] as String;
      final claimedBy = record?['deviceId']?.toString() ?? '';
      if (claimedBy.isEmpty) {
        // Never claimed (e.g. pre-feature account) — first opener takes it.
        await _writeClaim(uid);
        return const SessionCheck(SessionVerdict.ok, null);
      }
      if (claimedBy != deviceId) {
        return SessionCheck(SessionVerdict.evicted,
            record?['deviceName']?.toString());
      }
      // Touch lastActiveAt (throttled, best-effort).
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastTouchedAt >= _touchIntervalMs) {
        _lastTouchedAt = now;
        final idToken = await AuthService.getValidIdToken().catchError((_) => '');
        await FirestoreRest.setDocument(
          _sessionPath(uid),
          {
            'deviceId': deviceId,
            'lastActiveAt': FirestoreRest.serverTimestampValue(),
          },
          idToken: idToken,
        ).catchError((_) {});
      }
      _lastVerifiedAt = now;
      return const SessionCheck(SessionVerdict.ok, null);
    } catch (_) {
      return const SessionCheck(SessionVerdict.skipped, null);
    }
  }

  /// Drops this device's claim on deliberate sign-out — only when it still
  /// names THIS device, so a displaced phone never wipes the new holder.
  static Future<void> releaseDeviceSession(String uid) async {
    try {
      final results = await Future.wait([_readActiveSession(uid), getDeviceId()]);
      final record = results[0] as Map<String, dynamic>?;
      final deviceId = results[1] as String;
      if (record?['deviceId']?.toString() != deviceId) return;
      final idToken = await AuthService.getValidIdToken().catchError((_) => '');
      await FirestoreRest.deleteDocument(_sessionPath(uid), idToken: idToken)
          .catchError((_) {});
    } catch (_) {}
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
