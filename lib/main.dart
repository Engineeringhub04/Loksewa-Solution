import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'services/app_language.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppLanguage.init();
  runApp(const LoksewaSolutionApp());
  _listenForWarmAppLinks();
}

/// Warm-start App Links: while the app is alive, a tapped
/// https://www.kbr.com.np/signup link routes to home when logged in,
/// or to the signup page when not. Everything is guarded — an incoming
/// link must never crash the app.
void _listenForWarmAppLinks() {
  try {
    DeepLinkService.warmLinks.listen((uri) async {
      try {
        if (!DeepLinkService.isSignupLink(uri)) return;
        final user = await AuthService.restoreSession().catchError((_) => null);
        appRouter.go(user != null ? '/' : '/signup');
      } catch (_) {}
    }, onError: (_) {});
  } catch (_) {}
}

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
