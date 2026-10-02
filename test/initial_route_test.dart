import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/router/app_router.dart';

/// Link cold starts must never bypass the splash: Android hands the tapped
/// App Link to the engine as the platform's initial route, and go_router
/// would otherwise boot straight to '/' (or '/signup') with no session
/// check and no user loaded. These tests pin the fix.
void main() {
  test('router ignores the OS link route on boot', () {
    expect(appRouter.overridePlatformDefaultLocation, isTrue);
  });

  test('router boots to /splash', () {
    final loc = appRouter.routeInformationProvider.value.uri.toString();
    expect(loc, '/splash');
  });
}
