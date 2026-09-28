import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/login_screen.dart';
import '../screens/tabs_screen.dart';
import '../screens/maintenance_screen.dart';
import '../screens/no_internet_screen.dart';

/// App navigation — mirrors the expo-router structure.
/// Screens are rewritten here one by one (Phase 2).
final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const TabsScreen(),
    ),
    GoRoute(
      path: '/blocking/maintenance',
      builder: (context, state) => const MaintenanceScreen(),
    ),
    GoRoute(
      path: '/blocking/no-internet',
      builder: (context, state) => const NoInternetScreen(),
    ),
  ],
);
