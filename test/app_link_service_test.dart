import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/app_link_service.dart';

void main() {
  setUp(() => AppLinkService.resetForTest());

  test('shareLink falls back to the signup App Link before the doc is seeded',
      () {
    expect(AppLinkService.shareLink,
        'https://www.kbr.com.np/signup');
  });

  test('appDomainLink falls back to www.kbr.com.np before the doc is seeded',
      () {
    expect(AppLinkService.appDomainLink, 'www.kbr.com.np');
  });

  test('ensureLoaded does not throw when Firestore is unreachable', () async {
    // No network/auth in unit tests: _fetch catches and keeps fallbacks.
    await AppLinkService.ensureLoaded();
    expect(AppLinkService.shareLink,
        'https://www.kbr.com.np/signup');
  });
}
