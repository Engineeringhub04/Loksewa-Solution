import 'dart:convert';

import 'package:http/http.dart' as http;

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
  }) async {
    final token = await AuthService.getValidIdToken();
    final res = await http
        .post(
          Uri.parse('$_base/payments/init'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'gateway': gateway, 'planId': planId}),
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
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'error': 'Verification failed (${res.statusCode}).'};
    }
  }
}

class GatewayException implements Exception {
  final String message;
  GatewayException(this.message);
  @override
  String toString() => message;
}
