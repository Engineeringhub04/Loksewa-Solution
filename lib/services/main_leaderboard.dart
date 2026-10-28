// Main leaderboard scoring + publish engine.
//
// Dart port of the React/Expo implementation:
//   - services/mainLeaderboard.ts (computeMainLeaderboardScore,
//     publishMainLeaderboardScore, throttle helpers, publicRowId)
//   - services/scoring.ts (POINTS constants and pure scoring helpers)
//   - firebase/services/profile.ts (writeUserStats, rank-only variant)
//
// Why two documents per publish (mirrors React):
// Firestore cannot query across per-user subcollections, and the private
// aggregate below is owner-read-only, so a leaderboard can never be built by
// reading other users' data directly. Every publish therefore writes twice:
//
//   users/{uid}/app_mainleaderboard/{subcourseId}  - private, full breakdown
//   app_main_leaderboard/{uid}__{subcourseId}      - public, one ranking row
//
// What a score is (mirrors React):
//   percent - PROGRESS: activity points as a percent of the total marks the
//             subcourse's content can yield. Starts near zero and climbs
//             slowly — no user hits 100% fast. The denominator is dynamic: it
//             comes from app_content_totals/{subcourseId} (per-field fallbacks
//             when fields are missing), so adding questions/models raises the
//             total and every percent eases down automatically (user spec,
//             2026-10-02).
//   points  - a cumulative EFFORT total: correct answers pay more than
//             attempts; completing something pays a small bonus. Only ever
//             grows, so consistent daily use is visibly rewarded.
//   accuracyPercent - weighted accuracy across the sources the user touched
//             ("how well am I doing"), kept for the stats card.
//
// Ranking is by points first; percent breaks ties between identical points.
//
// NOTE: the analytics-trend snapshot (React's recordAnalyticsSnapshot) is not
// ported - there is no analytics pipeline in the Flutter app yet. TODO: wire a
// daily snapshot here once one exists.
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'cf_api.dart';
import 'exam_service.dart';

/// Signup bonus granted once per account per subcourse (see
/// [ensureMainLeaderboardRow]). Added on top of computed activity points.
const int kLeaderboardSignupBonus = 50;

/// Points awarded per event. Correctness pays more than mere participation.
/// (Port of POINTS in services/scoring.ts.)
abstract final class LeaderboardPoints {
  static const int qotdAttempt = 4;
  static const int qotdCorrect = 10;
  static const int examAttempt = 10;
  static const double examPerScorePoint = 1.0; // x score% -> a 70% exam pays 70
  static const int dailyTestAttempt = 6;
  static const double dailyTestPerScorePoint = 0.5;
  static const int practiceAttempt = 2;
  static const int practiceCorrect = 5;
  static const int gkPmAttempt = 2;
  static const int gkPmCorrect = 5;
  static const int readViewed = 1;
  static const int theoryCompleted = 6;
  static const int constitutionRead = 4;
  static const int completionBonus = 8;
}

// ---------- small decoders (this library's own; exam_service.dart has its own
// private copies that are not visible here) ----------

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.isFinite ? v.round() : fallback;
  return fallback;
}

// ---------- public types ----------

/// Stable public document id, exactly as React builds it:
/// `${uid}__${subcourseId}`, sanitised and capped at 128 chars.
String publicRowId(String uid, String subcourseId) {
  final raw = '${uid}__$subcourseId'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return raw.length > 128 ? raw.substring(0, 128) : raw;
}

// ---------- publish throttle ----------

/// Recomputing a score reads a user's entire history, so publishing is
/// throttled to once every five minutes per user+subcourse. Kept here (not in
/// a screen) because more than one screen publishes - a shared map keeps the
/// effective recompute rate at one, not one per screen visited.
const int _publishIntervalMs = 5 * 60 * 1000;
final Map<String, int> _lastPublishedAt = <String, int>{};

String _throttleKey(String uid, String subcourseId) => '${uid}__$subcourseId';

/// True when enough time has passed to justify another full recompute.
bool shouldPublishMainLeaderboardScore(String uid, String subcourseId) {
  if (uid.isEmpty || subcourseId.isEmpty) return false;
  final previous = _lastPublishedAt[_throttleKey(uid, subcourseId)];
  return previous == null ||
      DateTime.now().millisecondsSinceEpoch - previous > _publishIntervalMs;
}

