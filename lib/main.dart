import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/app_language.dart';
import 'services/password_reset_service.dart';
import 'services/prefs_service.dart';
import 'services/push_notification_service.dart';
import 'services/reset_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppLanguage.init();
  // Password-reset App Link cold start: the router forces every cold start
  // to /splash (overridePlatformDefaultLocation), which would discard the
  // tapped link's token. Capture it first — the splash consumes the stash
  // and routes to the reset form. Best-effort, never blocks startup.
  await ResetLinkService.captureInitialLink();
  // FCM push: token registration (best-effort, never blocks startup).
  PushNotificationService.init().catchError((_) {});
  // Notification tap → stash the payload for the splash on cold start;
  // navigate immediately when the app is already running (warm tap).
  // The splash consumes the stash after the auth check:
  //   logged in  → home → notification list → auto-open the tapped details
  //   logged out → stash cleared, normal onboarding/login flow.
  // Back stack after a tap: details → list → home (never straight to close).
  PushNotificationService.onNotificationTap = (data) async {
    final id = data['notificationId']?.trim();
    final link = data['deepLink']?.trim();
    if (id != null && id.isNotEmpty) {
      await PrefsService.setString(
          PushNotificationService.pendingNotificationIdKey, id);
    }
    if (link != null && link.isNotEmpty) {
      await PrefsService.setString(
          PushNotificationService.pendingNotificationLinkKey, link);
    }
    // Warm tap (app already past the splash): navigate right away.
    // Cold start: splashHasRouted is still false — the splash picks the
    // stash up after auth.
    if (splashHasRouted) {
      final pending = await PushNotificationService.consumePendingTap();
      final pendingId = pending.id;
      if (pendingId != null && AuthService.currentUser != null) {
        appRouter.go('/');
        appRouter.push('/notifications', extra: {
          'autoOpenId': pendingId,
          if (pending.deepLink != null)
            'fallbackDeepLink': pending.deepLink!,
        });
      } else if (pending.deepLink != null && AuthService.currentUser != null) {
        // Push-only notifications (e.g. Gorkhapatra) carry a deepLink but no
        // notificationId — push it directly instead of dropping the tap.
        // Login required: no access to anything before login.
        appRouter.push(pending.deepLink!);
      }
    }
  };
  // Warm-start App Links: the app is already running (in recents) when a
  // link is tapped. Only the exact password-reset path is intercepted;
  // every other link keeps today's behavior — the OS resumes the activity
  // and Dart does nothing with it. Cold starts are owned by
  // captureInitialLink() + the splash (splashHasRouted is still false
  // there), so stream events are ignored until the splash has routed.
  // The tapped token is validated SILENTLY before navigating, per the
  // reset-link matrix: invalid/expired → /login + popup when logged out,
  // popup in place when logged in; unreachable validation → the form
  // anyway when logged out (submit surfaces the error), nothing when
  // logged in.
  ResetLinkService.onWarmResetLink = (location) async {
    if (!splashHasRouted) return;
    final token = Uri.tryParse(location)?.queryParameters['token'];
    if (token == null || token.isEmpty) {
      appRouter.go(location);
      return;
    }
    await ResetLinkService.handleWarmToken(
      token,
      loggedIn: AuthService.currentUser != null,
      validate: PasswordResetService.validateToken,
      navigate: appRouter.go,
      showInvalidPopup: () async {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) {
          await ResetLinkService.showInvalidLinkPopup(ctx);
        }
      },
    );
  };
  AppLinks().uriLinkStream.listen(
    ResetLinkService.handleIncomingUri,
    onError: (_) {},
  );
  runApp(const LoksewaSolutionApp());
}

/// App Links (https://www.kbr.com.np) carry no in-app routing except the
/// password-reset path: tapping a plain-domain link just opens / resumes the
/// app. Cold start goes through the normal splash routing below; a warm
/// start (app in recents) simply resumes where the user was — the OS
/// delivers the intent to the existing activity and Dart deliberately does
/// nothing with it. The one exception is
/// https://kbr.com.np/auth/reset-password?token=..., which the
/// ResetLinkService routes to the reset form (cold start via the splash,
/// warm start via the link stream).

class LoksewaSolutionApp extends StatelessWidget {
  const LoksewaSolutionApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the theme toggle flips ThemeService.mode,
    // or when the profile language converter flips AppLanguage.current.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.mode,
      builder: (context, mode, _) => ValueListenableBuilder<String>(
        valueListenable: AppLanguage.current,
        builder: (context, _, __) => MaterialApp.router(
          title: 'Loksewa Solution',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          routerConfig: appRouter,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
