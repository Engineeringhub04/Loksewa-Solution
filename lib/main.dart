import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'services/app_language.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppLanguage.init();
  // FCM push: token registration (best-effort, never blocks startup).
  PushNotificationService.init().catchError((_) {});
  // Notification tap → route. deepLink values come from the admin panel
  // (e.g. "/notifications"); anything else falls back to the inbox.
  PushNotificationService.onNotificationTap = (deepLink) {
    final path = (deepLink != null && deepLink.startsWith('/'))
        ? deepLink
        : '/notifications';
    appRouter.go(path);
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
