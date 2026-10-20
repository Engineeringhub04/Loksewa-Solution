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

  group('esewaSlotFor', () {
    EsewaProbeResult probe(int text, int interactive) => EsewaProbeResult(
        readyState: 'complete',
        textLength: text,
        interactiveCount: interactive);

    test('a failed eval (null probe) is inconclusive, never blank', () {
      expect(esewaSlotFor(null), EsewaProbeSlot.inconclusive);
    });

    test('an empty DOM is blank', () {
      expect(esewaSlotFor(probe(0, 0)), EsewaProbeSlot.blank);
      expect(esewaSlotFor(probe(19, 2)), EsewaProbeSlot.blank);
    });

    test('a rendered DOM is alive', () {
      expect(esewaSlotFor(probe(150, 7)), EsewaProbeSlot.alive);
      expect(esewaSlotFor(probe(0, 3)), EsewaProbeSlot.alive);
    });
  });

  group('esewaLivenessOutcome', () {
    const a = EsewaProbeSlot.alive;
    const b = EsewaProbeSlot.blank;
    const i = EsewaProbeSlot.inconclusive;

    test('probe schedule is the fast 3/6/10/14 ladder', () {
      expect(esewaLivenessProbeOffsetsSecs, [3, 6, 10, 14]);
    });

    test('alive on ANY single probe, even mid-window', () {
      expect(esewaLivenessOutcome([a]), EsewaLivenessOutcome.alive);
      expect(esewaLivenessOutcome([i, a]), EsewaLivenessOutcome.alive);
      expect(esewaLivenessOutcome([b, b, a]), EsewaLivenessOutcome.alive);
      expect(esewaLivenessOutcome([b, i, b, a]), EsewaLivenessOutcome.alive);
    });

    test('pending while the window is incomplete — two blanks are '
        'not yet a verdict', () {
      expect(esewaLivenessOutcome([]), EsewaLivenessOutcome.pending);
      expect(esewaLivenessOutcome([b]), EsewaLivenessOutcome.pending);
      expect(esewaLivenessOutcome([b, b]), EsewaLivenessOutcome.pending);
      expect(esewaLivenessOutcome([b, i, b]), EsewaLivenessOutcome.pending);
      expect(esewaLivenessOutcome([i, i, i]), EsewaLivenessOutcome.pending);
    });

    test('blank verdict when a complete window ends on the last two '
        'consecutive blanks', () {
      expect(
          esewaLivenessOutcome([b, b, b, b]), EsewaLivenessOutcome.blank);
      expect(
          esewaLivenessOutcome([i, b, b, b]), EsewaLivenessOutcome.blank);
      expect(
          esewaLivenessOutcome([b, i, b, b]), EsewaLivenessOutcome.blank);
      // Inconclusive slots carry no DOM measurement — the last two
      // MEASURED states decide.
      expect(
          esewaLivenessOutcome([b, b, i, i]), EsewaLivenessOutcome.blank);
      expect(
          esewaLivenessOutcome([b, i, i, b]), EsewaLivenessOutcome.blank);
    });

    test('undecided when a complete window measured fewer than two '
        'blank states', () {
      expect(esewaLivenessOutcome([i, i, i, i]),
          EsewaLivenessOutcome.undecided);
      expect(esewaLivenessOutcome([b, i, i, i]),
          EsewaLivenessOutcome.undecided);
      expect(esewaLivenessOutcome([i, i, i, b]),
          EsewaLivenessOutcome.undecided);
    });
  });
}
