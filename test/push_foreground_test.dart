import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/push_notification_service.dart';

// Tests for the foreground (app-open) tray notification logic.
// Pure logic only — no platform channels: resolveForegroundContent,
// encodeTapPayload and decodeTapPayload never touch the plugin.

const _msg = PushNotificationService.resolveForegroundContent;
const _enc = PushNotificationService.encodeTapPayload;
const _dec = PushNotificationService.decodeTapPayload;

RemoteMessage _message({
  String? title,
  String? body,
  Map<String, dynamic> data = const {},
}) =>
    RemoteMessage(
      messageId: 'mid1',
      notification: (title == null && body == null)
          ? null
          : RemoteNotification(title: title, body: body),
      data: data,
    );

void main() {
  group('resolveForegroundContent', () {
    test('prefers the FCM notification title/body verbatim', () {
      final c = _msg(_message(
        title: 'Loksewa Notice: Re-apply Required',
        body: 'PSC lost data. Re-apply soon.',
        data: const {'title': 'WRONG', 'body': 'WRONG'},
      ));
      expect(c, isNotNull);
      expect(c!.title, 'Loksewa Notice: Re-apply Required');
      expect(c.body, 'PSC lost data. Re-apply soon.');
    });

    test('falls back to data title/body for data-only messages', () {
      final c = _msg(_message(data: const {
        'title': 'New Gorkhapatra Added',
        'body': '“XYZ” added now.',
      }));
      expect(c, isNotNull);
      expect(c!.title, 'New Gorkhapatra Added');
      expect(c.body, '“XYZ” added now.');
    });

    test('falls back to data message when body is missing', () {
      final c = _msg(_message(data: const {'message': 'Hello there'}));
      expect(c, isNotNull);
      expect(c!.title, 'Loksewa Solution');
      expect(c.body, 'Hello there');
    });

    test('returns null when there is nothing sensible to show', () {
      expect(_msg(_message()), isNull);
      expect(_msg(_message(data: const {'kind': 'exam'})), isNull);
    });

    test('ignores blank strings', () {
      final c = _msg(_message(
        title: '  ',
        body: '',
        data: const {'title': 'Real Title'},
      ));
      expect(c, isNotNull);
      expect(c!.title, 'Real Title');
      expect(c.body, '');
    });

    test('trims surrounding whitespace', () {
      final c = _msg(_message(title: '  T  ', body: ' B '));
      expect(c!.title, 'T');
      expect(c.body, 'B');
    });

    test('title-only message keeps an empty body', () {
      final c = _msg(_message(title: 'Only Title'));
      expect(c, isNotNull);
      expect(c!.title, 'Only Title');
      expect(c.body, '');
    });
  });

  group('tap payload round-trip', () {
    test('encode/decode preserves the string data map', () {
      final payload = _enc(const {
        'deepLink': '/gorkhapatra/abc123',
        'notificationId': 'n1',
        'count': 3,
      });
      final decoded = _dec(payload);
      expect(decoded['deepLink'], '/gorkhapatra/abc123');
      expect(decoded['notificationId'], 'n1');
      expect(decoded['count'], '3');
    });

    test('decode handles null, empty and garbage gracefully', () {
      expect(_dec(null), isEmpty);
      expect(_dec(''), isEmpty);
      expect(_dec('not-json{{{'), isEmpty);
      expect(_dec('[1,2,3]'), isEmpty);
    });
  });
}
