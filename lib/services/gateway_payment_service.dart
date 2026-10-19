import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Client for the Cloudflare worker's /payments endpoints.
///
/// Security model: the worker holds every gateway secret (merchant secret
/// keys, HMAC signing). The app only ever receives *signed init payloads*
/// and forwards the gateway's proof back for server-side verification.
/// A faked "payment success" inside the app can never activate a
/// subscription — only the worker's server-to-server verification can.
class GatewayPaymentService {
  static const String _base =
      'https://loksewa-push-worker.loksewasolutionapi.workers.dev';

  /// Ask the worker to initiate a gateway payment.
  ///
  /// Returns the worker payload, e.g.:
  /// ```json
  /// {
  ///   "ok": true, "gateway": "esewa", "testMode": true,
  ///   "transactionUuid": "...",
  ///   "esewa": {"endpoint": "https://...", "fields": {"amount": "...", ...}},
  ///   "khalti": {"pidx": "...", "paymentUrl": "...", "publicKey": "..."}
  /// }
  /// ```
  static Future<Map<String, dynamic>> initPayment({
    required String gateway, // 'esewa' | 'khalti'
    required String planId,
    String? couponCode,
  }) async {
    final token = await AuthService.getValidIdToken();
    final res = await http
        .post(
          Uri.parse('$_base/payments/init'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'gateway': gateway,
            'planId': planId,
            if (couponCode != null && couponCode.trim().isNotEmpty)
              'couponCode': couponCode.trim(),
          }),
        )
        .timeout(const Duration(seconds: 30));
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
  /// activate the subscription. Returns the worker's JSON, e.g.
  /// `{ok: true, subscriptionId: "..."}` or `{ok: false, error: "..."}`.
  static Future<Map<String, dynamic>> verifyPayment({
    required String gateway, // 'esewa' | 'khalti'
    required String planId,
    String? couponCode,
    required Map<String, dynamic> proof,
  }) async {
    final token = await AuthService.getValidIdToken();
    final res = await http
        .post(
          Uri.parse('$_base/payments/verify'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'gateway': gateway,
            'planId': planId,
            if (couponCode != null && couponCode.trim().isNotEmpty)
              'couponCode': couponCode.trim(),
            'proof': proof,
          }),
        )
        .timeout(const Duration(seconds: 45));
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
  }) async {
    final token = await AuthService.getValidIdToken();
    final res = await http
        .post(
          Uri.parse('$_base/payments/recheck'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(
              {'gateway': gateway, 'transactionUuid': transactionUuid}),
        )
        .timeout(const Duration(seconds: 45));
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
  }) async {
    try {
      final token = await AuthService.getValidIdToken();
      await http
          .post(
            Uri.parse('$_base/payments/cancel'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(
                {'gateway': gateway, 'transactionUuid': transactionUuid}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Best-effort only.
    }
  }

  // ---------------- pending-payment recovery (SharedPreferences) ----------

  static const String _pendingKey = 'gateway_pending_payment_v1';

  /// Persisted right after /payments/init succeeds, so an app kill during
  /// the gateway/verify steps never loses the payment. Cleared on verify
  /// success, definitive failure, or user cancel.
  static Future<void> savePendingPayment({
    required String gateway,
    required String transactionUuid,
    required String subId,
    required String planId,
    required String planName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _pendingKey,
        jsonEncode({
          'gateway': gateway,
          'transactionUuid': transactionUuid,
          'subId': subId,
          'planId': planId,
          'planName': planName,
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

  /// Delete the user's own non-active subscription request via the worker.
  /// The worker verifies ownership, refuses active records, deletes the
  /// app_subscriptions doc, removes the id from the user's subscriptionIds,
  /// and best-effort cancels the linked gateway payment. Throws
  /// [GatewayException] on failure.
  static Future<void> deleteRequest(String subId) async {
    const url = '$_base/payments/delete-request';
    final token = await AuthService.getValidIdToken();
    final res = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'subId': subId}),
        )
        .timeout(const Duration(seconds: 30));
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
