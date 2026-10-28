import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'prefs_service.dart';

/// Cloudflare backend client (worker `loksewa-api`) — Round-1 migration.
///
/// The five migrated areas (auth, splash config, onboarding, course setup,
/// home data) talk to this client; everything else still uses the Firebase
/// REST layer. Responses are PLAIN JSON (never Firestore typed values), but
/// rows originate from the Firestore→D1 copy, so scalar fields may arrive as
/// strings ('true', '58', JSON-encoded lists/maps). All reads below decode
/// defensively — see [CfJson] and [CfApi.decodeFieldValue].
///
/// Session: one JSON blob in SharedPreferences under [sessionPrefsKey]
/// (access token + refresh token + user + optional access expiry). An
/// expired access token is refreshed ONCE per request on a 401 and the
/// request retried; the saved blob is never deleted by a read.

/// Server-side failure: [error] is the worker's error string verbatim
/// (e.g. 'needs_claim', 'wrong_password'), [statusCode] the HTTP status.
class CfError implements Exception {
  final String error;
  final int statusCode;
  const CfError(this.error, [this.statusCode = 0]);
  @override
  String toString() => 'CfError($statusCode, $error)';
}

/// Transport failure (no response at all). Kept distinct from [CfError] so
/// callers can keep showing their existing "network error" copy.
class CfNetworkError implements Exception {
  final Object cause;
  const CfNetworkError(this.cause);
  @override
  String toString() => 'CfNetworkError($cause)';
}

/// The authenticated user as the CF API returns it (`name`, not
/// `displayName` — AuthService converts).
class CfUser {
  final String uid;
  final String? email;
  final String? name;
  final String? photoURL;

  const CfUser({required this.uid, this.email, this.name, this.photoURL});

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'name': name,
        'photoURL': photoURL,
      };

  factory CfUser.fromJson(Map<String, dynamic> json) => CfUser(
        uid: '${json['uid'] ?? json['id'] ?? ''}',
        email: json['email'] as String?,
        name: (json['name'] ?? json['displayName']) as String?,
        photoURL: (json['photoURL'] ?? json['photoUrl']) as String?,
      );
}

/// Tokens + user returned by the /auth/* success responses.
class CfAuthResult {
  final CfUser user;
  final String accessToken;
  final String refreshToken;
  final bool isNewUser;

  const CfAuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.isNewUser = false,
  });
}

class _CfSession {
  final CfUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime? accessExpiresAt;

  const _CfSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.accessExpiresAt,
  });

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        if (accessExpiresAt != null)
          'accessExpiresAt': accessExpiresAt!.toIso8601String(),
      };

  factory _CfSession.fromJson(Map<String, dynamic> json) => _CfSession(
        user: CfUser.fromJson(
            (json['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
        accessToken: '${json['accessToken'] ?? ''}',
        refreshToken: '${json['refreshToken'] ?? ''}',
        accessExpiresAt: json['accessExpiresAt'] is String
            ? DateTime.tryParse(json['accessExpiresAt'] as String)
            : null,
      );
}

/// Defensive coercions for values that crossed the Firestore→D1 copy, where
/// booleans/numbers/timestamps may be stored as text.
class CfJson {
  static bool asBool(dynamic v, {bool fallback = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return fallback;
  }

  static int asInt(dynamic v, {int fallback = 0}) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? fallback;
  }

  static DateTime? asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is num) {
      // Seconds vs milliseconds: Firestore seconds are ~1.7e9, ms ~1.7e12.
      final n = v.toInt();
      return DateTime.fromMillisecondsSinceEpoch(n < 100000000000 ? n * 1000 : n);
    }
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
      final n = int.tryParse(v);
      if (n != null) return asDateTime(n);
      return null;
    }
    if (v is Map) {
      final seconds = v['seconds'] ?? v['_seconds'];
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).toInt());
      }
      final ts = v['timestampValue'] ?? v['_timestamp'];
      if (ts != null) return asDateTime(ts);
    }
    return null;
  }
}

class CfApi {
  static const baseUrl =
      'https://loksewa-api.loksewa-solution-api.workers.dev';
  static const sessionPrefsKey = 'cf_session';
  static const _timeout = Duration(seconds: 15);

