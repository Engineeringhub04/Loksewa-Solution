import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/payment_gateway.dart';

/// Unit tests for the payment-gateway port (payment_gateway.dart).
///
/// The eSewa signature vectors below were computed INDEPENDENTLY with
/// Python's hmac library (not by re-running the Dart code), so they act as a
/// cross-implementation check that the signed message format, field order,
/// key handling and base64 output match the React original byte-for-byte.
void main() {
  group('eSewa test constants', () {
    test('match the public UAT values from paymentGateway.ts', () {
      expect(EsewaTest.productCode, 'EPAYTEST');
      expect(EsewaTest.secretKey, '8gBm/:&EnhH.1/q');
      expect(EsewaTest.formUrl,
          'https://rc-epay.esewa.com.np/api/epay/main/v2/form');
    });

    test('Khalti UAT initiate URL and return URL are exact', () {
      expect(KhaltiTest.initiateUrl,
          'https://dev.khalti.com/api/v2/epayment/initiate/');
      expect(paymentReturnUrl, 'https://loksewasolution.app/payment-return');
    });
  });

  group('randomTxnId', () {
    test('has the expected prefix-timestamp-random shape', () {
      final id = randomTxnId('LS');
      expect(id.startsWith('LS-'), isTrue);
      expect(id.split('-').length, 3);
    });

    test('generates unique ids', () {
      expect(randomTxnId('LS') == randomTxnId('LS'), isFalse);
    });
  });

  group('createEsewaCheckoutHtml', () {
    test(
        'signature matches the independently-computed HMAC-SHA256 vector '
        '(test credentials)', () {
      final checkout = createEsewaCheckoutHtml(
        amount: 100,
        transactionUuid: 'abc-123',
        successUrl: 'https://loksewasolution.app/payment-return',
        failureUrl: 'https://loksewasolution.app/payment-return',
      );
      expect(checkout.transactionUuid, 'abc-123');
      // Vector computed with Python hmac for message:
      // total_amount=100,transaction_uuid=abc-123,product_code=EPAYTEST
      // keyed with the public UAT secret.
      expect(
        checkout.html,
        contains(
            'name="signature" value="he9XDW0cedutyT/W1uVuIjJTZ55XfVDlZ7qpM8RVjyA="'),
      );
    });

    test(
        'signature matches the independently-computed vector '
        '(custom code/key, decimal amount)', () {
      final checkout = createEsewaCheckoutHtml(
        amount: 149.5,
        transactionUuid: 'xyz-999',
        successUrl: 'https://example.com/ok',
        failureUrl: 'https://example.com/fail',
        merchantCode: 'NP-ES-TEST',
        secretKey: 'custom-secret-123',
      );
      // Vector computed with Python hmac for message:
      // total_amount=149.5,transaction_uuid=xyz-999,product_code=NP-ES-TEST
      expect(
        checkout.html,
        contains(
            'name="signature" value="8aZkq7s7SoSNEubo+BHVonK9N3fOwQoVHlhLCBBHr/0="'),
      );
      expect(checkout.html, contains('name="product_code" value="NP-ES-TEST"'));
      expect(checkout.html, contains('name="total_amount" value="149.5"'));
    });

    test('emits the exact signed field list and form field order', () {
      final checkout = createEsewaCheckoutHtml(
        amount: 250,
        transactionUuid: 'order-1',
        successUrl: 'https://a.example/ok',
        failureUrl: 'https://a.example/fail',
      );
      final html = checkout.html;
      expect(
        html,
        contains(
            'name="signed_field_names" value="total_amount,transaction_uuid,product_code"'),
      );
      final order = [
        'amount',
        'tax_amount',
        'total_amount',
        'transaction_uuid',
        'product_code',
        'product_service_charge',
        'product_delivery_charge',
        'success_url',
        'failure_url',
        'signed_field_names',
        'signature',
      ];
      var lastIndex = -1;
      for (final name in order) {
        final i = html.indexOf('name="$name"');
        expect(i, greaterThan(lastIndex), reason: 'field $name out of order');
        lastIndex = i;
      }
      expect(html, contains('action="${EsewaTest.formUrl}" method="POST"'));
      expect(html, contains('document.forms[0].submit()'));
    });

    test('whole-number amounts render without a decimal point', () {
      final checkout = createEsewaCheckoutHtml(
        amount: 100,
        transactionUuid: 't1',
        successUrl: 'https://a.example/ok',
        failureUrl: 'https://a.example/fail',
      );
      expect(checkout.html, contains('name="total_amount" value="100"'));
      expect(checkout.html.contains('value="100.0"'), isFalse);
    });

    test('escapes HTML special characters in field values', () {
      final checkout = createEsewaCheckoutHtml(
        amount: 100,
        transactionUuid: 't1',
        successUrl: 'https://a.example/ok?a=1&b=<x>"y"',
        failureUrl: 'https://a.example/fail',
      );
      expect(
        checkout.html,
        contains('value="https://a.example/ok?a=1&amp;b=&lt;x&gt;&quot;y&quot;"'),
      );
    });

    test('generates a transaction UUID when none is supplied', () {
      final checkout = createEsewaCheckoutHtml(
        amount: 100,
        successUrl: 'https://a.example/ok',
        failureUrl: 'https://a.example/fail',
      );
      expect(checkout.transactionUuid.startsWith('LS-'), isTrue);
      expect(checkout.html,
          contains('name="transaction_uuid" value="${checkout.transactionUuid}"'));
    });
  });

  group('openKhaltiCheckout', () {
    test('throws KHALTI_SECRET_KEY_MISSING when the key is empty', () async {
      await expectLater(
        openKhaltiCheckout(
          amount: 100,
          purchaseOrderId: 'LS-1',
          purchaseOrderName: 'Plan',
          returnUrl: paymentReturnUrl,
          websiteUrl: 'https://loksewasolution.app',
          secretKey: '',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('KHALTI_SECRET_KEY_MISSING'),
          ),
        ),
      );
    });
  });
}
