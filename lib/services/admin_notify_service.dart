/// Best-effort push-notification wiring between the app and the admin desk,
/// delivered through the loksewa-push-worker Cloudflare worker
/// (https://loksewa-push-worker.loksewasolutionapi.workers.dev — the same
/// base the admin panel uses for VITE_FCM_PUSH_URL).
///
/// Two directions:
/// - [notifyAdmin]: user -> admin. A user-side event just got recorded
///   (new report, purchase request, subscription request, answer upload,
///   delete-account request) and the admin's devices should be pinged.
/// - [notifyUser]: admin -> user. The admin just approved/rejected a
///   purchase and the buyer should be pinged.
///
/// FIRE-AND-FORGET CONTRACT (strict):
/// - EVERYTHING is wrapped in try/catch and nothing ever rethrows.
/// - Each HTTP call carries a short (~8s) timeout.
/// - Callers invoke these WITHOUT awaiting them; a relay outage must
///   never block the UI or fail the underlying Firestore write.
/// - No FCM server key anywhere — the worker URL only.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class AdminNotifyService {
  /// Base URL of the push worker. Defined ONCE here — no other URL constant
  /// for it exists in the Flutter repo; the admin panel reads the same
  /// value from VITE_FCM_PUSH_URL.
  static const _workerBase =
      'https://loksewa-push-worker.loksewasolutionapi.workers.dev';

  static const _timeout = Duration(seconds: 8);

  /// Injectable HTTP client. Tests set it via [setTestClient]; production
  /// code always falls back to `http.Client()`.
  static http.Client? _testClient;

  /// Overrides the HTTP client (tests only).
  static void setTestClient(http.Client? client) => _testClient = client;

  /// Pings the admin's devices about a user-side event.
  ///
  /// POSTs to `{WORKER_URL}/notify-admin` with `{kind, title, body,
  /// deepLink?}`. Never throws — call WITHOUT awaiting.
  static Future<void> notifyAdmin({
    required String kind,
    required String title,
    required String body,
    String? deepLink,
  }) async {
    try {
      await _post(
        '$_workerBase/notify-admin',
        <String, dynamic>{
          'kind': kind,
          'title': title,
          'body': body,
          if (deepLink != null && deepLink.isNotEmpty) 'deepLink': deepLink,
        },
      );
    } catch (_) {
      // Best-effort only: the underlying Firestore write already succeeded.
    }
  }

  /// Pings one user's devices after an admin decision on their request.
  ///
  /// POSTs to `{WORKER_URL}/send-to-uid` with `{uid, title, body,
  /// deepLink?}`. Never throws — call WITHOUT awaiting.
  static Future<void> notifyUser({
    required String uid,
    required String title,
    required String body,
    String? deepLink,
  }) async {
    try {
      await _post(
        '$_workerBase/send-to-uid',
        <String, dynamic>{
          'uid': uid,
          'title': title,
          'body': body,
          if (deepLink != null && deepLink.isNotEmpty) 'deepLink': deepLink,
        },
      );
    } catch (_) {
      // Best-effort only: the admin decision was already saved.
    }
  }

  /// Shared fire-and-forget POST with a short timeout. Non-2xx responses
  /// are ignored (never rethrown); any exception (network, timeout,
  /// encoding) is swallowed by the callers.
  static Future<void> _post(String url, Map<String, dynamic> payload) async {
    final client = _testClient ?? http.Client();
    await client
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
  }
}
