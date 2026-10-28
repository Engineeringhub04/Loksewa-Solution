import 'cf_api.dart';

/// Phase-3 admin gate for the in-app /admin screens.
///
/// The check is unified on GET /me: the signed-in user's row must carry
/// the admin role (role == 'admin', or the legacy isAdmin flag the
/// migrated rows carry). The worker ALSO re-checks the role server-side
/// on every /admin/* endpoint — this gate only decides whether a screen
/// shows its content or its existing not-admin state.
bool isAdminMe(Map<String, dynamic>? me) =>
    me != null && (me['role'] == 'admin' || CfJson.asBool(me['isAdmin']));

/// Fetches GET /me and answers the gate. Any failure reads as not-admin.
Future<bool> fetchIsAdmin() async {
  try {
    return isAdminMe(await CfApi.getMe());
  } catch (_) {
    return false;
  }
}
