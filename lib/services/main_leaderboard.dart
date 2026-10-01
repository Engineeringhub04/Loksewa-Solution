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
//   percent - COVERAGE of the subcourse: how much of the content that exists
//             has been worked through. Starts near zero, climbs only with real
//             study. The denominator is the app_content_totals/{subcourseId}
//             document, read live with React's per-field fallback semantics;
//             only a missing document degrades coverage to 0.
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

/// Weight of each source inside the ACCURACY average. Only sources the user has
/// actually touched are counted. (Port of PERCENT_WEIGHTS.)
const Map<String, double> _percentWeights = {
  'exam': 3,
  'dailyTest': 2.5,
  'practice': 2.5,
  'qotd': 2,
  'gkPm': 1.5,
  'reading': 1,
};

/// Relative importance of each content type inside the coverage average.
/// (Port of COVERAGE_WEIGHTS.)
const Map<String, double> _coverageWeights = {
  'practice': 3,
  'theory': 2.5,
  'exam': 2,
  'gkPm': 1.5,
  'read': 1.5,
  'dailyTest': 1,
  'constitution': 1,
};

/// Study time -> points, capped so presence can never outrank performance.
/// (Port of TIME_POINTS_PER_HOUR / TIME_POINTS_CAP.)
const double _timePointsPerHour = 12;
const double _timePointsCap = 240; // ~20 hours; beyond this, time stops paying

/// Reading "accuracy" is coverage normalised against a nominal target.
/// (Port of READING_TARGET_UNITS / READING_UNIT_WEIGHTS.)
const double _readingTargetUnits = 200;
const double _readingUnitQuestion = 1;
const double _readingUnitTheory = 5;
const double _readingUnitConstitution = 5;

// ---------- small decoders (this library's own; exam_service.dart has its own
// private copies that are not visible here) ----------

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.isFinite ? v.round() : fallback;
  return fallback;
}

double _toDouble(dynamic v, [double fallback = 0.0]) {
  if (v is num) return v.isFinite ? v.toDouble() : fallback;
  return fallback;
}

String _toStr(dynamic v, [String fallback = '']) =>
    (v is String && v.isNotEmpty) ? v : fallback;

bool _toBool(dynamic v) => v == true;

List<String> _toStrList(dynamic v) =>
    v is List ? v.whereType<String>().toList() : const <String>[];

// ---------- pure scoring helpers (port of services/scoring.ts) ----------

double _round2(double value) => (value * 100).round() / 100;

double _percentOf(double part, double whole) =>
    whole > 0 ? (part / whole) * 100 : 0;

double _weightedPercent(List<_WeightedPart> parts) {
  double num = 0;
  double den = 0;
  for (final p in parts) {
    num += p.value * p.weight;
    den += p.weight;
  }
  return den > 0 ? num / den : 0;
}

class _WeightedPart {
  final double value;
  final double weight;
  const _WeightedPart(this.value, this.weight);
}

double _readingUnits(
        int questionsRead, int theoryCompleted, int constitutionParts) =>
    max(0, questionsRead) * _readingUnitQuestion +
    max(0, theoryCompleted) * _readingUnitTheory +
    max(0, constitutionParts) * _readingUnitConstitution;

double _timePoints(double foregroundSeconds) => min(
    _timePointsCap, (max(0, foregroundSeconds) / 3600) * _timePointsPerHour);

/// Stand-in library size, used per-field when the totals document exists but a
/// counter has not been seeded yet. Port of FALLBACK_CONTENT_TOTALS in
/// services/scoring.ts. A present zero is meaningful (the admin published none
/// of that content type yet) and is never replaced by these.
const Map<String, int> _fallbackContentTotals = {
  'practice': 4000,
  'theory': 150,
  'exam': 60,
  'gkPm': 1200,
  'read': 4000,
  'dailyTest': 120,
  'constitution': 35,
};

/// Firestore field names inside app_content_totals/{subcourseId}.
/// Port of TOTAL_FIELDS in services/contentTotals.ts.
const Map<String, String> _totalFields = {
  'practice': 'practiceQuestions',
  'theory': 'theoryItems',
  'exam': 'examSets',
  'gkPm': 'gkPmQuestions',
  'read': 'readQuestions',
  'dailyTest': 'dailyTestModels',
};

