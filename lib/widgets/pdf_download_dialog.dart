import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/app_language.dart';
import 'app_modal_shell.dart';

/// Byte-counted PDF download with a live progress popup.
///
/// Flow: [PdfDownloadDialog] renders inside an [AppModalShell] popup, starts
/// downloading [url] immediately, shows real byte-counted progress, saves the
/// finished file into the phone's Downloads folder (app-documents fallback —
/// the same convention as the Keep Notes backup export and the checkout QR
/// download), then calls [onDone] so the caller can close the popup and show
/// a toast. No share sheet is opened.
///
/// Cancellation: closing the popup disposes the dialog, which aborts the
/// in-flight request and discards the partial download.
class PdfDownloadDialog extends StatefulWidget {
  final String url;
  final String fileName;
  final VoidCallback onDone;
  final VoidCallback onClose;

  /// Test seams: override the network fetch and the destination directory.
  final Future<Uint8List> Function(
      String url, void Function(int received, int? total) onProgress)?
      downloadFn;
  final Future<Directory> Function()? resolveDir;

  const PdfDownloadDialog({
    super.key,
    required this.url,
    required this.fileName,
    required this.onDone,
    required this.onClose,
    this.downloadFn,
    this.resolveDir,
  });

  @override
  State<PdfDownloadDialog> createState() => _PdfDownloadDialogState();
}

/// Downloads [url] with byte-counted progress callbacks. Only the connection
/// has a hard timeout (30 s); a body stalled with no data for 90 s aborts.
/// [client] is a test seam (a fresh client is created when omitted).
Future<Uint8List> downloadPdfBytes(
  String url,
  void Function(int received, int? total) onProgress, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    final res = await c.send(req).timeout(const Duration(seconds: 30));
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
  } finally {
    c.close();
  }
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

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // Abort the in-flight request; the guards in _start drop the result.
    _cancelled = true;
    _client?.close();
    _client = null;
    super.dispose();
  }

  Future<Uint8List> _defaultDownload(
      String url, void Function(int received, int? total) onProgress) {
    _client = http.Client();
    return downloadPdfBytes(url, onProgress, client: _client);
  }

  Future<void> _start() async {
    setState(() {
      _received = 0;
      _total = null;
      _error = null;
      _cancelled = false;
    });
    try {
      final bytes = await (widget.downloadFn ?? _defaultDownload)(
        widget.url,
        (received, total) {
          if (!mounted || _cancelled) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (_cancelled || !mounted) return;
      final dir = await (widget.resolveDir ?? resolveDownloadDir)();
      final file = File('${dir.path}/${widget.fileName}');
      // Sync write: async dart:io writes never complete in the FakeAsync
      // test zone (same as Directory.create). The buffer is already fully
      // downloaded at this point, so this is a single fast flush.
      file.writeAsBytesSync(bytes, flush: true);
      if (_cancelled || !mounted) return;
      widget.onDone();
    } catch (_) {
      if (_cancelled || !mounted) return;
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
