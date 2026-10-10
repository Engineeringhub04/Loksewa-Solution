import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/settings/change_password_screen.dart';
import 'package:loksewa_solution/screens/settings/login_devices_screen.dart';
import 'package:loksewa_solution/screens/settings/security_settings_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/stagger_entrance.dart';

/// Profile → App Settings → Security Settings: the entry renders the
/// read-only account email and both destinations navigate correctly.
/// NEVER pumpAndSettle — the login-devices dot blinks forever.

GoRouter _router() {
  return GoRouter(
    initialLocation: '/settings/security',
    routes: [
      GoRoute(
        path: '/settings/security',
        builder: (_, __) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: '/settings/change-password',
        builder: (_, __) => const ChangePasswordScreen(
          debugEmail: 'user@example.com',
        ),
      ),
      GoRoute(
        path: '/settings/login-devices',
        builder: (_, __) => LoginDevicesScreen(
          debugUid: 'u1',
          loadDevices: (_) async => [],
          currentDeviceIdForTest: 'dev-mine',
        ),
      ),
    ],
  );
}


/// Pumps the StaggerEntrance delays (max 240ms) + entrances through in
/// small increments, so no delayed timer is pending at teardown.
Future<void> _pumpEntered(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('renders the email row and both entries', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await _pumpEntered(tester);

    expect(find.text('Security Settings'), findsOneWidget);
    // No signed-in user in tests → the read-only placeholder.
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Login Devices'), findsOneWidget);
  });

  testWidgets('Change Password entry navigates to the change form',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await _pumpEntered(tester);

    await tester.tap(find.text('Change Password'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('Update Password'), findsOneWidget);
  });

  testWidgets('Login Devices entry navigates to the device list',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await _pumpEntered(tester);

    await tester.tap(find.text('Login Devices'));
    for (var i = 0;
        i < 10 && find.byType(LoginDevicesScreen).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(LoginDevicesScreen), findsOneWidget);
    // Empty list → the friendly empty state.
    for (var i = 0;
        i < 10 && find.text('No devices found').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('No devices found'), findsOneWidget);
    // Fire the empty-state stagger delay — no pending timers at teardown.
    await _pumpEntered(tester);
  });

  testWidgets('premium treatment: staggered cards + safety tip (EN)',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await _pumpEntered(tester);

    // Account card, both entries and the tip card all stagger in.
    expect(find.byType(StaggerEntrance), findsNWidgets(4));
    expect(find.text('Stay protected'), findsOneWidget);
    expect(
      find.text(
          'Use a strong, unique password and never share it with anyone.'),
      findsOneWidget,
    );
    // Core content unchanged.
    expect(find.text('Security Settings'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Login Devices'), findsOneWidget);
  });

  testWidgets('renders Devanagari strings in Nepali mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.setLanguage('ne');
    addTearDown(() => AppLanguage.setLanguage('en'));

    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await _pumpEntered(tester);

    expect(find.text('सुरक्षा सेटिङहरू'), findsOneWidget);
    expect(find.text('खाता इमेल'), findsOneWidget);
    expect(find.text('पासवर्ड परिवर्तन'), findsOneWidget);
    expect(find.text('लगइन डिभाइसहरू'), findsOneWidget);
    expect(find.text('सुरक्षित रहनुहोस्'), findsOneWidget);
    // No English leaking through.
    expect(find.text('Security Settings'), findsNothing);
    expect(find.text('Stay protected'), findsNothing);
  });
}
