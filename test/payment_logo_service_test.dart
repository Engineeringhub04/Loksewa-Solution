// Unit tests for PaymentLogoService: label matching against the worker's
// GET /image-links payload, the once-per-session fetch, and the
// failed-load retry (2026-11-04 — logos moved off ImgBB onto the admin
// panel's Image Link Generator).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/payment_logo_service.dart';

const _esewa =
    'https://res.cloudinary.com/dw7gg0fhc/image/upload/v1/image-links/esewa.png';
const _khalti =
    'https://res.cloudinary.com/dw7gg0fhc/image/upload/v1/image-links/khalti.png';
const _fonepay =
    'https://res.cloudinary.com/dw7gg0fhc/image/upload/v1/image-links/fonepay.png';

String _payload() => jsonEncode({
      'ok': true,
      'images': [
        {'id': '1', 'label': 'Khalti-Logo', 'imageUrl': _khalti},
        {'id': '2', 'label': 'Some Banner Art', 'imageUrl': 'https://x/y.png'},
        {'id': '3', 'label': 'Esewa-Logo', 'imageUrl': _esewa},
        {'id': '4', 'label': 'Fonepay-Logo', 'imageUrl': _fonepay},
      ],
    });

void main() {
  tearDown(() {
    CfApi.setTestClient(null);
    PaymentLogoService.debugReset();
  });

  test('matches each payment logo by its label keyword', () async {
    CfApi.setTestClient(MockClient((request) async {
      expect(request.url.path, '/image-links');
      return http.Response(_payload(), 200);
    }));
    await PaymentLogoService.ensureLoaded();
    expect(PaymentLogoService.esewaLogo, _esewa);
    expect(PaymentLogoService.khaltiLogo, _khalti);
    expect(PaymentLogoService.weAcceptLogos, [_esewa, _khalti, _fonepay]);
  });

  test('fetches at most once per session', () async {
    var calls = 0;
    CfApi.setTestClient(MockClient((_) async {
      calls++;
      return http.Response(_payload(), 200);
    }));
    await PaymentLogoService.ensureLoaded();
    await PaymentLogoService.ensureLoaded();
    await PaymentLogoService.ensureLoaded();
    expect(calls, 1);
  });

  test('failed load leaves logos unset and the next call retries', () async {
    var calls = 0;
    CfApi.setTestClient(MockClient((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('offline');
      return http.Response(_payload(), 200);
    }));
    await PaymentLogoService.ensureLoaded();
    expect(PaymentLogoService.esewaLogo, isNull);
    expect(PaymentLogoService.weAcceptLogos, isEmpty);
    await PaymentLogoService.ensureLoaded();
    expect(calls, 2);
    expect(PaymentLogoService.esewaLogo, _esewa);
  });

  test('rows without a matching label leave that logo unset', () async {
    CfApi.setTestClient(MockClient((_) async {
      return http.Response(
        jsonEncode({
          'ok': true,
          'images': [
            {'id': '9', 'label': 'Unrelated', 'imageUrl': 'https://x/z.png'},
          ],
        }),
        200,
      );
    }));
    await PaymentLogoService.ensureLoaded();
    expect(PaymentLogoService.esewaLogo, isNull);
    expect(PaymentLogoService.khaltiLogo, isNull);
    expect(PaymentLogoService.weAcceptLogos, isEmpty);
  });
}
