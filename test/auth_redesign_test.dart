import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/screens/auth/forgot_password_screen.dart';
import 'package:loksewa_solution/screens/auth/reset_password_screen.dart';
import 'package:loksewa_solution/screens/auth/signup_screen.dart';
import 'package:loksewa_solution/screens/login_screen.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/widgets/auth/auth_header.dart';
import 'package:loksewa_solution/widgets/auth/auth_screen_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finds an [Image] widget backed by the given asset path.
Finder _findAssetImage(String asset) => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == asset,
    );

/// Pump with a tall surface + mocked prefs (login/signup read prefs on mount).
Future<void> _pumpApp(WidgetTester tester, String location) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
          path: '/auth/reset-password',
          builder: (_, __) => const ResetPasswordScreen()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('AuthHeader — Himalayan redesign', () {
    testWidgets('renders Himalayan bg image + title + subtitle',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              title: 'Welcome Back',
              subtitle: 'Sign in to continue',
            ),
          ),
        ),
      );
      await tester.pump();

      // The Himalayan panorama is a BoxDecoration image (not an Image widget).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).image?.image is AssetImage &&
              (((w.decoration as BoxDecoration).image!.image) as AssetImage)
                      .assetName ==
                  'assets/images/auth_himalayas_bg.png',
        ),
        findsOneWidget,
      );
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign in to continue'), findsOneWidget);
    });
  });

  group('AuthScreenLayout — illustration slot', () {
    testWidgets('shows illustration when illustrationAsset is set',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthScreenLayout(
              title: 'T',
              subtitle: 'S',
              illustrationAsset: 'assets/images/auth_illust_reset.png',
              child: Text('body'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsOneWidget,
      );
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('no illustration when illustrationAsset is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthScreenLayout(
              title: 'T',
              subtitle: 'S',
              child: Text('body'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsNothing,
      );
    });
  });

  group('LoginScreen — illustration show/hide', () {
    testWidgets('collapsed state shows illustration; email state hides it',
        (tester) async {
      await _pumpApp(tester, '/login');

      // Collapsed: illustration visible.
      expect(
        _findAssetImage('assets/images/auth_illust_login.png'),
        findsOneWidget,
      );
      expect(find.text('Continue with Email'), findsOneWidget);

      // Open the email form → illustration hides with the fade.
      await tester.tap(find.text('Continue with Email'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _findAssetImage('assets/images/auth_illust_login.png'),
        findsNothing,
      );
      expect(find.text('Login with Email'), findsOneWidget);
    });
  });

  group('SignupScreen — illustration show/hide', () {
    testWidgets('collapsed state shows illustration; form state hides it',
        (tester) async {
      await _pumpApp(tester, '/signup');

      expect(
        _findAssetImage('assets/images/auth_illust_signup.png'),
        findsOneWidget,
      );

      await tester.tap(find.text('Continue with Email'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _findAssetImage('assets/images/auth_illust_signup.png'),
        findsNothing,
      );
    });
  });

  group('Reset pages — compact illustration', () {
    testWidgets('forgot-password shows the reset illustration',
        (tester) async {
      await _pumpApp(tester, '/forgot-password');

      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsOneWidget,
      );
      expect(find.text('Send Reset Link'), findsOneWidget);
    });

    testWidgets('reset-password shows the reset illustration',
        (tester) async {
      await _pumpApp(tester, '/auth/reset-password?token=abc123');

      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsOneWidget,
      );
      expect(find.text('New Password'), findsOneWidget);
    });
  });

  group('Success states — illustration hides (user asked 2026-10-10)', () {
    tearDown(() {
      // Never leak a mock client into another test.
      PasswordResetService.setTestClient(null);
    });

    testWidgets('forgot-password success hides the illustration',
        (tester) async {
      PasswordResetService.setTestClient(
        MockClient((request) async => http.Response('{"ok":true}', 200)),
      );
      await _pumpApp(tester, '/forgot-password');

      // Illustration visible on the form state.
      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsOneWidget,
      );

      final fields = find.byType(TextField);
      expect(fields, findsOneWidget);
      await tester.enterText(fields, 'user@example.com');
      await tester.tap(find.text('Send Reset Link'));
      // Let the mocked worker future resolve, then the switchers animate.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Check Your Email'), findsOneWidget);
      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsNothing,
      );
    });

    testWidgets('reset-password success hides the illustration',
        (tester) async {
      PasswordResetService.setTestClient(
        MockClient((request) async => http.Response('{"ok":true}', 200)),
      );
      await _pumpApp(tester, '/auth/reset-password?token=tok123');

      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsOneWidget,
      );

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'newpass1');
      await tester.enterText(fields.at(1), 'newpass1');
      await tester.tap(find.text('Change Password'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
          find.text(
              'Your password has been changed successfully. You can now log in with your new password.'),
          findsOneWidget);
      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsNothing,
      );
    });

    testWidgets('reset-password error keeps the illustration', (tester) async {
      PasswordResetService.setTestClient(
        MockClient((request) async =>
            http.Response('{"ok":false,"reason":"invalid_token"}', 200)),
      );
      await _pumpApp(tester, '/auth/reset-password?token=tok123');

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'newpass1');
      await tester.enterText(fields.at(1), 'newpass1');
      await tester.tap(find.text('Change Password'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      // Error state keeps the illustration for context (user asked).
      expect(
        _findAssetImage('assets/images/auth_illust_reset.png'),
        findsOneWidget,
      );
    });
  });

  group('v1.0.91 polish (user asked 2026-10-10)', () {
    testWidgets('auth header logo tile is a 96px squircle (radius 28)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthHeader(
              title: 'Welcome Back',
              subtitle: 'Sign in to continue',
            ),
          ),
        ),
      );
      await tester.pump();

      final tile = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(28),
      );
      expect(tile, findsOneWidget);
      // Logo image fills the 96x96 tile.
      final logoImg = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/images/app_logo.png',
        ),
      );
      expect(logoImg.width, 96);
      expect(logoImg.height, 96);
    });

    testWidgets('login illustration is 130px', (tester) async {
      await _pumpApp(tester, '/login');
      final img = tester.widget<Image>(
        _findAssetImage('assets/images/auth_illust_login.png'),
      );
      expect(img.height, 130);
    });

    testWidgets('signup illustration is 130px', (tester) async {
      await _pumpApp(tester, '/signup');
      final img = tester.widget<Image>(
        _findAssetImage('assets/images/auth_illust_signup.png'),
      );
      expect(img.height, 130);
    });

    testWidgets('reset-password illustration is 120px and centered',
        (tester) async {
      await _pumpApp(tester, '/auth/reset-password?token=tok123');
      final img = tester.widget<Image>(
        _findAssetImage('assets/images/auth_illust_reset.png'),
      );
      expect(img.height, 120);
      // Explicitly wrapped in a Center (user: illustration must be centered).
      expect(
        find.ancestor(
          of: _findAssetImage('assets/images/auth_illust_reset.png'),
          matching: find.byType(Center),
        ),
        findsWidgets,
      );
    });

    testWidgets('reset-password buttons are app blue, not purple',
        (tester) async {
      await _pumpApp(tester, '/auth/reset-password?token=tok123');
      final btn = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).first,
      );
      expect(
        btn.style?.backgroundColor?.resolve({}),
        const Color(0xFF1D4ED8),
      );
    });

    testWidgets('forgot-password send button is app blue, not purple',
        (tester) async {
      await _pumpApp(tester, '/forgot-password');
      final btn = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).first,
      );
      expect(
        btn.style?.backgroundColor?.resolve({}),
        const Color(0xFF1D4ED8),
      );
    });
  });
}