/// Resolves the coverage denominator from the totals document, exactly like
/// React's fetchContentTotals: start from the fallback library size and
/// override per field from the document. Returns null when the document is
/// missing, in which case coverage degrades to 0.
///
/// The CDN constitution count (React's fetchConstitutionTotal) is not ported;
/// constitutionSections from the document is used instead.
Map<String, int>? _resolveTotals(Map<String, dynamic>? doc) {
  if (doc == null) return null;
  final totals = <String, int>{};
  _totalFields.forEach((source, field) {
    final raw = doc[field];
    totals[source] =
        raw != null ? max(0, _toInt(raw)) : _fallbackContentTotals[source]!;
  });
  final cRaw = doc['constitutionSections'];
  totals['constitution'] = cRaw != null
      ? max(0, _toInt(cRaw))
      : _fallbackContentTotals['constitution']!;
  return totals;
}

/// Records written before course scoping existed carry no subcourseId. They are
/// counted toward the subcourse being scored, which is correct for every user
/// except one who has since switched course - a rare case whose only cost is a
/// slightly generous legacy score.
bool _belongsToSubcourse(String recordSubcourseId, String subcourseId) =>
    recordSubcourseId.isEmpty || recordSubcourseId == subcourseId;

// ---------- public types ----------

/// A freshly computed leaderboard score. [points] is the computed ACTIVITY
/// total and EXCLUDES any signup bonus - the bonus is added at publish time.
class LeaderboardScore {
  double percent;
  double accuracyPercent;
  int points;
  int usageSeconds;
  int activityCount;
  Map<String, dynamic> breakdown;

  LeaderboardScore({
    this.percent = 0,
    this.accuracyPercent = 0,
    this.points = 0,
    this.usageSeconds = 0,
    this.activityCount = 0,
    Map<String, dynamic>? breakdown,
  }) : breakdown = breakdown ?? <String, dynamic>{};
}

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

// ---------- guarded reads ----------

