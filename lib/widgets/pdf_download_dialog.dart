import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/app_language.dart';
import '../services/pdf_source.dart';
import '../services/public_downloads.dart';
import '../services/push_notification_service.dart';
import 'app_modal_shell.dart';

/// Stable notification id for PDF download PROGRESS (v1.0.120) — one
/// download popup exists at a time, so one id is enough. Its pair,
/// pdfDownloadAlertNotificationId (in push_notification_service.dart),
/// carries the start + completion alerts on their own channel
/// (split-id design, v1.0.123).
const int pdfDownloadNotificationId = 778899;

/// Byte-counted PDF download with a live progress popup.
///
/// Flow: [PdfDownloadDialog] renders inside an [AppModalShell] popup, starts
/// downloading [url] immediately, shows real byte-counted progress, saves the
/// finished file, then calls [onDone] so the caller can close the popup and
/// show a toast. No share sheet is opened. The fetch walks the in-app
/// viewer's candidate URLs ([PdfSource.candidateUrls]) so share-style
/// links (Drive/Dropbox) download the real PDF, not their HTML preview
/// page (v1.0.122).
///
/// Saving (v1.0.120): the file goes to the phone's REAL public Downloads
/// folder through the MediaStore channel ([PublicDownloads]) — the old
/// path_provider downloads dir is app-private and invisible in the
/// Downloads app. When the public save is unavailable (old Android,
/// channel failure) it falls back to that app-folder write, and
/// [onSaved] reports which happened so the caller's message stays
/// honest. On Android the progress also mirrors into system
/// notifications split by phase (v1.0.123): the progress entry lives
/// on its own silent id/channel from the first tick, a one-shot start
/// alert and the completion post ride a separate alert id/channel,
/// and settling cancels the progress entry so nothing stays stuck at
/// 100%. Bytes that fail the [looksLikePdf] sanity check are never
/// saved; they surface as a failed download instead.
///
/// Cancellation: closing the popup disposes the dialog, which aborts the
/// in-flight request and discards the partial download.
class PdfDownloadDialog extends StatefulWidget {
  final String url;
  final String fileName;
  final VoidCallback onDone;
  final VoidCallback onClose;

  /// Optional richer completion callback (v1.0.120): receives true when
  /// the file landed in the public Downloads folder, false when it fell
  /// back to the app folder. When provided it replaces [onDone].
  final void Function(bool savedToPublicDownloads)? onSaved;

  /// Mirror progress into the Android download notification.
  final bool notifyProgress;

  /// Test seams: override the network fetch and the destination directory.
  final Future<Uint8List> Function(
      String url, void Function(int received, int? total) onProgress)?
      downloadFn;
  final Future<Directory> Function()? resolveDir;

  /// Test seam: override the public-Downloads save (true = saved there).
  final Future<bool> Function(Uint8List bytes)? saveFn;

  const PdfDownloadDialog({
    super.key,
    required this.url,
    required this.fileName,
    required this.onDone,
    required this.onClose,
    this.onSaved,
    this.notifyProgress = true,
    this.downloadFn,
    this.resolveDir,
    this.saveFn,
  });

  @override
  State<PdfDownloadDialog> createState() => _PdfDownloadDialogState();
}

/// Sanity check for downloaded bytes (v1.0.121): a real PDF carries
/// the '%PDF-' magic within its first 1024 bytes (the spec tolerates
/// leading junk before the header). HTML error pages served with a
/// 200 status, empty bodies, and other non-PDF payloads fail — the
/// dialog treats them as a failed download and saves NOTHING, instead
/// of landing a corrupt file in the user's Downloads folder (the
/// phone viewer then reports it as "invalid format"). Delegates to
/// the single shared implementation in [PdfSource] (v1.0.122).
bool looksLikePdf(Uint8List bytes) => PdfSource.looksLikePdf(bytes);