/// Forces the next publish through - used by pull-to-refresh, where the user
/// has explicitly asked for fresh numbers and waiting out the throttle would
/// look like the refresh did nothing.
void resetMainLeaderboardThrottle(String uid, String subcourseId) {
  _lastPublishedAt.remove(_throttleKey(uid, subcourseId));
}

/// Max achievable activity points per content item of each source — the
/// denominator of the headline progress percent (points ÷ total content
/// marks). Mirrors [LeaderboardPoints]: a fully-correct first pass over one
/// item of the source.
const Map<String, double> _maxPointsPerItem = {
  'practice': 7, // attempt 2 + correct 5
  'theory': 6, // theoryCompleted
  'exam': 110, // attempt 10 + score 100 x 1.0
  'gkPm': 7, // attempt 2 + correct 5
  'read': 1, // readViewed
  'dailyTest': 56, // attempt 6 + score 100 x 0.5
  'constitution': 4, // constitutionRead
};

/// Total marks the subcourse's content can yield:
/// Σ totals[source] × max-points-per-item. Pure — unit-tested.
@visibleForTesting
double contentMarksForTotals(Map<String, int> totals) {
  var marks = 0.0;
  for (final entry in _maxPointsPerItem.entries) {
    marks += (totals[entry.key] ?? 0) * entry.value;
  }
  return marks;
}

/// Headline progress percent: activity [points] as a percent of the total
/// content [marks]. Clamped 0..100. Pure — unit-tested.
@visibleForTesting
double computeProgressPercent(double points, double marks) {
  if (marks <= 0) return 0;
  return (points / marks * 100).clamp(0.0, 100.0).toDouble();
}

// ---------- publish ----------

/// Extracts a leaderboard row map from a worker response body: the row
/// under 'row' when present, else the body itself when it looks like a
/// row. Null when neither carries row fields.
Map<String, dynamic>? _rowFromBody(Map<String, dynamic> body) {
  final row = body['row'];
  if (row is Map) return Map<String, dynamic>.from(row);
  if (body.containsKey('points') || body.containsKey('uid')) return body;
  return null;
}

/// The caller's own leaderboard entry from GET /leaderboard ('own'),
/// shaped as a row map. Null when the worker has none.
Future<Map<String, dynamic>?> _ownLeaderboardMap(
    String courseId, String subcourseId) async {
  try {
    final result = await CfApi.getLeaderboard(
        courseId: courseId, subcourseId: subcourseId);
    return result.own;
  } catch (_) {
    return null;
  }
}

/// Computes and publishes the score.
///
/// Phase-1: the recompute + republish happens SERVER-side via
/// POST /leaderboard/refresh — the worker recomputes from the migrated
/// data (the same sources [computeMainLeaderboardScore] used to read),
/// preserves the signup bonus, and writes both the private aggregate and
/// the public row. The throttle contract is unchanged: a skipped or
/// failed publish returns null and a failure never consumes the throttle.
///
/// Returns the freshly written public row on success, so the caller can show it
/// immediately without re-reading the board. Returns null when the publish is
/// skipped by the throttle or on any failure - never throws.
Future<MainLeaderboardRow?> publishMainLeaderboardScore({
  required String uid,
  required String courseId,
  required String subcourseId,
  required String name,
  required String? photoURL,
  required bool isPro,
}) async {
  if (uid.isEmpty || subcourseId.isEmpty) return null;
  if (!shouldPublishMainLeaderboardScore(uid, subcourseId)) return null;
  try {
    noteLeaderboardScope(courseId, subcourseId);
    final body = await CfApi.refreshLeaderboard({
      'courseId': courseId,
      'subcourseId': subcourseId,
      'name': name.isEmpty ? 'Anonymous' : name,
      'photoURL': photoURL,
      'isPro': isPro,
    });
    _lastPublishedAt[_throttleKey(uid, subcourseId)] =
        DateTime.now().millisecondsSinceEpoch;
    final rowMap =
        _rowFromBody(body) ?? await _ownLeaderboardMap(courseId, subcourseId);
    if (rowMap == null) return null;
    final row = MainLeaderboardRow.fromMap(rowMap);
    return row.uid.isEmpty ? null : row;
  } catch (_) {
    // A failed publish must NOT consume the throttle — otherwise every screen
    // sits on stale/fallback numbers for 5 minutes instead of retrying on the
    // next open. (2026-10-02: this is how the aggregate stayed missing while
    // the profile fell back to the frozen users/{uid}.stats.points mirror.)
    resetMainLeaderboardThrottle(uid, subcourseId);
    return null;
  }
}

