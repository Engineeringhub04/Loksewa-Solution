// Tests for the download-notification design (unified in v1.0.124):
// ONE progress entry on the alert channel with onlyAlertOnce (first
// post alerts, ticks stay quiet) under the progress id, and the
// completion post alone on the completion id — presented fresh at
// settle after the progress id is cancelled — plus the completion
// title design ("Download Complete 🎉" title, file name as body).
// Pure copy/id logic only — the plugin calls themselves are not
// mocked, following the push_foreground_test.dart approach.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/push_notification_service.dart';
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

const _copy = PushNotificationService.downloadCompletionCopy;
const _body = PushNotificationService.downloadProgressBody;

void main() {
  group('notification ids (unified design, v1.0.124)', () {
    test('completion id is distinct from the progress id', () {
      // Progress rides 778899 for the whole download; the completion
      // posts on 778900 ONLY at settle (never during the download), so
      // it always presents as a fresh notification.
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
