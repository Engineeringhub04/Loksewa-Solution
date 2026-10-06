import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/services/admin_notify_service.dart';

void main() {
  const workerBase = 'https://loksewa-push-worker.loksewasolutionapi.workers.dev';

  tearDown(() {
    // Never leak a mock client into another test.
    AdminNotifyService.setTestClient(null);
  });

  group('notifyAdmin', () {
    test('POSTs the right URL and body to /notify-admin', () async {
      Uri? seenUrl;
      Map<String, String>? seenHeaders;
      Map<String, dynamic>? seenBody;
      AdminNotifyService.setTestClient(
        MockClient((request) async {
          seenUrl = request.url;
          seenHeaders = request.headers;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );

      await AdminNotifyService.notifyAdmin(
        kind: 'report',
        title: 'नयाँ रिपोर्ट 📝',
        body: 'Test User ले समस्या रिपोर्ट गरे: login — app crashes',
        deepLink: '/admin/report-history',
      );

      expect(seenUrl.toString(), '$workerBase/notify-admin');
      expect(seenHeaders!['Content-Type'], 'application/json');
      expect(seenBody, {
        'kind': 'report',
        'title': 'नयाँ रिपोर्ट 📝',
        'body': 'Test User ले समस्या रिपोर्ट गरे: login — app crashes',
        'deepLink': '/admin/report-history',
      });
    });

    test('omits deepLink from the body when null', () async {
      Map<String, dynamic>? seenBody;
      AdminNotifyService.setTestClient(
        MockClient((request) async {
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );

      await AdminNotifyService.notifyAdmin(
        kind: 'exam_answer',
        title: 'उत्तर पेश गरियो ✍️',
        body: 'Someone ले उत्तर पठाए',
      );

      expect(seenBody, {
        'kind': 'exam_answer',
        'title': 'उत्तर पेश गरियो ✍️',
        'body': 'Someone ले उत्तर पठाए',
      });
      expect(seenBody!.containsKey('deepLink'), isFalse);
    });

    test('never throws on a network error', () async {
      AdminNotifyService.setTestClient(
        MockClient((request) async {
          throw http.ClientException('socket closed');
        }),
      );

      await AdminNotifyService.notifyAdmin(
        kind: 'report',
        title: 't',
        body: 'b',
      );
    });

    test('never throws on a non-200 response', () async {
      AdminNotifyService.setTestClient(
        MockClient((request) async => http.Response('boom', 500)),
      );

      await AdminNotifyService.notifyAdmin(
        kind: 'report',
        title: 't',
        body: 'b',
      );
    });

    test('never throws when the worker times out (~8s)', () async {
      AdminNotifyService.setTestClient(
        MockClient((request) async {
          // Hang far past the 8s client timeout.
          await Future<void>.delayed(const Duration(minutes: 5));
          return http.Response('late', 200);
        }),
      );

      await AdminNotifyService.notifyAdmin(
        kind: 'subscription',
        title: 't',
        body: 'b',
      ).timeout(const Duration(seconds: 20));
    });
  });

  group('notifyUser', () {
    test('POSTs the right URL and body to /send-to-uid', () async {
      Uri? seenUrl;
      Map<String, dynamic>? seenBody;
      AdminNotifyService.setTestClient(
        MockClient((request) async {
          seenUrl = request.url;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );

      await AdminNotifyService.notifyUser(
        uid: 'buyer-uid-123',
        title: 'खरिद स्वीकृत ✅',
        body: 'तपाईंको खरिद "Math Exam" स्वीकृत भयो।',
        deepLink: '/subscription/exam-purchase/abc',
      );

      expect(seenUrl.toString(), '$workerBase/send-to-uid');
      expect(seenBody, {
        'uid': 'buyer-uid-123',
        'title': 'खरिद स्वीकृत ✅',
        'body': 'तपाईंको खरिद "Math Exam" स्वीकृत भयो।',
        'deepLink': '/subscription/exam-purchase/abc',
      });
    });

    test('never throws on a network error', () async {
      AdminNotifyService.setTestClient(
        MockClient((request) async {
          throw http.ClientException('connection refused');
        }),
      );

      await AdminNotifyService.notifyUser(
        uid: 'u',
        title: 't',
        body: 'b',
      );
    });

    test('never throws on a non-200 response', () async {
      AdminNotifyService.setTestClient(
        MockClient((request) async => http.Response('boom', 503)),
      );

      await AdminNotifyService.notifyUser(
        uid: 'u',
        title: 't',
        body: 'b',
      );
    });
  });
}