// ---------- canonical stats (single source of truth) ----------
//
// THE CONSISTENCY RULE (2026-10-02): the points and progress percent shown on
// the Analytics hero, the Leaderboard board, and the Profile stats card ALL
// derive from [computeMainLeaderboardScore] plus the 50pt signup bonus
// ([kLeaderboardSignupBonus]). The once-a-day snapshot document
// (users/{uid}/app_analytics/{subcourseId}) is kept ONLY for history charts
// and windowed stats (active days, study time, per-day deltas) — it is never
// a source for hero / leaderboard / profile numbers, because it goes stale
// the moment any intraday activity happens (the "Analytics says 594, profile
// says much more" bug).
//
// The 50pt signup bonus is counted EVERYWHERE: it is baked into the
// aggregate's `points` at publish time (see [publishMainLeaderboardScore]),
// so every surface reading the aggregate — or a freshly published row —
// includes it. No surface ever shows activity-points-only.

/// Canonical live stats for one user+subcourse: the numbers the Analytics
/// hero, the Leaderboard board and the Profile stats card all display.
class CanonicalStats {
  /// Progress percent (points ÷ total content marks), 0..100.
  final double percent;

  /// Effort points INCLUDING the 50pt signup bonus.
  final int points;
  final int activityCount;

  /// The leaderboard breakdown snapshot (qotd/exam/dailyTest/practice/gkPm/
  /// reading/usage/coverage sub-maps), for the analytics "where the points
  /// came from" section.
  final Map<String, dynamic> breakdown;

  const CanonicalStats({
    required this.percent,
    required this.points,
    required this.activityCount,
    required this.breakdown,
  });
}

CanonicalStats? _canonicalFromMap(Map<String, dynamic>? m) {
  if (m == null) return null;
  num n(dynamic v) {
    if (v is num && v.isFinite) return v;
    // Phase-1: the API's own-row values may arrive as text.
    if (v is String) return num.tryParse(v.trim()) ?? 0;
    return 0;
  }

  final b = m['breakdown'];
  return CanonicalStats(
    percent: n(m['percent']).toDouble().clamp(0.0, 100.0),
    points: max(0, n(m['points']).round()),
    activityCount: max(0, n(m['activityCount']).round()),
    breakdown: b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{},
  );
}

/// Loads the canonical stats: the stored aggregate
/// (users/{uid}/app_mainleaderboard/{subcourseId}), refreshed first when the
/// publish throttle allows. Returns null when no aggregate exists and no
/// refresh was possible — callers fall back to degraded mode (never zeros).
/// Never throws.
///
/// [name]/[photoURL]/[isPro] feed the public row only when a refresh publish
/// actually runs. Pass [allowRefresh] false when the profile is not loaded, so
/// a refresh can never write the public row as "Anonymous".
Future<CanonicalStats?> loadCanonicalStats({
  required String uid,
  required String courseId,
  required String subcourseId,
  String name = '',
  String? photoURL,
  bool isPro = false,
  bool allowRefresh = true,
}) async {
  if (uid.isEmpty || subcourseId.isEmpty) return null;
  try {
    noteLeaderboardScope(courseId, subcourseId);
    if (allowRefresh && shouldPublishMainLeaderboardScore(uid, subcourseId)) {
      final row = await publishMainLeaderboardScore(
        uid: uid,
        courseId: courseId,
        subcourseId: subcourseId,
        name: name,
        photoURL: photoURL,
        isPro: isPro,
      );
      if (row != null) {
        // The public row omits the breakdown — read the caller's own
        // aggregate (GET /leaderboard 'own') so the breakdown stays whole.
        final own = await _ownLeaderboardMap(courseId, subcourseId);
        return _canonicalFromMap(own) ??
            CanonicalStats(
              percent: row.percent,
              points: row.points,
              activityCount: row.activityCount,
              breakdown: const <String, dynamic>{},
            );
      }
    }
    final own = await _ownLeaderboardMap(courseId, subcourseId);
    return _canonicalFromMap(own);
  } catch (_) {
    return null;
  }
}

