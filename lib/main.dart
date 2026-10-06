import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/app_language.dart';
import 'services/prefs_service.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppLanguage.init();
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
  runApp(const LoksewaSolutionApp());
}

/// App Links (https://www.kbr.com.np) carry no in-app routing: tapping the
/// link just opens / resumes the app. Cold start goes through the normal
/// splash routing below; a warm start (app in recents) simply resumes where
/// the user was — the OS delivers the intent to the existing activity and
/// Dart deliberately does nothing with it.

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
