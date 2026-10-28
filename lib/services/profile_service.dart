import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/subscription_service.dart';

/// User profile service + shared profile store.
///
/// Mirrors `src/core/firebase/services/profile.ts` (UserProfile schema,
/// formatDob, hasActivePremium, stats-mirror helpers) and
/// `src/core/store/profileStore.ts` (load / refresh / score / scoreLoading /
/// error, warmed once and shared by every screen).
///
/// Phase-3: everything shown on the Profile tab is backed by the
/// loksewa-api (GET /me + GET /profile/course-info), not the Firestore
/// document, so the values survive reinstalls and match across devices.

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Mirrored headline numbers on users/{uid}.stats. They are NOT computed here;
/// jobs that already have them in hand mirror them (PATCH /me 'stats'), so
/// the Profile stats card reads them for free.
class UserStats {
  final int testsTaken;
  final int streak;
  final int rank;
  final int points;

  const UserStats({
    this.testsTaken = 0,
    this.streak = 0,
    this.rank = 0,
    this.points = 0,
  });

  static int _num(Object? v) =>
      v is num && v.isFinite && v >= 0 ? v.round() : 0;

  factory UserStats.fromMap(Map<String, dynamic>? raw) {
    final m = raw ?? const <String, dynamic>{};
    return UserStats(
      testsTaken: _num(m['testsTaken']),
      streak: _num(m['streak']),
      rank: _num(m['rank']),
      points: _num(m['points']),
    );
  }

  Map<String, dynamic> toMap() => {
        'testsTaken': testsTaken,
        'streak': streak,
        'rank': rank,
        'points': points,
      };
}

/// Full users/{uid} document shape (normalised — callers never deal with
/// missing fields).
class UserProfile {
  final String uid;
  final String name;
  final String firstName;
  final String lastName;
  final String? email;
  final String? dob; // ISO calendar date, 'YYYY-MM-DD'
  final String? gender; // 'male' | 'female' | 'other'
  final String? photoURL;
  final String photoURLSource; // 'manual' | 'google' | 'none'
  final String? courseId;
  final String? subcourseId;
  final UserStats stats;
  final bool isAdmin;
  final bool isPremium;
  final String? premiumPlanName;
  final String? premiumBillingCycle; // 'monthly' | 'yearly' | 'free'
  final String? premiumExpiryDate;

  const UserProfile({
    required this.uid,
    this.name = '',
    this.firstName = '',
    this.lastName = '',
    this.email,
    this.dob,
    this.gender,
    this.photoURL,
    this.photoURLSource = 'none',
    this.courseId,
    this.subcourseId,
    this.stats = const UserStats(),
    this.isAdmin = false,
    this.isPremium = false,
    this.premiumPlanName,
    this.premiumBillingCycle,
    this.premiumExpiryDate,
  });

  UserProfile copyWith({
    String? name,
    String? firstName,
    String? lastName,
    String? email,
    String? dob,
    String? gender,
    String? photoURL,
    String? photoURLSource,
    String? courseId,
    String? subcourseId,
    UserStats? stats,
    bool? isAdmin,
    bool? isPremium,
    String? premiumPlanName,
    String? premiumBillingCycle,
    String? premiumExpiryDate,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      photoURL: photoURL ?? this.photoURL,
      photoURLSource: photoURLSource ?? this.photoURLSource,
      courseId: courseId ?? this.courseId,
      subcourseId: subcourseId ?? this.subcourseId,
      stats: stats ?? this.stats,
      isAdmin: isAdmin ?? this.isAdmin,
      isPremium: isPremium ?? this.isPremium,
      premiumPlanName: premiumPlanName ?? this.premiumPlanName,
      premiumBillingCycle: premiumBillingCycle ?? this.premiumBillingCycle,
      premiumExpiryDate: premiumExpiryDate ?? this.premiumExpiryDate,
    );
  }
}

/// The user's selected course + subcourse names (for display on Profile).
class UserCourseInfo {
  final String? courseId;
  final String? subcourseId;
  final String? courseName;
  final String? subcourseName;

  const UserCourseInfo({
    this.courseId,
    this.subcourseId,
    this.courseName,
    this.subcourseName,
  });
}

/// The stored whole-app aggregate behind the stats card
/// (users/{uid}/app_mainleaderboard/{subcourseId}) — one stored document,
/// never a recompute.
class MainLeaderboardScore {
  final double percent;
  final int points;
  final int activityCount;
  final Map<String, dynamic> breakdown;

