import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/notification_tracks.dart';

TrackableRow row(bool adminOnly, String category) =>
    TrackableRow(adminOnly: adminOnly, category: category);

List<NotificationTrack> build(
  List<TrackableRow> items, {
  String allLabel = 'All',
  String userLabel = 'User',
  String otherLabel = 'Other',
}) =>
    buildNotificationTracks(
      items,
      allLabel: allLabel,
      userLabel: userLabel,
      otherLabel: otherLabel,
    );

void main() {
  group('buildNotificationTracks', () {
    test('normal user rows produce only All + User (no chips drawn)', () {
      final tracks = build([
        row(false, 'App Notice'),
        row(false, 'Exam'),
        row(false, 'App Notice'),
      ]);
      expect(tracks.length, 2);
      expect(tracks[0].value, allTrack);
      expect(tracks[0].label, 'All');
      expect(tracks[0].count, 3);
      expect(tracks[1].value, userTrack);
      expect(tracks[1].count, 3);
      // Two tracks => hasUsefulTracks false => no chips for normal users.
      expect(hasUsefulTracks(tracks), isFalse);
    });

    test('admin rows get their own category tracks; counts add up', () {
      final tracks = build([
        row(false, 'App Notice'),
        row(false, 'Exam'),
        row(true, 'New Report'),
        row(true, 'New Report'),
        row(true, 'New Subscription'),
      ]);
      // All, User, New Purchase... sorted alphabetically: New Report, New Subscription
      expect(tracks.length, 4);
      expect(tracks[0].count, 5); // All
      expect(tracks[1].count, 2); // User
      expect(tracks[2].label, 'New Report');
      expect(tracks[2].count, 2);
      expect(tracks[2].value, 'category:new report');
      expect(tracks[3].label, 'New Subscription');
      expect(tracks[3].count, 1);
      // 2 + 2 + 1 = 5 = All count.
      final adminTotal =
          tracks.skip(2).fold<int>(0, (sum, t) => sum + t.count);
      expect(tracks[1].count + adminTotal, tracks[0].count);
      expect(hasUsefulTracks(tracks), isTrue);
    });

    test('category matching is case-insensitive', () {
      final tracks = build([
        row(true, 'New Report'),
        row(true, 'new report'),
        row(true, 'NEW REPORT'),
      ]);
      expect(tracks.length, 3); // All, User, one category
      expect(tracks[2].count, 3);
    });

    test('empty category falls back to other label', () {
      final tracks = build([row(true, '   ')]);
      expect(tracks.length, 3);
      expect(tracks[2].label, 'Other');
      expect(tracks[2].value, 'category:');
    });

    test('empty list still yields All + User with zero counts', () {
      final tracks = build([]);
      expect(tracks.length, 2);
      expect(tracks[0].count, 0);
      expect(tracks[1].count, 0);
      expect(hasUsefulTracks(tracks), isFalse);
    });
  });

  group('filterByTrack', () {
    final items = [
      row(false, 'App Notice'),
      row(true, 'New Report'),
      row(true, 'New Purchase'),
    ];

    test('user track shows only non-admin rows', () {
      final out = filterByTrack<TrackableRow>(
        items,
        userTrack,
        isAdminOnly: (i) => i.adminOnly,
        categoryOf: (i) => i.category,
      );
      expect(out.length, 1);
      expect(out.first.adminOnly, isFalse);
    });

    test('category track shows only matching admin rows', () {
      final out = filterByTrack<TrackableRow>(
        items,
        'category:new report',
        isAdminOnly: (i) => i.adminOnly,
        categoryOf: (i) => i.category,
      );
      expect(out.length, 1);
      expect(out.first.category, 'New Report');
    });

    test('unknown track falls back to everything', () {
      final out = filterByTrack<TrackableRow>(
        items,
        'bogus',
        isAdminOnly: (i) => i.adminOnly,
        categoryOf: (i) => i.category,
      );
      expect(out.length, 3);
    });

    test('all track shows everything', () {
      final out = filterByTrack<TrackableRow>(
        items,
        allTrack,
        isAdminOnly: (i) => i.adminOnly,
        categoryOf: (i) => i.category,
      );
      expect(out.length, 3);
    });
  });

  group('resolveTrack', () {
    test('keeps a valid selection', () {
      final tracks = build([row(true, 'New Report')]);
      expect(resolveTrack(tracks, 'category:new report'),
          'category:new report');
    });

    test('falls back to all when the track vanished', () {
      final tracks = build([row(false, 'App Notice')]);
      expect(resolveTrack(tracks, 'category:new report'), allTrack);
    });
  });

  group('hasUsefulTracks', () {
    test('false for 2 or fewer tracks', () {
      expect(hasUsefulTracks(build([])), isFalse);
      expect(hasUsefulTracks(build([row(false, 'x')])), isFalse);
    });

    test('true once an admin category exists', () {
      expect(hasUsefulTracks(build([row(true, 'New Report')])), isTrue);
    });
  });
}
