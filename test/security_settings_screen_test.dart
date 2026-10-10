import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/settings/change_password_screen.dart';
import 'package:loksewa_solution/screens/settings/login_devices_screen.dart';
import 'package:loksewa_solution/screens/settings/security_settings_screen.dart';

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

void main() {
  testWidgets('renders the email row and both entries', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Security Settings'), findsOneWidget);
    // No signed-in user in tests → the read-only placeholder.
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Login Devices'), findsOneWidget);
  });

  testWidgets('Change Password entry navigates to the change form',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Change Password'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('Update Password'), findsOneWidget);
  });

  testWidgets('Login Devices entry navigates to the device list',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pump(const Duration(milliseconds: 100));

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
  });
}