  const MainLeaderboardScore({
    this.percent = 0,
    this.points = 0,
    this.activityCount = 0,
    Map<String, dynamic>? breakdown,
  }) : breakdown = breakdown ?? const {};

  static double _dbl(Object? v) =>
      v is num && v.isFinite ? v.toDouble() : 0.0;
  static int _int(Object? v) => v is num && v.isFinite && v >= 0 ? v.round() : 0;

  factory MainLeaderboardScore.fromMap(Map<String, dynamic>? raw) {
    final m = raw ?? const <String, dynamic>{};
    final b = m['breakdown'];
    return MainLeaderboardScore(
      percent: _dbl(m['percent']),
      points: _int(m['points']),
      activityCount: _int(m['activityCount']),
      breakdown: b is Map<String, dynamic> ? b : const {},
    );
  }
}

// ---------------------------------------------------------------------------
// Pure helpers (mirrors profile.ts)
// ---------------------------------------------------------------------------

/// Returns true only while the user's mirrored premium entitlement is active.
/// Stricter than the raw isPremium flag: also checks the expiry date, so a
/// lapsed member loses the pro ring the moment it runs out.
bool hasActivePremium(UserProfile? profile) {
  if (profile == null || !profile.isPremium) return false;
  final expiry = profile.premiumExpiryDate;
  if (expiry == null) return true;
  final dt = DateTime.tryParse(expiry);
  if (dt == null) return false;
  return dt.isAfter(DateTime.now());
}

const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const _neMonths = [
  'जन', 'फेब', 'मार्च', 'अप्रि', 'मे', 'जुन',
  'जुल', 'अग', 'सेप', 'अक्टो', 'नोभे', 'डिसे'
];
const _neDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];

String _toNeDigits(String s) =>
    s.replaceAllMapped(RegExp(r'\d'), (m) => _neDigits[int.parse(m[0]!)]);

/// 'YYYY-MM-DD' -> a human-friendly label; null for missing/invalid input.
/// Invalid shapes are returned as-is (same as the TS original).
String? formatDob(String? dob, {required bool nepali}) {
  if (dob == null || dob.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dob);
  if (match == null) return dob;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return dob;
  final date = DateTime(year, month, day);
  // Rejects impossible calendar dates like 2001-02-30, which DateTime rolls over.
  if (date.month != month || date.day != day) return dob;
  final dd = day.toString().padLeft(2, '0');
  if (nepali) {
    return '${_toNeDigits(dd)} ${_neMonths[month - 1]} ${_toNeDigits('$year')}';
  }
  return '$dd ${_enMonths[month - 1]} $year';
}

/// Splits a legacy single `name` field into first/last for the edit form.
Map<String, String> splitName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return {'firstName': '', 'lastName': ''};
  return {'firstName': parts.first, 'lastName': parts.skip(1).join(' ')};
}

String fullNameOf(String firstName, String lastName) =>
    [firstName.trim(), lastName.trim()].where((p) => p.isNotEmpty).join(' ');

/// Formats raw digits typed by the user into a 'YYYY-MM-DD' mask.
/// Mirrors maskDobInput() in profile.ts.
String maskDobInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final d = digits.length > 8 ? digits.substring(0, 8) : digits;
  if (d.length <= 4) return d;
  if (d.length <= 6) return '${d.substring(0, 4)}-${d.substring(4)}';
  return '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6)}';
}

/// Real-calendar DOB check. Mirrors isValidDob() in profile.ts: rejects
/// impossible dates like 2001-02-30 (which DateTime would roll over), future
/// dates, and years before 1900.
bool isValidDob(String dob) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dob);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  final date = DateTime.tryParse('${dob}T00:00:00');
  if (date == null) return false;
  if (date.month != month || date.day != day) return false;
  if (date.isAfter(DateTime.now())) return false;
  return year >= 1900;
}

