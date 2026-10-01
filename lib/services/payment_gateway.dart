// Payment gateway helpers for the subscription checkout.
//
// Mirrors `src/core/media/paymentGateway.ts` line-by-line:
//
// eSewa ePay v2 uses a signed POST form. Khalti ePayment uses a server-side
// initiate request and returns a hosted payment URL. This app supports the
// providers' sandbox/UAT flow for testing; live secret keys must never be
// shipped in the client bundle.
//
// Secret handling: only the providers' PUBLIC test/UAT values live here
// (eSewa's official UAT credentials are documented at
// https://developer.esewa.com.np/pages/Test-credentials and are meant for
// client-side testing). Live merchant credentials belong in a secure backend
// and are passed in through the `merchantCode` / `secretKey` parameters —
// exactly like the React original. Nothing here is logged or persisted.
//
// What is intentionally NOT ported: `openEsewaCheckout` opens the generated
// HTML in the system browser via expo-web-browser. This Flutter build has no
// url_launcher dependency (and none may be added), so the browser half has no
// established equivalent — the portable half (HTML generation) is fully
// ported below, and the checkout screen keeps the React "under construction"
// stub behavior for the gateway button.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Official eSewa UAT credentials documented at:
/// https://developer.esewa.com.np/pages/Test-credentials
class EsewaTest {
  static const productCode = 'EPAYTEST';
  static const secretKey = '8gBm/:&EnhH.1/q';
  static const formUrl = 'https://rc-epay.esewa.com.np/api/epay/main/v2/form';
}

/// Khalti does not publish one shared secret key. A merchant must create a
/// sandbox account at https://test-admin.khalti.com. Its secret key must be
/// used only by a secure backend and must never be stored in client-readable
/// Firestore config or bundled in the mobile app.
class KhaltiTest {
  static const initiateUrl = 'https://dev.khalti.com/api/v2/epayment/initiate/';
}

/// Deep-link / return URL the gateway WebView watches for, so the app can
/// close the gateway and show the return hint. Mirrors PAYMENT_RETURN_URL in
/// app/subscription/checkout.tsx.
const paymentReturnUrl = 'https://loksewasolution.app/payment-return';

String randomTxnId(String prefix) {
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(100000)}';
}

/// Result of [createEsewaCheckoutHtml]: the auto-submitting HTML form plus
/// the transaction UUID that was signed into it.
class EsewaCheckout {
  final String html;
  final String transactionUuid;
  const EsewaCheckout({required this.html, required this.transactionUuid});
}

/// Builds the eSewa ePay v2 signed POST form as an auto-submitting HTML page.
///
/// Field order, the signed-field list, the signature message format and the
/// HMAC-SHA256 (base64) algorithm mirror `createEsewaCheckoutHtml` exactly:
/// signed_field_names = 'total_amount,transaction_uuid,product_code' and the
/// message `total_amount=…,transaction_uuid=…,product_code=…` signed with the
/// secret key. Pass live `merchantCode`/`secretKey` from a secure backend;
/// defaults are the public UAT values above.
EsewaCheckout createEsewaCheckoutHtml({
  required num amount,
  String? transactionUuid,
  required String successUrl,
  required String failureUrl,
  String? merchantCode,
  String? secretKey,
}) {
  final productCode = (merchantCode == null || merchantCode.isEmpty)
      ? EsewaTest.productCode
      : merchantCode;
  final key =
      (secretKey == null || secretKey.isEmpty) ? EsewaTest.secretKey : secretKey;
  final txnUuid = transactionUuid ?? randomTxnId('LS');
  final totalAmount = _amountString(amount);
  const signedFieldNames = 'total_amount,transaction_uuid,product_code';
  final messageToSign =
      'total_amount=$totalAmount,transaction_uuid=$txnUuid,product_code=$productCode';
  final signature = base64Encode(
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(messageToSign)).bytes,
  );

  final fields = <String, String>{
    'amount': totalAmount,
    'tax_amount': '0',
    'total_amount': totalAmount,
    'transaction_uuid': txnUuid,
    'product_code': productCode,
    'product_service_charge': '0',
    'product_delivery_charge': '0',
    'success_url': successUrl,
    'failure_url': failureUrl,
    'signed_field_names': signedFieldNames,
    'signature': signature,
  };

  final inputs = fields.entries
      .map((e) =>
          '<input type="hidden" name="${e.key}" value="${_escapeHtml(e.value)}" />')
      .join('\n');
  final html =
      '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1" /></head><body onload="document.forms[0].submit()"><form action="${EsewaTest.formUrl}" method="POST">$inputs</form><p>Opening eSewa…</p></body></html>';
  return EsewaCheckout(html: html, transactionUuid: txnUuid);
}

String _amountString(num amount) {
  // Mirrors JS String(amount): whole numbers render without a decimal point.
  if (amount % 1 == 0) return amount.toInt().toString();
  return amount.toString();
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// Result of [openKhaltiCheckout]: the hosted payment URL the user must be
/// sent to, plus the order id and Khalti's payment identifier.
class KhaltiCheckout {
  final String purchaseOrderId;
  final String? pidx;
  final String paymentUrl;
  const KhaltiCheckout({
    required this.purchaseOrderId,
    required this.pidx,
    required this.paymentUrl,
  });
}

/// Initiates Khalti ePayment and returns its hosted payment URL.
///
/// Mirrors `openKhaltiCheckout`: POSTs to the UAT initiate endpoint with
/// `Authorization: Key <secretKey>`, the amount in paisa
/// (`Math.round(amount * 100)`), and `customer_info`. Error codes match the
/// React originals: KHALTI_SECRET_KEY_MISSING, KHALTI_INITIATE_FAILED:<detail>,
/// KHALTI_NO_PAYMENT_URL.
Future<KhaltiCheckout> openKhaltiCheckout({
  required num amount,
  String? purchaseOrderId,
  required String purchaseOrderName,
  required String returnUrl,
  required String websiteUrl,
  String? customerName,
  String? customerEmail,
  required String secretKey,
}) async {
  final orderId = purchaseOrderId ?? randomTxnId('LS');
  if (secretKey.isEmpty) throw Exception('KHALTI_SECRET_KEY_MISSING');

  final customerInfo = <String, String>{
    if (customerName != null && customerName.isNotEmpty) 'name': customerName,
    if (customerEmail != null && customerEmail.isNotEmpty) 'email': customerEmail,
  };
  final response = await http.post(
    Uri.parse(KhaltiTest.initiateUrl),
    headers: {
      'Authorization': 'Key $secretKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'return_url': returnUrl,
      'website_url': websiteUrl,
      // Khalti expects paisa: Math.round(amount * 100).
      'amount': (amount * 100).round(),
      'purchase_order_id': orderId,
      'purchase_order_name': purchaseOrderName,
      'customer_info': customerInfo,
    }),
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final detail = response.body;
    throw Exception(
        'KHALTI_INITIATE_FAILED:${detail.length > 160 ? detail.substring(0, 160) : detail}');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final paymentUrl = data['payment_url'] as String?;
  if (paymentUrl == null || paymentUrl.isEmpty) {
    throw Exception('KHALTI_NO_PAYMENT_URL');
  }
  return KhaltiCheckout(
    purchaseOrderId: orderId,
    pidx: data['pidx'] as String?,
    paymentUrl: paymentUrl,
  );
}
