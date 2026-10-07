import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// "Report a Problem" submission pipeline.
///
/// Mirrors, in order:
/// - `app/settings/report-problem.tsx` (screen flow)
/// - `src/core/messaging/support.ts` → `submitProblemReport`
///   (Cloudinary upload first, Google Form POST second, Firestore history copy
///   best-effort last)
/// - `src/core/media/cloudinary.ts` → `uploadImageToCloudinary`
///   (unsigned preset — no API secret is shipped, same as the Expo app)
///
/// The Cloudinary cloud name + unsigned upload preset below are PUBLIC
/// client-side credentials: the Expo app ships the identical values inside its
/// own bundle via `EXPO_PUBLIC_` env vars (unsigned uploads are designed for
/// this). They grant upload-only access to the preset's folder.
class ScreenshotPicker {
  /// Dart side of the system image picker.
  ///
  /// There is no `image_picker` dependency (and none may be added), so picking
  /// goes through this tiny channel. The NATIVE side (~30 lines of Kotlin in
  /// `MainActivity.configureFlutterEngine`) is not part of this file — it must:
  /// 1. `MethodChannel(messenger, "loksewa_solution/media")`
  /// 2. on `"pickImage"`: launch `Intent(ACTION_OPEN_DOCUMENT)` with
  ///    `type = "image/*"`, `CATEGORY_OPENABLE`, `FLAG_GRANT_READ_URI_PERMISSION`
  /// 3. on result: read the content URI's bytes via `contentResolver`
  ///    (downscale if huge) and `result.success(bytes)`; on cancel,
  ///    `result.success(null)`.
  static const _channel = MethodChannel('loksewa_solution/media');

  /// Opens the system gallery. Returns the image bytes, or `null` when the
  /// user cancels. Throws [ScreenshotPickerUnavailable] when the native side
  /// is not wired yet, so the UI can explain instead of hanging.
  static Future<Uint8List?> pickImage() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('pickImage');
      return (bytes == null || bytes.isEmpty) ? null : bytes;
    } on MissingPluginException {
      throw ScreenshotPickerUnavailable();
    }
  }

  /// Launches the system camera app. Returns downscaled JPEG bytes, or `null`
  /// when the user cancels. Throws [ScreenshotPickerUnavailable] when the
  /// native side is not wired yet, so the UI can explain instead of hanging.
  static Future<Uint8List?> captureImage() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('captureImage');
      return (bytes == null || bytes.isEmpty) ? null : bytes;
    } on MissingPluginException {
      throw ScreenshotPickerUnavailable();
    }
  }
}

class ScreenshotPickerUnavailable implements Exception {
  @override
  String toString() => 'ScreenshotPickerUnavailable';
}

/// Unsigned Cloudinary image upload with determinate progress.
/// Mirrors `uploadImageToCloudinary` in `src/core/media/cloudinary.ts`.
class CloudinaryUploader {
  static const _cloudName = 'dw7gg0fhc';
  static const _uploadPreset = 'lsphotos';
  // Same folder the Expo app uses for every upload (AppConfig.media.cloudinary).
  static const _folder = 'profile-photos';

