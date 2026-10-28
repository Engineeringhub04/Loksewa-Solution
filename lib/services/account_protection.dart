import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/cf_api.dart';

/// Blacklist (app_deleted_users) enforcement + account-field backfills.
///
/// NOTE 1 — BLACKLIST = HARD BLOCK: a blacklisted email may never sign up or
/// log in again; only an admin removing the row from Deleted Users frees it.
///
/// Phase-3: the client-side pre-checks are RETIRED. The loksewa-api checks
/// the blacklist server-side on signup/login/Google sign-in and refuses
/// with 403 'blacklisted' — the verdict is authoritative and the auth
/// screens map that error to [blacklistedMessage]. (The old Firestore
/// query was fail-open under the rules anyway, and the old worker
/// pre-check duplicated what the server now decides atomically.)
class AccountProtection {
  /// Message shown when a blacklisted email tries to sign up / log in.
  static String blacklistedMessage() => AppLanguage.tr(
        'This account has been removed and cannot be used again. Please contact support if you believe this is a mistake.',
        'यो खाता हटाइएको छ र फेरि प्रयोग गर्न सकिँदैन। गल्ती भएको लागेमा कृपया सहयोगसँग सम्पर्क गर्नुहोस्।',
      );

  /// NOTE 3 backfill: if the profile has no `platform` field, set it to
  /// 'App' via PATCH /me. Best-effort — never throws. The [uid] parameter
  /// is kept for signature parity; identity rides the Bearer token.
  static Future<void> backfillPlatformIfMissing(String uid) async {
    if (uid.isEmpty) return;
    try {
      final doc = await CfApi.getMe();
      if (doc == null) return;
      final platform = doc['platform'];
      if (platform is String && platform.trim().isNotEmpty) return;
      await CfApi.patchMe({'platform': 'App'});
    } catch (_) {
      // Best-effort only.
    }
  }
}
