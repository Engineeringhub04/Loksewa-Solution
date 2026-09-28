import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const LoksewaSolutionApp());
}

class LoksewaSolutionApp extends StatelessWidget {
  const LoksewaSolutionApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the theme toggle flips ThemeService.mode.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.mode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'Loksewa Solution',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        routerConfig: appRouter,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
