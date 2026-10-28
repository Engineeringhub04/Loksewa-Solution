import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cf_api.dart';

/// Client for the loksewa-api worker's /payments endpoints.
///
/// Security model: the worker holds every gateway secret (merchant secret
/// keys, HMAC signing). The app only ever receives *signed init payloads*
/// and forwards the gateway's proof back for server-side verification.
/// A faked "payment success" inside the app can never activate a
/// subscription — only the worker's server-to-server verification can.
///
/// Phase-5: the payments module moved from the old push worker to
/// loksewa-api, and every call now carries the CF access token (Bearer)
/// instead of the Firebase ID token. Payload/response shapes unchanged.
class GatewayPaymentService {
  static String get _base => CfApi.baseUrl;

  /// Injectable HTTP client. Tests set it via [setTestClient]; production
  /// code always falls back to `http.Client()`.
  static http.Client? _testClient;

  /// Overrides the HTTP client (tests only).
  static void setTestClient(http.Client? client) => _testClient = client;

  static Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) {
    final client = _testClient ?? http.Client();
    return client
        .post(
          Uri.parse('$_base$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${CfApi.accessToken}',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
  }

  /// Ask the worker to initiate a gateway payment.
  ///
  /// [purchaseType] is 'subscription' (default), 'exam' or 'content'.
  /// For 'exam', [itemId] is the exam set id; for 'content' it is the
  /// content id (+ [contentType]/[contentUnitId]). The worker reads the
  /// real price server-side — the app never sends an amount.
  /// Coupons are subscription-only: [couponCode] is only sent for
  /// subscriptions (the worker rejects it for exam/content).
  ///
  /// Returns the worker payload, e.g.:
  /// ```json
  /// {
  ///   "ok": true, "gateway": "esewa", "testMode": true,
  ///   "transactionUuid": "...", "purchaseType": "exam",
  ///   "esewa": {"endpoint": "https://...", "fields": {"amount": "...", ...}},
  ///   "khalti": {"pidx": "...", "paymentUrl": "...", "publicKey": "..."}
  /// }
  /// ```
  static Future<Map<String, dynamic>> initPayment({
    required String gateway, // 'esewa' | 'khalti'
    String purchaseType = 'subscription',
    String? planId,
    String? itemId,
    String? contentType,
    String? contentUnitId,
    String? couponCode,
  }) async {
    final res = await _post(
      '/payments/init',
      {
        'gateway': gateway,
        'purchaseType': purchaseType,
        if (planId != null && planId.isNotEmpty) 'planId': planId,
        if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
        if (contentType != null && contentType.isNotEmpty)
          'contentType': contentType,
        if (contentUnitId != null && contentUnitId.isNotEmpty)
          'contentUnitId': contentUnitId,
        if (purchaseType == 'subscription' &&
            couponCode != null &&
            couponCode.trim().isNotEmpty)
          'couponCode': couponCode.trim(),
      },
      timeout: const Duration(seconds: 30),
    );
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = {};
    }
    if (res.statusCode != 200 || body['ok'] != true) {
      throw GatewayException(
          body['error']?.toString() ?? 'Payment init failed (${res.statusCode}).');
    }
    return body;
  }

  /// Ask the worker to verify a completed gateway payment and, on success,
  /// activate the purchase. Returns the worker's JSON, e.g.
  /// `{ok: true, subscriptionId: "...", purchaseType: "exam"}` or
  /// `{ok: false, error: "..."}`.
  static Future<Map<String, dynamic>> verifyPayment({
    required String gateway, // 'esewa' | 'khalti'
    String purchaseType = 'subscription',
    String? planId,
    String? itemId,
    String? contentType,
    String? contentUnitId,
    String? couponCode,
    required Map<String, dynamic> proof,
  }) async {
    final res = await _post(
      '/payments/verify',
      {
        'gateway': gateway,
        'purchaseType': purchaseType,
        if (planId != null && planId.isNotEmpty) 'planId': planId,
        if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
        if (contentType != null && contentType.isNotEmpty)
          'contentType': contentType,
        if (contentUnitId != null && contentUnitId.isNotEmpty)
          'contentUnitId': contentUnitId,
        if (purchaseType == 'subscription' &&
            couponCode != null &&
            couponCode.trim().isNotEmpty)
          'couponCode': couponCode.trim(),
        'proof': proof,
      },
      timeout: const Duration(seconds: 45),
    );
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = {'ok': false, 'error': 'Verification failed (${res.statusCode}).'};
    }
    return decoded;
  }

  /// Re-check a payment whose verification never completed (e.g. the app
  /// was closed mid-flow). The worker re-queries the gateway status API
  /// using only the transactionUuid — no redirect proof needed — and
  /// activates the subscription when the payment is COMPLETE.
  ///
  /// Returns `{ok: true, subscriptionId}` / `{ok: true, already: true,
  /// subscriptionId}` on success, or `{ok: false, reason: '...'}` where
  /// reason is 'payment_not_completed' | 'amount_mismatch' | 'duplicate'
  /// | 'not_found'.
  static Future<Map<String, dynamic>> recheckPayment({
    required String gateway, // 'esewa' | 'khalti'
    required String transactionUuid,
    String purchaseType = 'subscription',
  }) async {
    final res = await _post(
      '/payments/recheck',
      {
        'gateway': gateway,
        'transactionUuid': transactionUuid,
        'purchaseType': purchaseType,
      },
      timeout: const Duration(seconds: 45),
    );
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'reason': 'network_error'};
    }
  }

  /// Tell the worker the user backed out before completing payment.
  /// The worker DELETES the pending records (zero trace) — a completed
  /// payment is never deleted server-side (the worker replies
  /// payment_completed instead).
  /// Best-effort: never throws.
  static Future<void> cancelPayment({
    required String gateway,
    required String transactionUuid,
    String purchaseType = 'subscription',
  }) async {
    try {
      await _post(
        '/payments/cancel',
        {
          'gateway': gateway,
          'transactionUuid': transactionUuid,
          'purchaseType': purchaseType,
        },
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      // Best-effort only.
    }
  }

  // ---------------- pending-payment recovery (SharedPreferences) ----------

  static const String _pendingKey = 'gateway_pending_payment_v1';

  /// Persisted right after /payments/init succeeds, so an app kill during
  /// the gateway/verify steps never loses the payment. Cleared on verify
  /// success, definitive failure, or user cancel.
  ///
  /// [purchaseType] is 'subscription' (default), 'exam' or 'content';
  /// [itemId]/[itemTitle] identify the purchased item for non-subscription
  /// flows ([planId]/[planName] stay for subscriptions).
  static Future<void> savePendingPayment({
    required String gateway,
    required String transactionUuid,
    required String subId,
    String purchaseType = 'subscription',
    String? planId,
    String? planName,
    String? itemId,
    String? itemTitle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _pendingKey,
        jsonEncode({
          'gateway': gateway,
          'transactionUuid': transactionUuid,
          'subId': subId,
          'purchaseType': purchaseType,
          if (planId != null) 'planId': planId,
          if (planName != null) 'planName': planName,
          if (itemId != null) 'itemId': itemId,
          if (itemTitle != null) 'itemTitle': itemTitle,
          'initiatedAt': DateTime.now().toIso8601String(),
        }));
  }

  /// Returns the pending payment map, or null when none is stored.
  static Future<Map<String, dynamic>?> loadPendingPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPendingPayment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }

  /// Delete the user's own non-active purchase request via the worker.
  /// The worker verifies ownership, refuses active records, deletes the
  /// purchase doc, removes the id from the user's id array, and
  /// best-effort cancels the linked gateway payment. Throws
  /// [GatewayException] on failure.
  static Future<void> deleteRequest(String subId,
      {String purchaseType = 'subscription'}) async {
    final res = await _post(
      '/payments/delete-request',
      {'subId': subId, 'purchaseType': purchaseType},
      timeout: const Duration(seconds: 30),
    );
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = {};
    }
    if (res.statusCode != 200 || body['ok'] != true) {
      throw GatewayException(
          body['error']?.toString() ?? 'Delete failed (${res.statusCode}).');
    }
  }
}

class GatewayException implements Exception {
  final String message;
  GatewayException(this.message);
  @override
  String toString() => message;
}
