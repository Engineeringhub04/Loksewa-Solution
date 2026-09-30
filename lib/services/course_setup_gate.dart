import 'auth_service.dart';
import 'firestore_rest.dart';

/// Course-setup gate — mirrors React's hasUserCourseSetup(uid):
/// `users/{uid}.courseSetupComplete === true` (written by the course-setup
/// screen on save). Returns null when the check can't be completed
/// (offline / expired token / any error) so each caller can pick its own
/// fallback: splash treats unknown as home (previous behavior), login
/// treats unknown as setup (React's .catch(() => false)).
class CourseSetupGate {
  static Future<bool?> isComplete(String uid) async {
    try {
      final idToken = await AuthService.getValidIdToken();
      final doc =
          await FirestoreRest.getDocument('users/$uid', idToken: idToken);
      return doc?['courseSetupComplete'] == true;
    } catch (_) {
      return null;
    }
  }
}
