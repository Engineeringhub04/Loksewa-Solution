import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/shop/esewa_webview_screen.dart';

void main() {
  group('EsewaProbeResult.tryParse', () {
    test('parses a bare iOS-style probe string', () {
      final r = EsewaProbeResult.tryParse('complete|150|7');
      expect(r, isNotNull);
      expect(r!.readyState, 'complete');
      expect(r.textLength, 150);
      expect(r.interactiveCount, 7);
    });

    test('parses a JSON-quoted Android-style probe string', () {
      final r = EsewaProbeResult.tryParse('"complete|0|0"');
      expect(r, isNotNull);
      expect(r!.textLength, 0);
      expect(r.interactiveCount, 0);
    });

    test('returns null for the error token (eval failure in-page)', () {
      expect(EsewaProbeResult.tryParse('error|0|0'), isNull);
    });

    test('returns null for malformed values', () {
      expect(EsewaProbeResult.tryParse(null), isNull);
      expect(EsewaProbeResult.tryParse(''), isNull);
      expect(EsewaProbeResult.tryParse('garbage'), isNull);
      expect(EsewaProbeResult.tryParse('complete|x|1'), isNull);
      expect(EsewaProbeResult.tryParse('complete|1'), isNull);
    });
  });

  group('EsewaProbeResult.looksBlank', () {
    EsewaProbeResult probe(String readyState, int text, int interactive) =>
        EsewaProbeResult(
            readyState: readyState,
            textLength: text,
            interactiveCount: interactive);

    test('complete + empty DOM is blank (the iOS 15 white screen)', () {
      expect(probe('complete', 0, 0).looksBlank, isTrue);
      expect(probe('complete', 19, 2).looksBlank, isTrue);
    });

    test('enough text means the SPA rendered — not blank', () {
      expect(probe('complete', 20, 0).looksBlank, isFalse);
      expect(probe('complete', 500, 0).looksBlank, isFalse);
    });

    test('enough interactive elements means rendered — not blank', () {
      expect(probe('complete', 0, 3).looksBlank, isFalse);
      expect(probe('complete', 5, 12).looksBlank, isFalse);
    });

    test('a still-loading page is never blank', () {
      expect(probe('loading', 0, 0).looksBlank, isFalse);
      expect(probe('interactive', 0, 0).looksBlank, isFalse);
    });
  });

  group('esewaBlankKind (message selection)', () {
    test('iOS below 16 is the old-system message', () {
      expect(
          esewaBlankKind(isIOS: true, iosMajor: 15), EsewaBlankKind.oldSystem);
      expect(
          esewaBlankKind(isIOS: true, iosMajor: 12), EsewaBlankKind.oldSystem);
    });

    test('iOS 16+ is the load-failed message', () {
      expect(esewaBlankKind(isIOS: true, iosMajor: 16),
          EsewaBlankKind.loadFailed);
      expect(esewaBlankKind(isIOS: true, iosMajor: 26),
          EsewaBlankKind.loadFailed);
    });

    test('unparseable iOS version falls back to load-failed', () {
      expect(esewaBlankKind(isIOS: true, iosMajor: null),
          EsewaBlankKind.loadFailed);
    });

    test('Android is always load-failed', () {
      expect(esewaBlankKind(isIOS: false, iosMajor: null),
          EsewaBlankKind.loadFailed);
    });
  });

  group('parseIosMajorVersion', () {
    test('parses real iOS version strings', () {
      expect(parseIosMajorVersion('Version 15.8.3 (Build 19H386)'), 15);
      expect(parseIosMajorVersion('Version 17.2 (Build 21C62)'), 17);
      expect(parseIosMajorVersion('Version 16.0 (Build 20A362)'), 16);
    });

    test('returns null when there is no number', () {
      expect(parseIosMajorVersion(''), isNull);
      expect(parseIosMajorVersion('Version (Build)'), isNull);
    });
  });
}
