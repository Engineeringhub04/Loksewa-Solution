import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/auth/forgot_password_screen.dart';
import 'package:loksewa_solution/screens/auth/reset_password_screen.dart';
import 'package:loksewa_solution/screens/auth/signup_screen.dart';
import 'package:loksewa_solution/screens/login_screen.dart';
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
}
