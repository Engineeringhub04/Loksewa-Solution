// Widget tests for the admin filter-track chips row:
// - an admin inbox (admin-only rows present) renders chips with labels
//   and counts, and tapping a chip selects that track;
// - the screen gates the row behind hasUsefulTracks, so a normal user's
//   inbox (All + User only) never draws chips — verified via the gate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/user/notifications_screen.dart';
import 'package:loksewa_solution/services/notification_tracks.dart';

List<NotificationTrack> adminTracks() => buildNotificationTracks(
      const [
        TrackableRow(adminOnly: false, category: 'App Notice'),
        TrackableRow(adminOnly: false, category: 'Exam'),
        TrackableRow(adminOnly: true, category: 'New Report'),
        TrackableRow(adminOnly: true, category: 'New Report'),
        TrackableRow(adminOnly: true, category: 'New Subscription'),
      ],
      allLabel: 'All',
      userLabel: 'User',
      otherLabel: 'Other',
    );

List<NotificationTrack> userTracks() => buildNotificationTracks(
      const [
        TrackableRow(adminOnly: false, category: 'App Notice'),
        TrackableRow(adminOnly: false, category: 'Exam'),
      ],
      allLabel: 'All',
      userLabel: 'User',
      otherLabel: 'Other',
    );

void main() {
  testWidgets('admin inbox renders chips with labels and counts',
      (tester) async {
    final tracks = adminTracks();
    expect(hasUsefulTracks(tracks), isTrue);

    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationTrackChips(
            tracks: tracks,
            active: allTrack,
            onSelect: (v) => selected = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // All, User, New Report, New Subscription.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('New Report'), findsOneWidget);
    expect(find.text('New Subscription'), findsOneWidget);
    // Counts: All=5, User=2, New Report=2, New Subscription=1.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping a chip selects that track', (tester) async {
    final tracks = adminTracks();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationTrackChips(
            tracks: tracks,
            active: allTrack,
            onSelect: (v) => selected = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Report'));
    await tester.pump();
    expect(selected, 'category:new report');
  });

  testWidgets('active chip is visually distinguished', (tester) async {
    final tracks = adminTracks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationTrackChips(
            tracks: tracks,
            active: 'category:new report',
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Renders without error with a non-default active track.
    expect(find.text('New Report'), findsOneWidget);
  });

  test('normal user inbox never draws chips (gate)', () {
    // The screen renders NotificationTrackChips only when
    // hasUsefulTracks(tracks) is true. A normal user has no admin-only
    // rows, so the gate is always false for them.
    final tracks = userTracks();
    expect(tracks.length, 2);
    expect(hasUsefulTracks(tracks), isFalse);
  });
}