/// Merge-writes the editable profile fields via PATCH /me.
/// Mirrors updateUserProfile() in profile.ts.
///
/// Phase-3: identity rides the Bearer token (the [uid] parameter is kept
/// for signature parity with the old Firestore write). The worker's PATCH
/// merge treats an explicit null as a CLEAR for dob / gender /
/// photoURLSource — the same semantics the Firestore merge had — so
/// cleared fields are sent as nulls, never omitted. One exception:
/// photoURL is stringified server-side, so a cleared photo is sent as ''
/// (the established clear encoding; readers treat '' like no photo).
///
/// [photoURLSource] is 'manual' | 'none' when the photo was touched, null to
/// leave the existing source unchanged (so a Google re-login cannot replace
/// a manually uploaded Cloudinary photo).
Future<void> updateUserProfile(
  String uid, {
  required String firstName,
  required String lastName,
  String? dob,
  String? gender,
  String? photoURL,
  String? photoURLSource,
}) {
  return CfApi.patchMe({
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'name': fullNameOf(firstName, lastName),
    'dob': dob,
    'gender': gender,
    'photoURL': photoURL ?? '',
    if (photoURLSource != null) 'photoURLSource': photoURLSource,
  });
}

/// Coverage percent for the stats ring. Sub-10% values keep one decimal —
/// Math.round would print a flat "0%" through the first few hundred questions,
/// exactly when seeing the number move matters most.
double displayCoveragePercent(double percent) {
  final value = percent.isFinite ? percent.clamp(0.0, 100.0) : 0.0;
  if (value == 0) return 0;
  if (value < 0.1) return 0.1;
  if (value < 10) return (value * 10).round() / 10;
  return value.roundToDouble();
}

/// Tests taken from a stored aggregate breakdown
/// (exam.attempts + dailyTest.attempts).
int testsTakenOf(Map<String, dynamic> breakdown) {
  int numAt(List<String> path) {
    Object? cur = breakdown;
    for (final k in path) {
      if (cur is Map<String, dynamic>) {
        cur = cur[k];
      } else {
        return 0;
      }
    }
    return cur is num && cur.isFinite && cur >= 0 ? cur.round() : 0;
  }

  return numAt(['exam', 'attempts']) + numAt(['dailyTest', 'attempts']);
}

// ---------------------------------------------------------------------------
// Reads / writes
// ---------------------------------------------------------------------------

String? _asString(Object? v) => v is String ? v : null;

String? _toGender(Object? v) =>
    v == 'male' || v == 'female' || v == 'other' ? v as String : null;

/// Normalises a GET /me row into a [UserProfile]. `firstName`/`lastName`
/// fall back to splitting the legacy `name` field. D1 rows may carry
/// scalars as text ('true', JSON-encoded maps), so booleans and the stats
/// map are decoded defensively. Also seeds the stats baseline the store's
/// setScore composes against.
///
/// Phase-3: the old Firestore fetch also BACKFILLED a missing stats map
/// with a write — that write is dropped; readers default missing stats to
/// zeros (UserStats.fromMap), which is all the backfill ever produced.
UserProfile profileFromMeRow(String uid, Map<String, dynamic> doc) {
  final name = _asString(doc['name']) ?? '';
  final storedFirst = _asString(doc['firstName']) ?? '';
  final storedLast = _asString(doc['lastName']) ?? '';
  final derived = splitName(name);

  final statsRaw = CfApi.decodeFieldValue(doc['stats']);
  final stats =
      UserStats.fromMap(statsRaw is Map ? statsRaw.cast<String, dynamic>() : null);
  // Seed the baseline every writer composes its partial update against.
  _statsBaseline[uid] = stats;

  final photoURL = _asString(doc['photoURL']);
  final source = _asString(doc['photoURLSource']);
  return UserProfile(
    uid: uid,
    name: name,
    firstName: storedFirst.isNotEmpty ? storedFirst : derived['firstName']!,
    lastName: storedLast.isNotEmpty ? storedLast : derived['lastName']!,
    email: _asString(doc['email']),
    dob: _asString(doc['dob']),
    gender: _toGender(doc['gender']),
    photoURL: photoURL,
    photoURLSource: source == 'manual' || source == 'google' || source == 'none'
        ? source!
        : (photoURL != null && photoURL.isNotEmpty ? 'manual' : 'none'),
    courseId: _asString(doc['courseId']),
    subcourseId: _asString(doc['subcourseId']),
    stats: stats,
    isAdmin: doc['role'] == 'admin' || CfJson.asBool(doc['isAdmin']),
    isPremium: CfJson.asBool(doc['isPremium']),
    premiumPlanName: _asString(doc['premiumPlanName']),
    premiumBillingCycle: _asString(doc['premiumBillingCycle']),
    premiumExpiryDate: _asString(doc['premiumExpiryDate']),
  );
}