/// Downloads the PDF behind [url] with byte-counted progress
/// callbacks, walking the SAME candidate URLs the in-app viewer uses
/// ([PdfSource.candidateUrls] — v1.0.122). A share-style link (Google
/// Drive `/view`, Dropbox) answers a plain GET with an HTTP-200 HTML
/// page instead of PDF bytes; each candidate is fetched in order and
/// the first whose bytes pass [looksLikePdf] wins. That is what the
/// raw single-GET version missed: v1.0.120 saved the HTML page as a
/// .pdf ("invalid format" in the phone viewer) and the v1.0.121 gate
/// then rejected it outright ("Download failed"). Non-share URLs
/// yield exactly one candidate — the URL itself — so they behave
/// exactly as before. Progress may restart from zero per candidate.
/// Throws when every candidate fails (transport error, non-200, or
/// non-PDF bytes). [client] is a test seam (a fresh client is created
/// when omitted) and is closed when the walk ends.
Future<Uint8List> downloadPdfBytes(
  String url,
  void Function(int received, int? total) onProgress, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    Object? lastError;
    for (final candidate in PdfSource.candidateUrls(url)) {
      try {
        final bytes = await _fetchCandidateBytes(candidate, onProgress,
            client: c);
        if (looksLikePdf(bytes)) return bytes;
        lastError = Exception('not a pdf');
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('download failed');
  } finally {
    c.close();
  }
}

/// One streamed GET of a single candidate URL with byte-counted
/// progress. Only the connection has a hard timeout (30 s); a body
/// stalled with no data for 90 s aborts. Does NOT close [client] —
/// the candidate walk in [downloadPdfBytes] owns it.
Future<Uint8List> _fetchCandidateBytes(
  String url,
  void Function(int received, int? total) onProgress, {
  required http.Client client,
}) async {
  final req = http.Request('GET', Uri.parse(url));
  final res = await client.send(req).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) {
    throw Exception('download failed (${res.statusCode})');
  }
  final chunks = <List<int>>[];
  var received = 0;
  await for (final chunk in res.stream.timeout(const Duration(seconds: 90))) {
    chunks.add(chunk);
    received += chunk.length;
    final total = res.contentLength;
    onProgress(received, (total != null && total > 0) ? total : null);
  }
  final out = Uint8List(received);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  if (out.isEmpty) throw Exception('empty file');
  return out;
}

/// Phone's Downloads folder, falling back to app documents (same convention
/// as the Keep Notes backup export and the checkout QR download).
Future<Directory> resolveDownloadDir() async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();
  return dir;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

class _PdfDownloadDialogState extends State<PdfDownloadDialog> {
  int _received = 0;
  int? _total;
  String? _error;
  bool _cancelled = false;
  http.Client? _client;

  /// Notification forwarding throttle: last integer percent posted, and
  /// when the last indeterminate update went out.
  int? _lastNotifiedPct;
  DateTime? _lastNotifyAt;

