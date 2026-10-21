// Tests for the download-notification redesign (v1.0.123): separate
// ids per phase — progress on its own silent id/channel, start +
// completion alerts on the alert id/channel — plus the completion
// title design ("Download Complete 🎉" title, file name as body).
// Pure copy logic only — the plugin calls themselves are not mocked,
// following the push_foreground_test.dart approach.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/push_notification_service.dart';
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

const _copy = PushNotificationService.downloadCompletionCopy;
const _body = PushNotificationService.downloadProgressBody;

void main() {
  group('split notification ids (v1.0.123)', () {
    test('alert id is distinct from the progress id', () {
      expect(pdfDownloadAlertNotificationId, 778900);
      expect(pdfDownloadNotificationId, 778899);
      expect(pdfDownloadAlertNotificationId,
          isNot(equals(pdfDownloadNotificationId)));
    });
  });

  group('downloadCompletionCopy', () {
    test('success to public Downloads: title design + saved line', () {
      final c = _copy(
        success: true,
        fileName: 'Checked-Answer-Test.pdf',
        toDownloads: true,
      );
      expect(c.title, 'Download Complete 🎉');
      expect(c.body, 'Checked-Answer-Test.pdf');
      expect(c.bigText, 'Checked-Answer-Test.pdf\nSaved to Downloads');
    });

    test('success with app-folder fallback: no saved-to-Downloads line',
        () {
      final c = _copy(
        success: true,
        fileName: 'Checked-Answer-Test.pdf',
        toDownloads: false,
      );
      expect(c.title, 'Download Complete 🎉');
      expect(c.body, 'Checked-Answer-Test.pdf');
      expect(c.bigText, 'Checked-Answer-Test.pdf');
    });

    test('failure: failed title, file name body, no saved line', () {
      final c = _copy(
        success: false,
        fileName: 'Checked-Answer-Test.pdf',
        toDownloads: true,
      );
      expect(c.title, 'Download Failed ❌');
      expect(c.body, 'Checked-Answer-Test.pdf');
      expect(c.bigText, 'Checked-Answer-Test.pdf');
    });
  });

  group('downloadProgressBody', () {
    test('unknown total reads plain Downloading…', () {
      expect(_body(null), 'Downloading…');
    });

    test('known percent is interpolated', () {
      expect(_body(0), 'Downloading… 0%');
      expect(_body(45), 'Downloading… 45%');
      expect(_body(100), 'Downloading… 100%');
    });

    test('percent is clamped to 0–100', () {
      expect(_body(150), 'Downloading… 100%');
      expect(_body(-5), 'Downloading… 0%');
    });
  });
}