  static Future<String> uploadImage(
    Uint8List bytes, {
    void Function(double fraction)? onProgress,
  }) async {
    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final total = bytes.length;
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = _folder
      ..files.add(http.MultipartFile(
        'file',
        _countedStream(bytes, (sent) => onProgress?.call(sent / total)),
        total,
        filename: 'screenshot.jpg',
      ));

    final streamed = await request.send().timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('CLOUDINARY_TIMEOUT'),
        );
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('CLOUDINARY_UPLOAD_FAILED_${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('CLOUDINARY_BAD_RESPONSE');
    }
    final url = data['secure_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception(data['error']?['message'] ?? 'CLOUDINARY_BAD_RESPONSE');
    }
    onProgress?.call(1);
    return url;
  }

  /// Answer-sheet PDF upload — mirrors `uploadPdfToCloudinary` in
  /// `src/core/media/cloudinary.ts`: the `raw/upload` endpoint, same
  /// unsigned preset, `exam-answers` folder.
  static Future<String> uploadAnswerPdf(
    Uint8List bytes,
    String filename, {
    void Function(double fraction)? onProgress,
  }) async {
    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/raw/upload');
    final total = bytes.length;
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'exam-answers'
      ..files.add(http.MultipartFile(
        'file',
        _countedStream(bytes, (sent) => onProgress?.call(sent / total)),
        total,
        filename: filename,
        contentType: http_parser.MediaType('application', 'pdf'),
      ));

    final streamed = await request.send().timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException('CLOUDINARY_TIMEOUT'),
        );
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('CLOUDINARY_UPLOAD_FAILED_${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('CLOUDINARY_BAD_RESPONSE');
    }
    final url = data['secure_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception(data['error']?['message'] ?? 'CLOUDINARY_BAD_RESPONSE');
    }
    onProgress?.call(1);
    return url;
  }

  /// Byte-chunked stream so the UI can show real upload progress
  /// (the `http` package exposes no upload-progress events itself —
  /// same reason the Expo app uses XMLHttpRequest instead of fetch).
  static Stream<List<int>> _countedStream(
    Uint8List bytes,
    void Function(int sent) onChunk,
  ) async* {
    const chunkSize = 32 * 1024;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = min(i + chunkSize, bytes.length);
      yield bytes.sublist(i, end);
      onChunk(end);
    }
  }
}

/// Submits a problem report: screenshot → Cloudinary, then the Google Form
/// (relayed to Discord by Apps Script), then a best-effort Firestore history
/// copy. Mirrors `submitProblemReport` in `src/core/messaging/support.ts`.
///
/// A failed screenshot upload is NOT a failed report — the marker text goes in
/// instead and the description is still delivered.
class ReportService {
  // Keep in sync with android/app/build.gradle versionName.
  static const appVersion = '1.0.4';

  // Google Form field ids — mirrors AppConfig.messaging.googleForm in the
  // Expo app (taken from the form's "Get pre-filled link").
  static const _formId =
      '1FAIpQLSc8fAOhc793cp8aMOAKymwtGYLT504S-yjBNixCSE8dgokGQQ';
  static const _entries = {
    'type': 'entry.592505579',
    'name': 'entry.1756370732',
    'email': 'entry.2059602454',
    'message': 'entry.633453203',
    'rating': 'entry.2878998',
    'questionReference': 'entry.168055861',
    'issueCategory': 'entry.1740941696',
    'appVersion': 'entry.1821448113',
    'platform': 'entry.458970457',
    'userId': 'entry.2072267690',
  };

  static Future<void> submitProblemReport({
    required String category,
    required String description,
    Uint8List? screenshotBytes,
    void Function(double fraction)? onUploadProgress,
  }) async {
    var body = description.trim();

    if (screenshotBytes != null) {
      try {
        final url = await CloudinaryUploader.uploadImage(
          screenshotBytes,
          onProgress: onUploadProgress,
        );
        body = '$body\n\nScreenshot: $url';
      } catch (_) {
        // Same fallback the Expo app uses — the report must not be lost
        // because the screenshot upload wobbled.
        body = '$body\n\n[User attached a screenshot, but the upload failed]';
      }
    }

    await _submitToGoogleForm(
      type: 'report',
      issueCategory: 'app-problem / $category',
      message: body,
    );

    // Best-effort history copy — the report already reached support.
    try {
      final reporterName = await _createReportHistory(category, body);
      // Fire-and-forget admin push — reached only when the history write
      // succeeded; never blocks the caller.
      final oneLine = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final preview = oneLine.length > 80 ? '${oneLine.substring(0, 80)}…' : oneLine;
      unawaited(AdminNotifyService.notifyAdmin(
        kind: 'report',
        title: 'New Report 📝',
        body: '$reporterName reported an issue: $category — $preview',
        deepLink: '/admin/report-history',
      ));
    } catch (_) {}
  }