  /// True once the notification reached a final state (complete/failed)
  /// — dispose() then leaves it alone instead of cancelling it.
  bool _notifySettled = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // Abort the in-flight request; the guards in _start drop the result.
    _cancelled = true;
    // A user cancel mid-download dismisses the progress notification;
    // a settled one (complete/failed) stays in the tray.
    if (widget.notifyProgress && !_notifySettled) {
      unawaited(PushNotificationService.cancelDownloadNotification(
          id: pdfDownloadNotificationId));
    }
    _client?.close();
    _client = null;
    super.dispose();
  }

  Future<Uint8List> _defaultDownload(
      String url, void Function(int received, int? total) onProgress) {
    _client = http.Client();
    return downloadPdfBytes(url, onProgress, client: _client);
  }

  /// Default save: the URI-returning public-Downloads variant, so the
  /// completion notification can carry the saved file's content URI
  /// as its tap payload (v1.0.121).
  Future<String?> _defaultSaveUri(Uint8List bytes) =>
      PublicDownloads.saveToPublicDownloadsUri(bytes, widget.fileName);

  /// Mirrors byte progress into the Android notification, throttled:
  /// determinate progress posts only when the integer percent changes,
  /// indeterminate at most twice a second.
  void _forwardProgress(int received, int? total) {
    if (!widget.notifyProgress) return;
    final pct = (total != null && total > 0)
        ? ((received / total) * 100).floor()
        : null;
    final now = DateTime.now();
    if (pct != null) {
      if (pct == _lastNotifiedPct) return;
      _lastNotifiedPct = pct;
    } else {
      if (_lastNotifyAt != null &&
          now.difference(_lastNotifyAt!) <
              const Duration(milliseconds: 500)) {
        return;
      }
    }
    _lastNotifyAt = now;
    unawaited(PushNotificationService.showDownloadProgress(
      id: pdfDownloadNotificationId,
      fileName: widget.fileName,
      percent: pct,
    ));
  }

  void _settleNotification(bool success,
      {bool toDownloads = true, String? openUri}) {
    if (!widget.notifyProgress) return;
    _notifySettled = true;
    unawaited(PushNotificationService.finishDownloadNotification(
      id: pdfDownloadNotificationId,
      fileName: widget.fileName,
      success: success,
      toDownloads: toDownloads,
      openUri: success ? openUri : null,
    ));
  }

  Future<void> _start() async {
    setState(() {
      _received = 0;
      _total = null;
      _error = null;
      _cancelled = false;
      _lastNotifiedPct = null;
      _lastNotifyAt = null;
      _notifySettled = false;
    });
    try {
      final bytes = await (widget.downloadFn ?? _defaultDownload)(
        widget.url,
        (received, total) {
          if (!mounted || _cancelled) return;
          _forwardProgress(received, total);
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (_cancelled || !mounted) return;
      // v1.0.121: never save bytes that are not a PDF (e.g. an HTML
      // error page behind a 200) — a corrupt file in the public
      // Downloads folder is what the phone viewer calls "invalid
      // format". Treat it exactly like a failed download.
      if (!looksLikePdf(bytes)) {
        _settleNotification(false);
        setState(() => _error = 'download');
        return;
      }
      // Save: real public Downloads first (MediaStore channel); the
      // app-folder write is only the fallback. The default save also
      // returns the saved file's content URI for the completion
      // notification's tap-to-open payload; the saveFn test seam keeps
      // its bool shape (no URI — the notification then has no payload).
      final bool savedPublic;
      final String? savedUri;
      if (widget.saveFn != null) {
        savedPublic = await widget.saveFn!(bytes);
        savedUri = null;
      } else {
        savedUri = await _defaultSaveUri(bytes);
        savedPublic = savedUri != null;
      }
      if (_cancelled || !mounted) return;
      if (!savedPublic) {
        final dir = await (widget.resolveDir ?? resolveDownloadDir)();
        final file = File('${dir.path}/${widget.fileName}');
        // Sync write: async dart:io writes never complete in the FakeAsync
        // test zone (same as Directory.create). The buffer is already fully
        // downloaded at this point, so this is a single fast flush.
        file.writeAsBytesSync(bytes, flush: true);
      }
      if (_cancelled || !mounted) return;
      _settleNotification(true, toDownloads: savedPublic, openUri: savedUri);
      if (widget.onSaved != null) {
        widget.onSaved!(savedPublic);
      } else {
        widget.onDone();
      }
    } catch (_) {
      if (_cancelled || !mounted) return;
      _settleNotification(false);
      setState(() => _error = 'download');
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    // The shell's body region is white in both themes — use fixed ink colors.
    return AppModalShell(
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: (failed
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF1D4ED8))
              .withValues(alpha: 0.12),
        ),
        child: Icon(
          failed ? Icons.error_outline : Icons.download,
          size: 28,
          color:
              failed ? const Color(0xFFDC2626) : const Color(0xFF1D4ED8),
        ),
      ),
      tagLabel: AppLanguage.tr('Answer Sheet', 'उत्तरपुस्तिका'),
      title: Text(failed
          ? AppLanguage.tr('Download failed', 'डाउनलोड असफल भयो')
          : AppLanguage.tr('Downloading PDF', 'PDF डाउनलोड हुँदैछ')),
      body: failed ? _errorBody() : _progressBody(),
      footer: failed ? _errorFooter() : _progressFooter(),
      onClose: widget.onClose,
    );
  }

  Widget _progressBody() {
    final hasTotal = _total != null && _total! > 0;
    final progress = hasTotal ? _received / _total! : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.fileName,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            // null => indeterminate sweep while the total is unknown.
            value: progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF1D4ED8)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasTotal
              ? '${(progress! * 100).round()}% · ${_formatBytes(_received)} / ${_formatBytes(_total!)}'
              : '${_formatBytes(_received)} ${AppLanguage.tr('downloaded', 'डाउनलोड')}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _progressFooter() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        // Popping disposes the dialog, which aborts the download.
        onPressed: widget.onClose,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
      ),
    );
  }

  Widget _errorBody() {
    return Text(
      AppLanguage.tr(
          'Could not download the file. Please check your connection and try again.',
          'फाइल डाउनलोड हुन सकेन। कृपया आफ्नो इन्टरनेट जाँचेर पुनः प्रयास गर्नुहोस्।'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
    );
  }

  Widget _errorFooter() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.onClose,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(AppLanguage.tr('Close', 'बन्द गर्नुहोस्')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child:
                Text(AppLanguage.tr('Retry', 'पुनः प्रयास गर्नुहोस्')),
          ),
        ),
      ],
    );
  }
}
