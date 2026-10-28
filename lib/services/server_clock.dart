import 'dart:io';

import 'auth_service.dart';
import 'cf_api.dart';

/// Server-corrected clock — mirrors serverNow()/noteServerTime() in
/// firestoreRest.ts from the Expo app.
///
/// Every HTTP response carries a `Date` header with the server's time;
/// [updateFromHttpDate] (called from the response paths of [CfApi] and,
/// for the remaining mirror traffic, [FirestoreRest]) records the skew
/// between that and the device clock. [nowUtc] is the device clock
/// corrected by that skew, so winding the phone clock cannot unlock
/// future-dated content (e.g. tomorrow's daily test). Never throws.
class ServerClock {
  static Duration _offset = Duration.zero;
  static DateTime? _lastSync;

  /// Record the server time from an HTTP `Date` header, e.g.
  /// "Tue, 29 Sep 2026 06:55:21 GMT". Parse failures are ignored silently.
  static void updateFromHttpDate(String? dateHeader) {
    if (dateHeader == null || dateHeader.isEmpty) return;
    try {
      final serverTime = HttpDate.parse(dateHeader).toUtc();
      _offset = serverTime.difference(DateTime.now().toUtc());
      _lastSync = DateTime.now();
    } catch (_) {
      // Not a valid HTTP date — keep the previous offset.
    }
  }

  /// Best-known current UTC time: device clock corrected by the last
  /// server-observed skew (zero until the first response arrives).
  static DateTime nowUtc() => DateTime.now().toUtc().add(_offset);

  /// Refresh the skew when it is older than 10 minutes. Does one cheap
  /// Cloudflare read (GET /config); the response `Date` header refreshes
  /// the offset through the hook in [CfApi]. Silent when signed out or
  /// the read fails — [nowUtc] then falls back to the device clock.
  static Future<void> ensureSynced() async {
    final last = _lastSync;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await CfApi.getConfig();
    } catch (_) {
      // Offline or transient failure — keep the previous offset.
    }
  }
}
