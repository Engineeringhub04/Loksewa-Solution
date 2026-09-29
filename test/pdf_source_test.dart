import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/pdf_source.dart';

// Pure-function tests for the pdfSource.ts port — no network involved.
void main() {
  group('driveFileId', () {
    test('extracts id from /file/d/<id>/view share links', () {
      expect(
        PdfSource.driveFileId(
            'https://drive.google.com/file/d/1wdiV-Uh8sAVtBCJ2K4KjxrPGk42MLGAZ/view?usp=sharing'),
        '1wdiV-Uh8sAVtBCJ2K4KjxrPGk42MLGAZ',
      );
    });

    test('extracts id from ?id= links', () {
      expect(
        PdfSource.driveFileId(
            'https://drive.google.com/open?id=1wdiV-Uh8sAVtBCJ2K4KjxrPGk42MLGAZ'),
        '1wdiV-Uh8sAVtBCJ2K4KjxrPGk42MLGAZ',
      );
    });

    test('returns null for non-drive urls', () {
      expect(
          PdfSource.driveFileId('https://example.com/syllabus.pdf'), isNull);
    });
  });

  group('toDirectPdfUrl', () {
    test('converts drive share links to uc?export=download', () {
      expect(
        PdfSource.toDirectPdfUrl(
            'https://drive.google.com/file/d/ABC123/view?usp=sharing'),
        'https://drive.google.com/uc?export=download&id=ABC123',
      );
    });

    test('converts dropbox links to dl=1', () {
      expect(
        PdfSource.toDirectPdfUrl('https://www.dropbox.com/s/xyz/file.pdf?dl=0'),
        'https://www.dropbox.com/s/xyz/file.pdf?dl=1',
      );
    });

    test('leaves direct pdf urls untouched', () {
      const url = 'https://example.com/files/syllabus.pdf';
      expect(PdfSource.toDirectPdfUrl(url), url);
    });
  });

  group('candidateUrls', () {
    test('drive share link yields usercontent-first candidates', () {
      final urls = PdfSource.candidateUrls(
          'https://drive.google.com/file/d/ABC123/view?usp=sharing');
      expect(urls.length, 3);
      expect(
        urls[0],
        'https://drive.usercontent.google.com/download?id=ABC123&export=download&confirm=t',
      );
      expect(urls[1].contains('confirm=t'), isTrue);
      expect(urls[2],
          'https://drive.google.com/uc?export=download&id=ABC123');
    });

    test('plain url yields a single candidate', () {
      const url = 'https://example.com/a.pdf';
      expect(PdfSource.candidateUrls(url), [url]);
    });
  });

  group('looksLikePdf', () {
    test('accepts %PDF- header', () {
      expect(
        PdfSource.looksLikePdf(
            Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31])),
        isTrue,
      );
    });

    test('rejects html pages', () {
      expect(
        PdfSource.looksLikePdf(
            Uint8List.fromList('<html'.codeUnits)),
        isFalse,
      );
    });

    test('rejects short/empty input', () {
      expect(PdfSource.looksLikePdf(Uint8List(0)), isFalse);
      expect(
          PdfSource.looksLikePdf(Uint8List.fromList([0x25, 0x50])), isFalse);
    });
  });
}
