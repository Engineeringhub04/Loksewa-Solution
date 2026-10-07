/// Track partition logic for the notification inbox — a port of
/// `src/core/notifications/tracks.ts` from the Expo app.
///
/// An admin's inbox carries two unrelated things: the notices they receive
/// as a user of the app, and the items that arrive because they are an
/// admin (reports, purchase requests, ...). Mixed into one stream, a busy
/// admin queue buries everything else, and there is no way to read just
/// one of the two.
///
/// The tracks PARTITION the inbox rather than overlapping it: "User" holds
/// everything a normal user would also see, and every admin-only category
/// gets a track of its own. The counts therefore add up to the "All"
/// count, which is what makes a row of chips readable at a glance.
///
/// Nothing here is configured anywhere. A track exists because a row of
/// that category is actually in the list right now — so the day a new
/// kind of admin feed starts producing rows, its track appears on its own,
/// with no new Firestore field and no change to this file.
library;

/// One filter chip. Shaped to drop straight into the chip row.
class NotificationTrack {
  final String value;
  final String label;
  final int count;

  const NotificationTrack({
    required this.value,
    required this.label,
    required this.count,
  });
}

const String allTrack = 'all';
const String userTrack = 'user';

/// Category tracks are namespaced so a category someone literally names
/// "all" or "user" cannot shadow one of the two fixed tracks.
const String categoryTrackPrefix = 'category:';

/// Minimal view of an inbox row for track computation.
class TrackableRow {
  final bool adminOnly;
  final String category;

  const TrackableRow({required this.adminOnly, required this.category});
}

/// Lower-cased so two spellings of the same category ("New Report" /
/// "new report") share one track. An empty string is a valid key — it is
/// the bucket for a row with no category, and no real category can trim
/// down to it.
String _categoryKey(String category) => category.trim().toLowerCase();

/// Builds the track list: [All, User, ...derived category tracks].
/// Derived tracks are sorted alphabetically by label rather than by
/// count — counts change on every pull-to-refresh, and chips that
/// reorder under the finger are worse than chips in a dull order.
List<NotificationTrack> buildNotificationTracks(
  List<TrackableRow> items, {
  required String allLabel,
  required String userLabel,
  required String otherLabel,
}) {
  var userCount = 0;
  final categories = <String, ({String label, int count})>{};

  for (final item in items) {
    if (!item.adminOnly) {
      userCount += 1;
      continue;
    }
    final key = _categoryKey(item.category);
    final existing = categories[key];
    if (existing != null) {
      categories[key] = (label: existing.label, count: existing.count + 1);
    } else {
      final label =
          item.category.trim().isEmpty ? otherLabel : item.category.trim();
      categories[key] = (label: label, count: 1);
    }
  }

  final derived = categories.entries.toList()
    ..sort((a, b) => a.value.label.compareTo(b.value.label));

  return [
    NotificationTrack(value: allTrack, label: allLabel, count: items.length),
    NotificationTrack(value: userTrack, label: userLabel, count: userCount),
    for (final e in derived)
      NotificationTrack(
        value: '$categoryTrackPrefix${e.key}',
        label: e.value.label,
        count: e.value.count,
      ),
  ];
}

/// The rows one track shows. An unknown track falls back to showing
/// everything.
List<T> filterByTrack<T>(
  List<T> items,
  String track, {
  required bool Function(T item) isAdminOnly,
  required String Function(T item) categoryOf,
}) {
  if (track == userTrack) {
    return items.where((item) => !isAdminOnly(item)).toList();
  }
  if (!track.startsWith(categoryTrackPrefix)) return items.toList();
  final wanted = track.substring(categoryTrackPrefix.length);
  return items
      .where((item) =>
          isAdminOnly(item) && _categoryKey(categoryOf(item)) == wanted)
      .toList();
}

/// Keeps the selection valid when the list changes underneath it — a track
/// disappears the moment its last row does. Resolving here instead of in
/// a setState means the list never renders one frame of an empty filter.
String resolveTrack(List<NotificationTrack> tracks, String selected) {
  return tracks.any((track) => track.value == selected) ? selected : allTrack;
}

/// Whether the chip row is worth drawing at all. Two tracks means All and
/// User hold the same rows, so the row would be decoration that does
/// nothing. Normal users therefore never see chips — byte-for-byte the
/// page it has always been.
bool hasUsefulTracks(List<NotificationTrack> tracks) => tracks.length > 2;