/// Fetches the user's selected course + subcourse names via
/// GET /profile/course-info (the worker resolves the course/subcourse
/// documents, including the legacy flat-collection fallback). The [uid] /
/// [userDoc] parameters are kept for signature parity — identity rides
/// the Bearer token and the worker reads the profile itself.
Future<UserCourseInfo?> fetchUserCourseInfo(String uid,
    {Map<String, dynamic>? userDoc}) async {
  final row = await CfApi.getProfileCourseInfo().catchError((_) => null);
  if (row == null) return null;
  return UserCourseInfo(
    courseId: _asString(row['courseId']),
    subcourseId: _asString(row['subcourseId']),
    courseName: _asString(row['courseName'])?.trim(),
    subcourseName: _asString(row['subcourseName'])?.trim(),
  );
}

// ---------------------------------------------------------------------------
// stats mirror bookkeeping (mirrors the baseline cache in profile.ts)
// ---------------------------------------------------------------------------

final Map<String, UserStats> _statsBaseline = {};

/// Last known stats map for a user, or null when none has been read yet.
UserStats? peekUserStats(String uid) => _statsBaseline[uid];

/// Drops the cached baseline. Call with no argument on sign-out.
void forgetUserStats([String? uid]) {
  if (uid != null) {
    _statsBaseline.remove(uid);
  } else {
    _statsBaseline.clear();
  }
}



// ---------------------------------------------------------------------------
// Shared store (mirrors profileStore.ts)
// ---------------------------------------------------------------------------

