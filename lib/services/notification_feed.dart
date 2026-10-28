import 'cf_api.dart';

/// The merged notification feed behind GET /notifications — the single
/// fetch shared by the Home header badge (home_tab.dart) and the
/// Notifications inbox (notifications_screen.dart), replacing the three
/// Firestore collection reads both used to make independently.
///
/// Rows are flat maps with Firestore field names: personal inbox rows
/// (durable `read` field), global campaign rows and exam-push rows.
class NotificationFeed {
  final List<Map<String, dynamic>> personal;
  final List<Map<String, dynamic>> global;
  final List<Map<String, dynamic>> exam;

  const NotificationFeed({
    required this.personal,
    required this.global,
    required this.exam,
  });
}

/// Fetches the feed for the signed-in user (Bearer). Throws on failure —
/// callers keep their existing best-effort handling.
Future<NotificationFeed> fetchNotificationFeed() async {
  final feed = await CfApi.getNotifications();
  return NotificationFeed(
    personal: feed.personal,
    global: feed.global,
    exam: feed.exam,
  );
}
