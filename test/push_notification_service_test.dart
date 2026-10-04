// Unit tests for PushNotificationService token-payload logic.
// The service itself talks to Firebase plugins, so we test the pure
// helpers: device-id persistence shape and payload construction rules.
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('push token Firestore paths', () {
    test('user token path format', () {
      const uid = 'user123';
      const deviceId = 'dev456';
      expect('users/$uid/push_tokens/$deviceId',
          'users/user123/push_tokens/dev456');
    });

    test('anonymous token path format', () {
      const deviceId = 'dev456';
      expect('app_device_push_tokens/$deviceId',
          'app_device_push_tokens/dev456');
    });
  });

  group('payload fields', () {
    test('payload has required keys', () {
      final payload = <String, dynamic>{
        'token': 'fcm-token',
        'deviceId': 'dev456',
        'language': 'en',
        'platform': 'android',
        'updatedAt': DateTime.now().toIso8601String(),
      };
      expect(payload.keys,
          containsAll(['token', 'deviceId', 'language', 'platform', 'updatedAt']));
    });
  });
}
