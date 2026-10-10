import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/settings/login_devices_screen.dart';

/// Widget tests for Security Settings → Login Devices.
///
/// The Firestore list and the device id are injected seams
/// ([LoginDevicesScreen.loadDevices] / `currentDeviceIdForTest`), so no
/// Firestore or platform channels are touched. NEVER pumpAndSettle — the
/// "this device" dot blinks forever.

List<Map<String, dynamic>> _docs() {
  final now = DateTime.now();
  return [
    {
      'deviceId': 'dev-other',
      'deviceModel': 'samsung SM-A546E',
      'platform': 'android',
      'appVersion': '1.0.86',
      'updatedAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
    },
    {
      'deviceId': 'dev-mine',
      'deviceModel': 'Pixel 8',
      'platform': 'android',
      'appVersion': '1.0.87',
      'updatedAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
    },
    {
      // No deviceModel — the "Unknown device" fallback.
      'deviceId': 'dev-unknown',
      'platform': 'ios',
      'updatedAt': now.subtract(const Duration(days: 3)).toIso8601String(),
    },
  ];
}

Widget _screen({List<Map<String, dynamic>> Function()? docs}) {
  return MaterialApp(
    home: LoginDevicesScreen(
      debugUid: 'u1',
      loadDevices: (_) async => docs == null ? _docs() : docs(),
      currentDeviceIdForTest: 'dev-mine',
    ),
  );
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.pumpWidget(_screen());
  for (var i = 0;
      i < 10 && find.text('Pixel 8').evaluate().isEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('lists devices with the current one first', (tester) async {
    await _pumpLoaded(tester);

    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('samsung SM-A546E'), findsOneWidget);
    // Current device sorts first even though it was listed second.
    final mine = tester.getTopLeft(find.text('Pixel 8')).dy;
    final other = tester.getTopLeft(find.text('samsung SM-A546E')).dy;
    expect(mine, lessThan(other));
  });

  testWidgets('current device wears the This device tag', (tester) async {
    await _pumpLoaded(tester);

    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('missing deviceModel falls back to Unknown device',
      (tester) async {
    await _pumpLoaded(tester);

    expect(find.text('Unknown device'), findsOneWidget);
  });

  testWidgets('rows show app version and relative last-active time',
      (tester) async {
    await _pumpLoaded(tester);

    expect(find.textContaining('v1.0.87'), findsOneWidget);
    expect(find.textContaining('v1.0.86'), findsOneWidget);
    expect(find.textContaining('5 min ago'), findsOneWidget);
    expect(find.textContaining('2 hr ago'), findsOneWidget);
    expect(find.textContaining('3 days ago'), findsOneWidget);
  });

  testWidgets('empty list shows the friendly empty state', (tester) async {
    await tester.pumpWidget(_screen(docs: () => []));
    for (var i = 0;
        i < 10 && find.text('No devices found').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('No devices found'), findsOneWidget);
    expect(find.text('Devices you sign in on will appear here.'),
        findsOneWidget);
  });
}