/// Guarantees the user has a public leaderboard row for this subcourse,
/// granting the 50-point signup bonus exactly once. Returns the existing row
/// when one is already there; otherwise creates BOTH documents fresh with
/// `points: 50, signupBonus: 50` and returns the new row.
///
/// Call this at course-setup completion or on first leaderboard visit, once the
/// subcourseId is known. Never throws - null on any failure.
Future<MainLeaderboardRow?> ensureMainLeaderboardRow({
  required String uid,
  required String courseId,
  required String subcourseId,
  required String name,
  required String? photoURL,
  required bool isPro,
}) async {
  if (uid.isEmpty || subcourseId.isEmpty) return null;
  try {
    noteLeaderboardScope(courseId, subcourseId);
    final displayName = name.isEmpty ? 'Anonymous' : name;
    // Phase-1: POST /leaderboard/ensure-row — the worker returns the
    // existing row untouched, or creates both documents with the bonus
    // exactly as the client used to.
    final body = await CfApi.ensureLeaderboardRow({
      'courseId': courseId,
      'subcourseId': subcourseId,
      'name': displayName,
      'photoURL': photoURL,
      'isPro': isPro,
    });
    final rowMap =
        _rowFromBody(body) ?? await _ownLeaderboardMap(courseId, subcourseId);
    if (rowMap != null) {
      final row = MainLeaderboardRow.fromMap(rowMap);
      if (row.uid.isNotEmpty) return row;
    }
    // The POST landed but carried no row back — mirror the row the old
    // code returned right after creating it.
    return MainLeaderboardRow(
      id: publicRowId(uid, subcourseId),
      uid: uid,
      name: displayName,
      photoURL: photoURL,
      isPro: isPro,
      percent: 0,
      points: kLeaderboardSignupBonus,
      usageSeconds: 0,
      activityCount: 0,
      signupBonus: kLeaderboardSignupBonus,
    );
  } catch (_) {
    return null;
  }
}

// ---------- user stats rank mirror ----------

/// In-memory baseline of users/{uid}.stats, read once per session per user -
/// mirrors the statsBaseline map in profile.ts. The baseline is only promoted
/// after a write lands, so a failed write can never look like a successful one.
final Map<String, Map<String, int>> _userStatsBaseline =
    <String, Map<String, int>>{};

int _pickStat(dynamic value, int fallback) {
  final v = _toInt(value, -1);
  return v >= 0 ? v : fallback;
}

/// Port of writeUserStats for the rank field: merges into users/{uid}.stats
/// and skips the write entirely when the rank has not changed. These calls
/// happen on every leaderboard publish and every board open, and most of the
/// time the number is identical to what is already stored.
///
/// Never throws.
Future<void> writeUserStatsRank(String uid, int rank) async {
  if (uid.isEmpty) return;
  try {
    var baseline = _userStatsBaseline[uid];
    if (baseline == null) {
      // Only reached when a writer runs before any profile load. One read,
      // once, per session. Phase-1: the baseline comes from GET /me.
      final doc = await CfApi.getMe().catchError((_) => null);
      final stats = doc?['stats'];
      final map =
          stats is Map ? Map<String, dynamic>.from(stats) : <String, dynamic>{};
      baseline = {
        'testsTaken': _pickStat(map['testsTaken'], 0),
        'streak': _pickStat(map['streak'], 0),
        'rank': _pickStat(map['rank'], 0),
        'points': _pickStat(map['points'], 0),
      };
    }

    final next = <String, int>{
      'testsTaken': baseline['testsTaken'] ?? 0,
      'streak': baseline['streak'] ?? 0,
      'rank': rank >= 0 ? rank : (baseline['rank'] ?? 0),
      'points': baseline['points'] ?? 0,
    };

    // Remember the baseline even when about to skip, so the one-off read
    // above happens at most once per session.
    _userStatsBaseline[uid] = baseline;
    if (next['rank'] == baseline['rank']) return;

    // Phase-1: the stats mirror merges into the profile via PATCH /me.
    await CfApi.patchMe({'stats': next});
    // Promoted only after the write lands.
    _userStatsBaseline[uid] = next;
  } catch (_) {
    // Silent by design - a failed mirror must stay invisible.
  }
}
