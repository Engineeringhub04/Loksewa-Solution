import 'package:flutter/foundation.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Blacklist (app_deleted_users) enforcement + account-field backfills.
///
/// NOTE 1 — BLACKLIST = HARD BLOCK: a blacklisted email may never sign up or
/// log in again; only an admin removing the row from Deleted Users frees it.
///
/// The check queries `app_deleted_users` where email == the user's email. It
/// is FAIL-OPEN on query error: the Firestore rules currently allow only
/// admins to read app_deleted_users, so until the rules are updated to let a
/// signed-in user read their own blacklist row, the query is denied and the
/// flow is allowed through (with a debugPrint warning). A confirmed HIT is
/// always a hard block.
class AccountProtection {
  /// Message shown when a blacklisted email tries to sign up / log in.
  static String blacklistedMessage() => AppLanguage.tr(
        'This account has been removed and cannot be used again. Please contact support if you believe this is a mistake.',
        'यो खाता हटाइएको छ र फेरि प्रयोग गर्न सकिँदैन। गल्ती भएको लागेमा कृपया सहयोगसँग सम्पर्क गर्नुहोस्।',
      );

  /// True when [email] has a row in app_deleted_users. Never throws —
  /// any failure (rules deny, network) is treated as "not blacklisted"
  /// (fail-open) so a missing rules publish can never lock out real users.
  static Future<bool> isEmailBlacklisted(String email) async {
    final exact = email.trim();
    if (exact.isEmpty) return false;
    // Email matching is case-sensitive in Firestore; the wipe writes the
    // email as it was on the user doc, so probe both the as-typed and the
    // lowercased form.
    final probes = <String>{exact, exact.toLowerCase()};
    for (final probe in probes) {
      try {
        final docs = await ExamRest.runQuery(
          'app_deleted_users',
          where: ExamRest.fieldFilter('email', 'EQUAL', probe),
          limit: 1,
        );
        if (docs.isNotEmpty) return true;
      } catch (e) {
        // Fail-open: rules deny (admin-only read until the blacklist rule
        // is published) or the network is down — never block on this.
        debugPrint('blacklist check failed (fail-open): $e');
        return false;
      }
    }
    return false;
  }

  /// NOTE 3 backfill: if users/{uid} has no `platform` field, set it to
  /// 'App'. Best-effort — never throws.
  static Future<void> backfillPlatformIfMissing(String uid) async {
    if (uid.isEmpty) return;
    try {
      final token = await AuthService.getValidIdToken();
      final doc =
          await FirestoreRest.getDocument('users/$uid', idToken: token);
      if (doc == null) return;
      final platform = doc['platform'];
      if (platform is String && platform.trim().isNotEmpty) return;
      await FirestoreRest.updateDocument(
        'users/$uid',
        {'platform': 'App'},
        idToken: token,
      );
    } catch (_) {
      // Best-effort only.
    }
  }
}
