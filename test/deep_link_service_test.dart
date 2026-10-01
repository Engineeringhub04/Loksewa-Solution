import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.isSignupLink', () {
    test('matches the shared signup link on www host', () {
      expect(DeepLinkService.isSignupLink(
          Uri.parse('https://www.kbr.com.np/signup')), isTrue);
    });

    test('matches the shared signup link on bare host', () {
      expect(DeepLinkService.isSignupLink(
          Uri.parse('https://kbr.com.np/signup')), isTrue);
    });

    test('matches /signup with trailing path or query', () {
      expect(DeepLinkService.isSignupLink(
          Uri.parse('https://www.kbr.com.np/signup?ref=share')), isTrue);
    });

    test('rejects null and other hosts', () {
      expect(DeepLinkService.isSignupLink(null), isFalse);
      expect(DeepLinkService.isSignupLink(
          Uri.parse('https://www.kbr.com.np/downloadapp')), isFalse);
      expect(DeepLinkService.isSignupLink(
          Uri.parse('https://example.com/signup')), isFalse);
    });
  });

  group('DeepLinkService.getInitialLink', () {
    test('returns null (not throw) when no link opened the app', () async {
      // No platform plugin in unit tests: the MissingPluginException is
      // swallowed and the cold-start path behaves like a normal launch.
      expect(await DeepLinkService.getInitialLink(), isNull);
    });
  });
}