  /// Contact Us — free-text message from the user.
  /// Mirrors `submitContactMessage` in `src/core/messaging/support.ts`.
  static Future<void> submitContactMessage(String message) async {
    await _submitToGoogleForm(
      type: 'contact',
      issueCategory: '',
      message: message,
    );
  }

  /// App feedback with a 1–5 star rating.
  /// Mirrors `submitFeedback` in `src/core/messaging/support.ts`: the row
  /// stays readable in the sheet even when the user rates without commenting.
  static Future<void> submitFeedback(int rating, String message) async {
    await _submitToGoogleForm(
      type: 'feedback',
      issueCategory: '',
      message: message.isEmpty ? '(no comment)' : message,
      rating: rating,
    );
  }

  static Future<String> _platformLabel() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final release = info.version.release;
      return 'Android $release · Flutter $appVersion';
    } catch (_) {
      return 'Android · Flutter $appVersion';
    }
  }

  /// Report an issue with a specific exam/quiz question (manual entry screen).
  /// Mirrors `submitQuestionReport` in `src/core/messaging/support.ts`: the
  /// Google Form POST (the copy support actually reads) and the private
  /// Firestore report-history copy are awaited TOGETHER — a Form failure is
  /// a visible failure, exactly like the Expo app.
  static Future<void> submitQuestionReport({
    required String questionRef,
    required String issue,
    required String description,
  }) async {
    final ref = questionRef.trim();
    final body = description.trim();
    String? reporterName;
    await Future.wait([
      _submitToGoogleForm(
        type: 'report',
        questionReference: ref,
        issueCategory: 'question / $issue',
        message: body,
      ),
      _createQuestionReportHistory(
        questionRef: ref,
        issue: issue,
        description: body,
      ).then((name) => reporterName = name),
    ]);
    // Fire-and-forget admin push — reached only when BOTH writes above
    // succeeded (Future.wait rethrows on any failure), never blocks caller.
    final preview = body.isEmpty
        ? ref
        : (body.length > 80 ? '${body.substring(0, 80)}…' : body);
    unawaited(AdminNotifyService.notifyAdmin(
      kind: 'report',
      title: 'New Report 📝',
      body: '$reporterName reported a question: $issue — $preview',
      deepLink: '/admin/report-history',
    ));
  }

  /// Mirrors the `createReportHistory` call inside the Expo
  /// `submitQuestionReport` — fixed source/target for the manual screen.
  ///
  /// Returns the reporter name (used for the admin push) after the history
  /// write succeeds.
  static Future<String> _createQuestionReportHistory({
    required String questionRef,
    required String issue,
    required String description,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) throw Exception('AUTH_REQUIRED');
    final idToken = await AuthService.getValidIdToken();
    final userDoc =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: idToken)
            .catchError((_) => null);
    final reporterName =
        (userDoc?['name'] ?? user.displayName ?? 'Anonymous').toString();

    final reportId = _randomId();
    await FirestoreRest.setDocument(
      'app_report_history/$reportId',
      {
        'reporterId': user.uid,
        'reporterName': reporterName,
        'reporterEmail': userDoc?['email'] ?? user.email,
        'reporterPhoto': userDoc?['photoURL'] ?? user.photoURL,
        'reporterCourseId': userDoc?['courseId'],
        'reporterSubcourseId': userDoc?['subcourseId'],
        'source': 'question',
        'targetType': 'question',
        'targetId': questionRef,
        'targetTitle': questionRef,
        'targetPreview': null,
        'contextLabel': 'Question · Manual report',
        'targetAuthorName': null,
        'targetAuthorPhoto': null,
        // The issue VALUE (e.g. 'wrong-answer') — the history list shows it
        // raw, exactly like the Expo record.
        'reason': issue,
        'description': description,
        'status': 'pending',
        'adminMessage': null,
        'adminResponses': [],
        'createdAt': FirestoreRest.serverTimestamp(),
        'reviewedAt': null,
      },
      idToken: idToken,
    );
    // Index the report ID on the user's doc for per-user history.
    // Rules deny LIST queries on app_report_history for non-admins.
    await _indexReportId(user.uid, reportId, idToken);
    return reporterName;
  }

  static Future<void> _submitToGoogleForm({
    required String type,
    required String issueCategory,
    required String message,
    String? questionReference,
    int? rating,
  }) async {
    final user = AuthService.currentUser;
    final displayName = user?.displayName?.trim();
    final uid = user?.uid ?? 'guest';
    final userIdField = (displayName != null && displayName.isNotEmpty)
        ? '$displayName ($uid)'
        : uid;

    final fields = <String, String>{
      _entries['type']!: type,
      _entries['name']!: displayName ?? '',
      _entries['email']!: user?.email ?? '',
      _entries['message']!: message,
      _entries['rating']!: rating != null ? '$rating' : '',
      _entries['questionReference']!: questionReference ?? '',
      _entries['issueCategory']!: issueCategory,
      _entries['appVersion']!: appVersion,
      _entries['platform']!: await _platformLabel(),
      _entries['userId']!: userIdField,
    };
    final body = fields.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final res = await http
        .post(
          Uri.parse('https://docs.google.com/forms/d/e/$_formId/formResponse'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('GOOGLE_FORM_SUBMIT_FAILED_${res.statusCode}');
    }
  }

  /// Mirrors `createReportHistory` in
  /// `src/core/firebase/services/reportHistory.ts`.
  static Future<String> _createReportHistory(
      String category, String message) async {
    final user = AuthService.currentUser;
    if (user == null) return '';
    final idToken = await AuthService.getValidIdToken();
    final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: idToken)
        .catchError((_) => null);
    final reporterName =
        (userDoc?['name'] ?? user.displayName ?? 'Anonymous').toString();

    final reportId = _randomId();
    await FirestoreRest.setDocument(
      'app_report_history/$reportId',
      {
        'reporterId': user.uid,
        'reporterName': reporterName,
        'reporterEmail': userDoc?['email'] ?? user.email,
        'reporterPhoto': userDoc?['photoURL'] ?? user.photoURL,
        'reporterCourseId': userDoc?['courseId'],
        'reporterSubcourseId': userDoc?['subcourseId'],
        'source': 'app',
        'targetType': 'app',
        'targetId': 'app-problem',
        'targetTitle': category,
        'targetPreview': null,
        'contextLabel': 'App · Report a Problem',
        'targetAuthorName': null,
        'targetAuthorPhoto': null,
        'reason': category,
        'description': message,
        'status': 'pending',
        'adminMessage': null,
        'adminResponses': [],
        'createdAt': FirestoreRest.serverTimestamp(),
        'reviewedAt': null,
      },
      idToken: idToken,
    );
    // Index the report ID on the user's doc for per-user history.
    // Rules deny LIST queries on app_report_history for non-admins.
    await _indexReportId(user.uid, reportId, idToken);
    return reporterName;
  }

  /// Best-effort index of a report ID into the reporter's own doc.
  /// Never throws — the report itself is already saved.
  static Future<void> _indexReportId(
      String uid, String reportId, String idToken) async {
    try {
      final userDoc = await FirestoreRest.getDocument('users/$uid',
          idToken: idToken);
      final ids = <String>[
        for (final e in (userDoc?['reportIds'] as List? ?? [])) e.toString(),
      ];
      if (!ids.contains(reportId)) {
        ids.add(reportId);
        await FirestoreRest.updateDocument(
            'users/$uid', {'reportIds': ids},
            idToken: idToken);
      }
    } catch (_) {
      // Best-effort only; the admin backfill can repair it.
    }
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