/// Shared user-profile state (singleton).
///
/// Warmed once per session; the Profile tab, Home header and Edit Profile all
/// read this single store so a save shows up everywhere instantly. The stats
/// card's aggregate rides along for the same reason: it is one stored document
/// read, so fetching it on every tab visit only ever bought a skeleton.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  UserProfile? profile;
  UserCourseInfo? courseInfo;

  /// True only for the very first load, so the screen can skip its spinner on
  /// refetches (pull-to-refresh keeps content on screen).
  bool loading = false;
  bool refreshing = false;

  /// `error` counts as ready: a failed load shows the page (with its retry
  /// affordances), never an infinite spinner.
  bool error = false;

  /// uid the current data belongs to — guards against showing a previous
  /// user's data.
  String? loadedUid;

  /// The whole-app aggregate behind the stats card.
  MainLeaderboardScore? score;

  /// Plan name of the user's active app_subscriptions record — the SAME
  /// source the Subscription Details page reads
  /// ([SubscriptionService.currentActiveRecord]: the last-approved active
  /// record, which is also what the users/{uid} premium mirror describes).
  /// The mirror is only written at approval time and can disagree with the
  /// ledger (stale/manual data, approvals that predate the mirror); the
  /// ledger wins for display. Null while the lookup hasn't settled — see
  /// [activePlanLoaded].
  String? activePlanName;

  /// True once the active-subscription lookup has settled, even when there
  /// is no active record. Distinguishes "still loading" (show the mirrored
  /// fields) from "no active plan" (show Free Plan, like Subscription
  /// Details does).
  bool activePlanLoaded = false;

  /// Starts true: until the first attempt settles we genuinely do not know the
  /// numbers, and a skeleton is more honest than zeroes that silently become
  /// real data a moment later.
  bool scoreLoading = true;

  String? _inFlightUid;
  Future<void>? _inFlight;
  int _scoreRequestToken = 0;

  Future<void> load(String uid,
      {bool force = false, bool refresh = false}) async {
    final alreadyLoaded = loadedUid == uid && profile != null;
    if (alreadyLoaded && !force && !refresh) return;

    // Share the in-flight request so concurrent warm-ups don't issue
    // duplicate profile/course reads.
    if (_inFlightUid == uid && _inFlight != null) {
      await _inFlight;
      return;
    }

    final request = () async {
      if (refresh) {
        refreshing = true;
        error = false;
      } else {
        loading = !alreadyLoaded;
        error = false;
      }
      notifyListeners();

      try {
        // Phase-3: the profile comes from GET /me and the course info
        // from GET /profile/course-info. A throwing read means a real
        // failure -> error state; a missing row means an empty-but-ready
        // page.
        final meRow = await CfApi.getMe();
        final fetchedProfile =
            meRow == null ? null : profileFromMeRow(uid, meRow);
        final fetchedCourse =
            await fetchUserCourseInfo(uid).catchError((_) => null);

        profile = fetchedProfile;
        courseInfo = fetchedCourse;
        loadedUid = uid;
        loading = false;
        refreshing = false;
        error = false;
        notifyListeners();

        // Deliberately NOT awaited, and deliberately after the notify above:
        // the header only needs the profile, and making it wait on a
        // stats-card read would slow down what the user sees first.
        unawaited(loadScore(uid, fetchedCourse?.subcourseId));
        // Same treatment for the plan label: the mirrored users/{uid}
        // fields show immediately, then the ledger (the Subscription
        // Details page's source) corrects the label if they disagree.
        unawaited(_loadActivePlan(uid));
      } catch (_) {
        loading = false;
        refreshing = false;
        error = true;
        notifyListeners();
      }
    }();

    _inFlightUid = uid;
    _inFlight = request;
    try {
      await request;
    } finally {
      if (_inFlight == request) {
        _inFlight = null;
        _inFlightUid = null;
      }
    }
  }

  /// Reads the stats-card aggregate. Pass a null subcourse for a user who
  /// has not enrolled.
  /// Best-effort fetch of the active subscription record's plan name, using
  /// the exact same pick as the Subscription Details page
  /// ([SubscriptionService.currentActiveRecord]: the last-approved active
  /// record, which is also what the users/{uid} premium mirror describes).
  /// Never throws: on failure the mirrored user-doc fields stay as the
  /// label fallback, and a later refresh retries.
  Future<void> _loadActivePlan(String uid) async {
    try {
      final history = await SubscriptionService.fetchMySubscriptionHistory(uid);
      final active = SubscriptionService.currentActiveRecord(history);
      // The user may have signed out / switched while the read was away.
      if (loadedUid != uid) return;
      activePlanName = active?.planName;
      activePlanLoaded = true;
      notifyListeners();
    } catch (_) {
      // Keep the mirrored fallback.
    }
  }

  Future<void> loadScore(String uid, String? subcourseId) async {
    final token = ++_scoreRequestToken;
    if (uid.isEmpty || subcourseId == null || subcourseId.isEmpty) {
      score = null;
      scoreLoading = false;
      notifyListeners();
      return;
    }
    scoreLoading = true;
    notifyListeners();
    // Phase-3: the aggregate is the Phase-1 leaderboard response's 'own'
    // row (the worker's stored app_main_leaderboard aggregate) — the old
    // direct Firestore read of users/{uid}/app_mainleaderboard is gone.
    MainLeaderboardScore? fetched;
    try {
      final courseId = courseInfo?.courseId ?? profile?.courseId ?? '';
      final result = await CfApi.getLeaderboard(
          courseId: courseId, subcourseId: subcourseId);
      final own = result.own;
      fetched = own == null ? null : MainLeaderboardScore.fromMap(own);
    } catch (_) {
      fetched = null;
    }
    // Someone signed out, switched course, or published a fresher score while
    // this read was in flight — our answer is now the stale one.
    if (token != _scoreRequestToken) return;
    score = fetched;
    scoreLoading = false;
    notifyListeners();
  }

  /// Hand the store a score that was just recomputed elsewhere instead of
  /// re-reading it — fresher than the stored copy and one read cheaper.
  void setScore(MainLeaderboardScore? s) {
    _scoreRequestToken += 1;
    final p = profile;
    final stats = loadedUid != null ? peekUserStats(loadedUid!) : null;
    score = s;
    scoreLoading = false;
    if (p != null && stats != null) {
      profile = p.copyWith(stats: stats);
    }
    notifyListeners();
  }

  /// Merge locally-known changes so every screen re-renders immediately
  /// (e.g. right after an Edit Profile save).
  void applyLocalPatch(UserProfile Function(UserProfile) patch) {
    final current = profile;
    if (current == null) return;
    profile = patch(current);
    notifyListeners();
  }

  void clear() {
    _scoreRequestToken += 1;
    // The stats baseline is a mirror of one account's numbers and has no
    // business outliving the session that read it.
    forgetUserStats();
    profile = null;
    courseInfo = null;
    loadedUid = null;
    loading = false;
    refreshing = false;
    error = false;
    score = null;
    activePlanName = null;
    activePlanLoaded = false;
    // Back to "not known yet", not "known to be empty" — the next account's
    // card should open on a skeleton, not on somebody else's blank slate.
    scoreLoading = true;
    notifyListeners();
  }
}