  // ------------------------------------------------------------ test seam
  static http.Client? _testClient;

  /// Overrides the HTTP client (tests only) — same pattern as
  /// PasswordResetService.setTestClient.
  static void setTestClient(http.Client? client) => _testClient = client;

  static http.Client? _sharedClient;
  static Zone? _sharedClientZone;

  static http.Client get _client {
    if (_testClient != null) return _testClient!;
    // Zone-aware shared client (same reasoning as ExamRest): a client made
    // inside a test's runWithClient zone stays bound to that zone's factory.
    if (_sharedClient == null || _sharedClientZone != Zone.current) {
      _sharedClient = http.Client();
      _sharedClientZone = Zone.current;
    }
    return _sharedClient!;
  }

  // -------------------------------------------------------------- session
  static _CfSession? _session;

  static CfUser? get currentUser => _session?.user;
  static bool get hasSession => _session != null;

  static Future<void> _persist() async {
    final s = _session;
    if (s == null) return;
    await PrefsService.setString(sessionPrefsKey, json.encode(s.toJson()));
  }

  /// Installs an auth result as the active session and persists it.
  static Future<void> storeAuthResult(CfAuthResult result) async {
    _session = _CfSession(
      user: result.user,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await _persist();
  }

  /// Reads the saved CF session from disk WITHOUT any network call and
  /// installs it in memory. Never deletes the blob (a corrupt blob returns
  /// null and stays on disk — same contract as the legacy session peek).
  static Future<CfUser?> loadSavedUser() async {
    try {
      final raw = await PrefsService.getString(sessionPrefsKey);
      if (raw == null) return null;
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      _session = _CfSession.fromJson(decoded.cast<String, dynamic>());
      if (_session!.user.uid.isEmpty) {
        _session = null;
        return null;
      }
      return _session!.user;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    _session = null;
    await PrefsService.remove(sessionPrefsKey);
  }

  /// Merges [fields] into the persisted user (keys are CfUser JSON keys:
  /// 'name', 'photoURL', 'email'). No-op without a session.
  static Future<void> patchStoredUser(Map<String, dynamic> fields) async {
    final s = _session;
    if (s == null) return;
    final merged = s.user.toJson()..addAll(fields);
    _session = _CfSession(
      user: CfUser.fromJson(merged),
      accessToken: s.accessToken,
      refreshToken: s.refreshToken,
      accessExpiresAt: s.accessExpiresAt,
    );
    await _persist();
  }

  // ------------------------------------------------------------ transport
  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool retried = false,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && _session != null && _session!.accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_session!.accessToken}';
    }
    final http.Response res;
    try {
      final uri = Uri.parse('$baseUrl$path');
      final client = _client;
      res = await switch (method) {
        'GET' => client.get(uri, headers: headers).timeout(_timeout),
        'POST' => client
            .post(uri, headers: headers, body: json.encode(body ?? {}))
            .timeout(_timeout),
        'PATCH' => client
            .patch(uri, headers: headers, body: json.encode(body ?? {}))
            .timeout(_timeout),
        _ => throw ArgumentError('unsupported method $method'),
      };
    } catch (e) {
      throw CfNetworkError(e);
    }
    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = json.decode(res.body);
      } catch (_) {
        decoded = null;
      }
    }
    if (res.statusCode == 401 && auth && !retried && _session != null) {
      // One-shot refresh, then retry the original request exactly once.
      if (await _tryRefresh()) {
        return _request(method, path, body: body, auth: auth, retried: true);
      }
      throw const CfError('session_expired', 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CfError(_errorString(decoded), res.statusCode);
    }
    // Some worker handlers answer 200 with {ok:false, error} — treat that
    // as the failure it is.
    if (decoded is Map && decoded['ok'] == false && decoded['error'] != null) {
      throw CfError('${decoded['error']}', res.statusCode);
    }
    return decoded;
  }

  static String _errorString(dynamic decoded) {
    if (decoded is Map) {
      final e = decoded['error'] ?? decoded['message'] ?? decoded['code'];
      if (e != null) return '$e';
    }
    return 'unknown_error';
  }

  /// Exchanges the refresh token for a new token pair. False on any failure
  /// (the saved session is left untouched either way).
  static Future<bool> _tryRefresh() async {
    final refreshToken = _session?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final decoded = await _request(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
        auth: false,
      );
      final m = _asMap(decoded);
      final access = '${m['accessToken'] ?? ''}';
      if (access.isEmpty) return false;
      final s = _session!;
      _session = _CfSession(
        user: s.user,
        accessToken: access,
        refreshToken: '${m['refreshToken'] ?? refreshToken}',
        accessExpiresAt: s.accessExpiresAt,
      );
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------- helpers
  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  /// Decodes a stringified JSON value ('[...]' / '{...}') back into its
  /// List/Map — D1 rows can carry Firestore JSON fields as text. Anything
  /// else passes through unchanged.
  static dynamic decodeFieldValue(dynamic v) {
    if (v is String) {
      final t = v.trim();
      if ((t.startsWith('[') && t.endsWith(']')) ||
          (t.startsWith('{') && t.endsWith('}'))) {
        try {
          return json.decode(t);
        } catch (_) {
          return v;
        }
      }
    }
    return v;
  }

  static Map<String, dynamic> normalizeRow(Map<String, dynamic> row) =>
      row.map((k, v) => MapEntry(k, decodeFieldValue(v)));

  /// Extracts a row list from a decoded body: the body itself when it is a
  /// list, else the first List found under [keys]. Rows are normalized.
  static List<Map<String, dynamic>> _rows(dynamic body, List<String> keys) {
    dynamic v = body;
    if (v is Map) {
      for (final k in keys) {
        if (v[k] is List) {
          v = v[k];
          break;
        }
      }
    }
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => normalizeRow(e.cast<String, dynamic>()))
          .toList();
    }
    return [];
  }

  static CfAuthResult _authResult(dynamic body) {
    final m = _asMap(body);
    return CfAuthResult(
      user: CfUser.fromJson(_asMap(m['user'])),
      accessToken: '${m['accessToken'] ?? ''}',
      refreshToken: '${m['refreshToken'] ?? ''}',
      isNewUser: CfJson.asBool(m['isNewUser']),
    );
  }

  // ----------------------------------------------------------------- auth
  static Future<CfAuthResult> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    final body = await _request('POST', '/auth/signup', auth: false, body: {
      'name': name,
      'email': email,
      'password': password,
    });
    final result = _authResult(body);
    await storeAuthResult(result);
    return result;
  }

  static Future<CfAuthResult> login({
    required String email,
    required String password,
  }) async {
    final body = await _request('POST', '/auth/login', auth: false, body: {
      'email': email,
      'password': password,
    });
    final result = _authResult(body);
    await storeAuthResult(result);
    return result;
  }

  /// Google sign-in. With [store] false the session is NOT installed — the
  /// caller (AuthService) inspects isNewUser first (login screen forbids
  /// account creation) and stores the result itself when allowed.
  static Future<CfAuthResult> google(
    String idToken, {
    bool allowCreate = true,
    bool store = true,
  }) async {
    final body = await _request('POST', '/auth/google', auth: false, body: {
      'idToken': idToken,
      'allowCreate': allowCreate,
    });
    final result = _authResult(body);
    if (store) await storeAuthResult(result);
    return result;
  }

  /// NOTE-11 claim flow, step 1: ask for the 6-digit code. The worker
  /// answers {ok:true} whether or not the email exists.
  static Future<void> claimRequest(String email) async {
    await _request('POST', '/auth/claim/request',
        auth: false, body: {'email': email});
  }

  /// NOTE-11 claim flow, step 2: verify the code, set the password, and
  /// log in (the returned session is stored).
  static Future<CfAuthResult> claimVerify({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final body = await _request('POST', '/auth/claim/verify', auth: false,
        body: {'email': email, 'code': code, 'newPassword': newPassword});
    final result = _authResult(body);
    await storeAuthResult(result);
    return result;
  }

  /// Forgot-password (code flow), step 1.
  static Future<void> resetRequest(String email) async {
    await _request('POST', '/auth/reset/request',
        auth: false, body: {'email': email});
  }

  /// Forgot-password (code flow), step 2. No auto-login.
  static Future<void> resetVerify({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _request('POST', '/auth/reset/verify', auth: false,
        body: {'email': email, 'code': code, 'newPassword': newPassword});
  }

  // --------------------------------------------------------- device claim
  /// Claims this device as the account's active device (Bearer).
  static Future<void> sessionClaim(Map<String, dynamic> body) async {
    await _request('POST', '/auth/session/claim', body: body);
  }

  /// Whether [deviceId] is the account's active device (Bearer).
  static Future<bool> sessionCheck(String deviceId) async {
    final body = await _request('GET',
        '/auth/session/check?deviceId=${Uri.encodeComponent(deviceId)}');
    return CfJson.asBool(_asMap(body)['active']);
  }

  // ----------------------------------------------------------------- data
  /// meta/appConfig object (maintenance flags, global-notification copy…).
  static Future<Map<String, dynamic>> getConfig() async {
    final body = await _request('GET', '/config');
    final m = _asMap(body);
    for (final k in ['config', 'appConfig', 'data']) {
      if (m[k] is Map) return normalizeRow(_asMap(m[k]));
    }
    return normalizeRow(m);
  }

  /// Onboarding slide rows (may be empty → callers keep local slides).
  static Future<List<Map<String, dynamic>>> getOnboarding() async {
    final body = await _request('GET', '/onboarding');
    return _rows(body, ['slides', 'onboarding', 'items', 'data']);
  }

  /// Course + subcourse rows for the setup screen / name resolution.
  static Future<({List<Map<String, dynamic>> courses, List<Map<String, dynamic>> subcourses})>
      getCourses() async {
    final body = await _request('GET', '/courses');
    return (
      courses: _rows(body, ['courses']),
      subcourses: _rows(body, ['subcourses', 'subCourses']),
    );
  }

  /// Notice rows (latest 30 server-side; callers still filter/sort).
  static Future<List<Map<String, dynamic>>> getNotices() async {
    final body = await _request('GET', '/notices');
    return _rows(body, ['notices', 'items', 'data']);
  }

  /// Home banner rows.
  static Future<List<Map<String, dynamic>>> getBanners() async {
    final body = await _request('GET', '/banners');
    return _rows(body, ['banners', 'items', 'data']);
  }

  /// Today's QOTD bundle for the signed-in user: question doc + result +
  /// summary + greetings, in whatever envelope the worker chose — callers
  /// unwrap defensively.
  static Future<Map<String, dynamic>> getQotd({
    required String dateKey,
    required String courseId,
    required String subcourseId,
  }) async {
    final q = Uri(queryParameters: {
      'dateKey': dateKey,
      'courseId': courseId,
      'subcourseId': subcourseId,
    }).query;
    final body = await _request('GET', '/qotd?$q');
    return _asMap(body);
  }

  /// Exam-set durations (minutes) keyed by set id, for badge expiry.
  static Future<Map<String, int>> getExamDurations() async {
    final body = await _request('GET', '/exam-durations');
    final out = <String, int>{};
    final m = _asMap(body);
    final nested = m['durations'] ?? m['examDurations'];
    if (nested is Map) {
      nested.forEach((k, v) => out['$k'] = CfJson.asInt(v, fallback: 60));
      return out;
    }
    if (body is List) {
      for (final row in body.whereType<Map>()) {
        final id = row['id'] ?? row['setId'] ?? row['examSetId'];
        if (id != null) {
          out['$id'] =
              CfJson.asInt(row['durationMinutes'] ?? row['duration'], fallback: 60);
        }
      }
      return out;
    }
    // A bare {setId: minutes} object.
    m.forEach((k, v) {
      if (v is num || v is String) out[k] = CfJson.asInt(v, fallback: 60);
    });
    return out;
  }

  // -------------------------------------------------------------- profile
  /// The signed-in user's profile (users row). Null when the worker has
  /// no row (404) — transport/server errors still throw.
  static Future<Map<String, dynamic>?> getMe() async {
    try {
      final body = await _request('GET', '/me');
      final m = _asMap(body);
      for (final k in ['user', 'profile', 'data']) {
        if (m[k] is Map) return normalizeRow(_asMap(m[k]));
      }
      return normalizeRow(m);
    } on CfError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Merges [fields] into the signed-in user's profile.
  static Future<void> patchMe(Map<String, dynamic> fields) async {
    await _request('PATCH', '/me', body: fields);
  }
}
