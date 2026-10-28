import 'cf_api.dart';

/// Course-setup gate — mirrors React's hasUserCourseSetup(uid):
/// the profile's `courseSetupComplete === true` (written by the
/// course-setup screen on save, now via PATCH /me). Returns null when the
/// check can't be completed (offline / no CF session / any error) so each
/// caller can pick its own fallback: splash treats unknown as home
/// (previous behavior), login treats unknown as setup (React's
/// .catch(() => false)).
class CourseSetupGate {
  static Future<bool?> isComplete(String uid) async {
    try {
      final me = await CfApi.getMe();
      if (me == null) return null;
      // D1 may store the flag as a 'true' string — coerce either shape.
      return CfJson.asBool(me['courseSetupComplete']);
    } catch (_) {
      return null;
    }
  }
}