Future<List<Map<String, dynamic>>> _guardList(
    Future<List<Map<String, dynamic>>> f) async {
  try {
    return await f;
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

Future<Map<String, dynamic>?> _guardDoc(Future<Map<String, dynamic>?> f) async {
  try {
    return await f;
  } catch (_) {
    return null;
  }
}

// ---------- compute ----------

/// Builds the score for one subcourse. Reads a lot, so it is NOT something to
/// call on every screen - publishing is throttled (see
/// [publishMainLeaderboardScore]).
///
/// Every source is independently catch-guarded: one unavailable source
/// degrades the score, never fails the whole computation. A missing source
/// contributes 0.
Future<LeaderboardScore> computeMainLeaderboardScore(
    String uid, String courseId, String subcourseId) async {
  final results = await Future.wait([
    _guardList(ExamRest.listDocs('users/$uid/questionofdata')),
    _guardList(ExamRest.listDocs('users/$uid/exam_attempts')),
    _guardList(ExamRest.listDocs('users/$uid/daily_test_results')),
    _guardList(ExamRest.listDocs('users/$uid/learning_progress')),
    _guardList(ExamRest.listDocs('users/$uid/app_activity_progress')),
    _guardDoc(ExamRest.getDoc('users/$uid/app_usage/summary')),
    // The coverage denominator. This document exists in Firestore
    // (app_content_totals/{subcourseId}); it is read live and catch-guarded.
    // Only when it is actually missing does coverage fall back to 0.
    _guardDoc(ExamRest.getDoc('app_content_totals/$subcourseId')),
  ]);

  final qotdDocs = results[0] as List<Map<String, dynamic>>;
  final examDocs = results[1] as List<Map<String, dynamic>>;
  final dailyDocs = results[2] as List<Map<String, dynamic>>;
  final practiceDocs = results[3] as List<Map<String, dynamic>>;
  final activityDocs = results[4] as List<Map<String, dynamic>>;
  final usageDoc = results[5] as Map<String, dynamic>?;
  final totalsDoc = results[6] as Map<String, dynamic>?;

  final percentParts = <_WeightedPart>[];
  final covered = <String, int>{
    'practice': 0,
    'theory': 0,
    'exam': 0,
    'gkPm': 0,
    'read': 0,
    'dailyTest': 0,
    'constitution': 0,
  };
  double points = 0;

  // ===== Question of the Day =====
  // The same collection also holds the rolling 'summary' document, which is not
  // an attempt and must not be counted as one.
  var qotdAttempts = 0;
  var qotdCorrect = 0;
  for (final doc in qotdDocs) {
    if (_toStr(doc['id']) == 'summary') continue;
    if (!_belongsToSubcourse(_toStr(doc['subcourseId']), subcourseId)) continue;
    qotdAttempts += 1;
    if (_toBool(doc['isCorrect'])) qotdCorrect += 1;
  }
  final qotdPercent =
      _percentOf(qotdCorrect.toDouble(), qotdAttempts.toDouble());
  if (qotdAttempts > 0) {
    percentParts.add(_WeightedPart(qotdPercent, _percentWeights['qotd'] ?? 0));
    points += qotdAttempts * LeaderboardPoints.qotdAttempt +
        qotdCorrect * LeaderboardPoints.qotdCorrect;
  }

  // ===== Exams =====
  // Scored on the BEST attempt per set, matching how the per-exam ranking
  // works, so retrying to improve is not averaged away. Points still accrue
  // per attempt.
  final bestByExamSet = <String, double>{};
  var examAttempts = 0;
  for (final doc in examDocs) {
    if (!_belongsToSubcourse(_toStr(doc['subcourseId']), subcourseId)) continue;
    final setId = _toStr(doc['examSetId']);
    if (setId.isEmpty) continue;
    final score = _toDouble(doc['score']).clamp(0.0, 100.0).toDouble();
    examAttempts += 1;
    points += LeaderboardPoints.examAttempt +
        score * LeaderboardPoints.examPerScorePoint;
    final previousBest = bestByExamSet[setId];
    if (previousBest == null || score > previousBest) {
      bestByExamSet[setId] = score;
    }
  }
  final examBests = bestByExamSet.values.toList();
  final examAveragePercent = examBests.isNotEmpty
      ? examBests.reduce((a, b) => a + b) / examBests.length
      : 0.0;
  final examBestPercent = examBests.isNotEmpty ? examBests.reduce(max) : 0.0;
  if (examAttempts > 0) {
    percentParts
        .add(_WeightedPart(examAveragePercent, _percentWeights['exam'] ?? 0));
  }
  // An exam set is "covered" once it has been sat at all. Sitting the same
  // set five times is one covered set, not five.
  covered['exam'] = bestByExamSet.length;

  // ===== Daily tests =====
  // Coverage counts DISTINCT models. The attempt documents are one-per-attempt,
  // so the model id is collected explicitly.
  final dailyModelIds = <String>{};
  var dailyAttempts = 0;
  var dailyScoreSum = 0.0;
  for (final doc in dailyDocs) {
    if (!_belongsToSubcourse(_toStr(doc['subcourseId']), subcourseId)) continue;
    final score = _toDouble(doc['score']).clamp(0.0, 100.0).toDouble();
    dailyAttempts += 1;
    dailyScoreSum += score;
    points += LeaderboardPoints.dailyTestAttempt +
        score * LeaderboardPoints.dailyTestPerScorePoint;
    final modelId = _toStr(doc['modelId']);
    if (modelId.isNotEmpty) dailyModelIds.add(modelId);
  }
  final dailyAveragePercent =
      dailyAttempts > 0 ? dailyScoreSum / dailyAttempts : 0.0;
  if (dailyAttempts > 0) {
    percentParts.add(
        _WeightedPart(dailyAveragePercent, _percentWeights['dailyTest'] ?? 0));
  }
  // Results written before modelId was recorded cannot be de-duplicated, so
  // they fall back to the attempt count.
  covered['dailyTest'] =
      dailyModelIds.isNotEmpty ? dailyModelIds.length : dailyAttempts;

  // ===== Practice mode (learning_progress) =====
  var practiceAttempted = 0;
  var practiceCorrect = 0;
  var chaptersCompleted = 0;
  for (final doc in practiceDocs) {
    if (!_belongsToSubcourse(_toStr(doc['subcourseId']), subcourseId)) continue;
    final attempted = _toStrList(doc['attemptedQuestionIds']).length;
    final correct = _toStrList(doc['correctQuestionIds']).length;
    practiceAttempted += attempted;
    practiceCorrect += correct;
    if (_toBool(doc['completed'])) {
      chaptersCompleted += 1;
      points += LeaderboardPoints.completionBonus;
    }
  }
  final practicePercent =
      _percentOf(practiceCorrect.toDouble(), practiceAttempted.toDouble());
  if (practiceAttempted > 0) {
    percentParts
        .add(_WeightedPart(practicePercent, _percentWeights['practice'] ?? 0));
    points += practiceAttempted * LeaderboardPoints.practiceAttempt +
        practiceCorrect * LeaderboardPoints.practiceCorrect;
  }
  // attemptedQuestionIds is already a distinct set per chapter document, and a
  // question belongs to exactly one chapter, so summing their lengths is a
  // distinct question count.
  covered['practice'] = practiceAttempted;

  // ===== Everything in app_activity_progress =====
  // GK/PM are scored (they have questions); read/theory/constitution are
  // coverage only, feeding the 'reading' weight rather than an accuracy one.
  var gkPmAttempted = 0;
  var gkPmCorrect = 0;
  var gkPmCovered = 0;
  var questionsRead = 0;
  var theoryCompleted = 0;
  var constitutionParts = 0;
  var readingSeconds = 0;

  const scoredSources = {'gk', 'pm', 'pastqns'};
  for (final record in activityDocs) {
    if (!_belongsToSubcourse(_toStr(record['subcourseId']), subcourseId)) {
      continue;
    }
    readingSeconds += max(0, _toInt(record['secondsSpent']));
    final source = _toStr(record['source']);

    if (scoredSources.contains(source)) {
      final attempted = _toStrList(record['attemptedQuestionIds']);
      final correct = _toStrList(record['correctQuestionIds']);
      final viewed = _toStrList(record['viewedItemIds']);
      gkPmAttempted += attempted.length;
      gkPmCorrect += correct.length;
      // Coverage is broader than scoring here: revealing a GK answer without
      // committing to an option is still consuming that question. The union
      // de-duplicates the overlap between the two lists.
      gkPmCovered += {...attempted, ...viewed}.length;
      continue;
    }

    if (source == 'read') {
      final viewedCount = _toStrList(record['viewedItemIds']).length;
      questionsRead += viewedCount;
      points += viewedCount * LeaderboardPoints.readViewed;
      if (_toBool(record['completed'])) {
        points += LeaderboardPoints.completionBonus;
      }
      continue;
    }
    if (source == 'theory' && _toBool(record['completed'])) {
      theoryCompleted += 1;
      points += LeaderboardPoints.theoryCompleted;
      continue;
    }
    if (source == 'constitution') {
      constitutionParts += 1;
      points += LeaderboardPoints.constitutionRead;
    }
  }

  covered['gkPm'] = gkPmCovered;
  covered['read'] = questionsRead;
  covered['theory'] = theoryCompleted;
  covered['constitution'] = constitutionParts;

  final gkPmPercent =
      _percentOf(gkPmCorrect.toDouble(), gkPmAttempted.toDouble());
  if (gkPmAttempted > 0) {
    percentParts.add(_WeightedPart(gkPmPercent, _percentWeights['gkPm'] ?? 0));
    points += gkPmAttempted * LeaderboardPoints.gkPmAttempt +
        gkPmCorrect * LeaderboardPoints.gkPmCorrect;
  }

  // Reading has no right or wrong answer, so its "accuracy" is how much
  // material was covered, normalised against a nominal target.
  final readingCoverage =
      _readingUnits(questionsRead, theoryCompleted, constitutionParts);
  if (readingCoverage > 0) {
    percentParts.add(_WeightedPart(
        _percentOf(readingCoverage, _readingTargetUnits),
        _percentWeights['reading'] ?? 0));
  }

  // ===== Time in app -> capped points =====
  // The Flutter app does not bank foreground seconds yet (no flushAppUsage
  // equivalent); the summary document only carries what writers record, so a
  // missing field simply contributes 0 here.
  final foregroundSeconds = max(0, _toInt(usageDoc?['foregroundSeconds']));
  final activityCount = max(0, _toInt(usageDoc?['activityCount']));
  final sessionCount = max(0, _toInt(usageDoc?['sessionCount']));
  points += _timePoints(foregroundSeconds.toDouble());

  // Accuracy is no longer the headline, but it is still worth knowing and the
  // stats card reads it.
  final accuracyPercent = _weightedPercent(percentParts);

  // The headline: coverage of everything this subcourse contains. The totals
  // document is resolved with React's per-field fallback semantics; a missing
  // document yields a 0% coverage rather than a crash.
  final coverage = _computeCoverage(covered, _resolveTotals(totalsDoc));

  return LeaderboardScore(
    percent: _round2(coverage.percent.clamp(0.0, 100.0).toDouble()),
    accuracyPercent: _round2(accuracyPercent.clamp(0.0, 100.0).toDouble()),
    points: max(0, points.round()),
    usageSeconds: foregroundSeconds,
    activityCount: activityCount,
    breakdown: {
      'qotd': {
        'attempts': qotdAttempts,
        'correct': qotdCorrect,
        'percent': _round2(qotdPercent),
      },
      'exam': {
        'attempts': examAttempts,
        'bestPercent': _round2(examBestPercent),
        'averagePercent': _round2(examAveragePercent),
      },
      'dailyTest': {
        'attempts': dailyAttempts,
        'averagePercent': _round2(dailyAveragePercent),
      },
      'practice': {
        'attempted': practiceAttempted,
        'correct': practiceCorrect,
        'percent': _round2(practicePercent),
        'chaptersCompleted': chaptersCompleted,
      },
      'gkPm': {
        'attempted': gkPmAttempted,
        'correct': gkPmCorrect,
        'percent': _round2(gkPmPercent),
      },
      'reading': {
        'questionsRead': questionsRead,
        'theoryCompleted': theoryCompleted,
        'constitutionParts': constitutionParts,
        'secondsSpent': readingSeconds,
      },
      'usage': {
        'foregroundSeconds': foregroundSeconds,
        'sessionCount': sessionCount,
        'activityCount': activityCount,
      },
      'coverage': {
        'percent': _round2(coverage.percent),
        'coveredItems': coverage.coveredItems,
        'totalItems': coverage.totalItems,
        'details': coverage.details,
      },
    },
  );
}

class _CoverageResult {
  final double percent;
  final int coveredItems;
  final int totalItems;
  final List<Map<String, dynamic>> details;
  const _CoverageResult({
    required this.percent,
    required this.coveredItems,
    required this.totalItems,
    required this.details,
  });
}

/// Coverage of the subcourse's content. Every category with content counts
/// toward the average, including ones the user has never opened - that is what
/// makes 100% genuinely hard. A category the catalog has no content for yet is
/// skipped entirely: you cannot have covered a fraction of nothing.
///
/// A null [totals] (the totals document is missing from Firestore) skips every
/// category, so coverage degrades gracefully to 0%.
_CoverageResult _computeCoverage(
    Map<String, int> covered, Map<String, int>? totals) {
  final details = <Map<String, dynamic>>[];
  var coveredItems = 0;
  var totalItems = 0;

  for (final entry in _coverageWeights.entries) {
    final source = entry.key;
    final total = max(0, totals?[source] ?? 0);
    if (total <= 0) continue; // no content of this kind yet - not counted
    final done = max(0, min(total, max(0, covered[source] ?? 0)));
    coveredItems += done;
    totalItems += total;
    details.add({
      'source': source,
      'covered': done,
      'total': total,
      'percent': _round2(_percentOf(done.toDouble(), total.toDouble())),
      'weight': entry.value,
    });
  }

  final percent = _weightedPercent([
    for (final d in details)
      _WeightedPart(_toDouble(d['percent']), _toDouble(d['weight'])),
  ]);
  return _CoverageResult(
    percent: percent,
    coveredItems: coveredItems,
    totalItems: totalItems,
    details: details,
  );
}

// ---------- publish ----------

/// Computes and publishes the score. The private document carries the whole
/// breakdown; the public row carries only what the list renders plus the
/// tiebreak fields.
///
/// The signup bonus is PRESERVED: the existing public row is read first and its
/// `signupBonus` is added to the computed activity points, so a republish can
/// never wipe the bonus out. Points are never written without adding it.
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
    final rowId = publicRowId(uid, subcourseId);

    // Read the existing public row for its signup bonus (default 0). One read;
    // a missing row just means no bonus has been granted yet.
    final existing =
        await _guardDoc(ExamRest.getDoc('app_main_leaderboard/$rowId'));
    final signupBonus = _toInt(existing?['signupBonus']);

    final score = await computeMainLeaderboardScore(uid, courseId, subcourseId);
    _lastPublishedAt[_throttleKey(uid, subcourseId)] =
        DateTime.now().millisecondsSinceEpoch;

    final total = score.points + signupBonus;
    final displayName = name.isEmpty ? 'Anonymous' : name;

    await ExamRest.setDoc(
      'users/$uid/app_mainleaderboard/$subcourseId',
      {
        'courseId': courseId,
        'subcourseId': subcourseId,
        'percent': score.percent,
        'accuracyPercent': score.accuracyPercent,
        'points': total,
        'usageSeconds': score.usageSeconds,
        'activityCount': score.activityCount,
        'breakdown': score.breakdown,
      },
      serverTimestampFields: const ['updatedAt'],
    );

    // Best-effort: losing the public row costs a leaderboard position, not
    // data. (The row is still returned below from the values just written.)
    try {
      await ExamRest.setDoc(
        'app_main_leaderboard/$rowId',
        {
          'uid': uid,
          'courseId': courseId,
          'subcourseId': subcourseId,
          // Stored so other users' devices can draw the verified tick without
          // reading this person's profile - which the rules would not allow.
          'name': displayName,
          'photoURL': photoURL,
          'isPro': isPro,
          'percent': score.percent,
          'points': total,
          'usageSeconds': score.usageSeconds,
          'activityCount': score.activityCount,
          'signupBonus': signupBonus,
        },
        serverTimestampFields: const ['updatedAt'],
      );
    } catch (_) {
      // Best-effort only - the private aggregate above is already safe.
    }

    // TODO: record a daily analytics snapshot here once the Flutter app has an
    // analytics pipeline (React's recordAnalyticsSnapshot). It must stay
    // best-effort and last, like in React, so it can never fail a publish.

    return MainLeaderboardRow(
      id: rowId,
      uid: uid,
      name: displayName,
      photoURL: photoURL,
      isPro: isPro,
      percent: score.percent,
      points: total,
      usageSeconds: score.usageSeconds,
      activityCount: score.activityCount,
      signupBonus: signupBonus,
    );
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
// THE CONSISTENCY RULE (2026-10-02): the points and coverage percent shown on
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
  /// Coverage percent, 0..100.
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
  num n(dynamic v) => v is num && v.isFinite ? v : 0;
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
        // The public row omits the breakdown — re-read the private aggregate
        // (one extra read, only on a refresh) so the breakdown stays whole.
        final agg = await _guardDoc(
            ExamRest.getDoc('users/$uid/app_mainleaderboard/$subcourseId'));
        return _canonicalFromMap(agg) ??
            CanonicalStats(
              percent: row.percent,
              points: row.points,
              activityCount: row.activityCount,
              breakdown: const <String, dynamic>{},
            );
      }
    }
    final agg = await _guardDoc(
        ExamRest.getDoc('users/$uid/app_mainleaderboard/$subcourseId'));
    return _canonicalFromMap(agg);
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
    final rowId = publicRowId(uid, subcourseId);
    final existing =
        await _guardDoc(ExamRest.getDoc('app_main_leaderboard/$rowId'));
    if (existing != null) {
      return MainLeaderboardRow.fromMap(existing);
    }

    const bonus = kLeaderboardSignupBonus;
    final displayName = name.isEmpty ? 'Anonymous' : name;

    await ExamRest.setDoc(
      'app_main_leaderboard/$rowId',
      {
        'uid': uid,
        'courseId': courseId,
        'subcourseId': subcourseId,
        'name': displayName,
        'photoURL': photoURL,
        'isPro': isPro,
        'percent': 0,
        'points': bonus,
        'usageSeconds': 0,
        'activityCount': 0,
        'signupBonus': bonus,
      },
      serverTimestampFields: const ['updatedAt'],
    );
    await ExamRest.setDoc(
      'users/$uid/app_mainleaderboard/$subcourseId',
      {
        'courseId': courseId,
        'subcourseId': subcourseId,
        'percent': 0,
        'accuracyPercent': 0,
        'points': bonus,
        'usageSeconds': 0,
        'activityCount': 0,
        'signupBonus': bonus,
        'breakdown': <String, dynamic>{},
      },
      serverTimestampFields: const ['updatedAt'],
    );

    return MainLeaderboardRow(
      id: rowId,
      uid: uid,
      name: displayName,
      photoURL: photoURL,
      isPro: isPro,
      percent: 0,
      points: bonus,
      usageSeconds: 0,
      activityCount: 0,
      signupBonus: bonus,
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
      // once, per session.
      final doc = await _guardDoc(ExamRest.getDoc('users/$uid'));
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

    await ExamRest.setDoc(
      'users/$uid',
      {'stats': next},
      serverTimestampFields: const ['updatedAt'],
    );
    // Promoted only after the write lands.
    _userStatsBaseline[uid] = next;
  } catch (_) {
    // Silent by design - a failed mirror must stay invisible.
  }
}
