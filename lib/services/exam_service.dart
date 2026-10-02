/// Exam engine data layer — mirrors src/core/firebase/services/examHub.ts,
/// services/exams.ts, services/dailyTest.ts, services/qotd.ts and the main
/// leaderboard service from the Expo app.
///
/// Pure Dart `http` REST client (like FirestoreRest) so no native Firebase SDK
/// is needed. All functions take the raw Firestore fields and parse defensively.
library;

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'auth_service.dart';
import 'prefs_service.dart';
import 'server_clock.dart';

// ---------------------------------------------------------------------------
/// Thrown when Firestore refuses a query because the composite index backing
/// it has not been created in the Firebase console yet. Callers fall back to
/// a cheaper/legacy behavior and (optionally) tell the user the one-time
/// console step that unlocks the fast path.
class MissingIndexException implements Exception {
  final String message;
  MissingIndexException(this.message);
  @override
  String toString() => 'MissingIndexException: $message';
}

// Firestore REST plumbing (returns doc IDs alongside fields)
// ---------------------------------------------------------------------------

class ExamRest {
  static String get _base =>
      'https://firestore.googleapis.com/v1/projects/${AppConfig.firebaseProjectId}/databases/(default)/documents';

  static Map<String, String> _headers(String idToken) => {
        'Content-Type': 'application/json',
        if (idToken.isNotEmpty) 'Authorization': 'Bearer $idToken',
      };

  static Future<String> _token() => AuthService.getValidIdToken();

  static dynamic decode(dynamic v) {
    if (v is! Map<String, dynamic>) return v;
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('integerValue'))
      return int.tryParse('${v['integerValue']}');
    if (v.containsKey('doubleValue'))
      return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue')) return v['booleanValue'];
    if (v.containsKey('nullValue')) return null;
    if (v.containsKey('timestampValue')) {
      return DateTime.tryParse(v['timestampValue'] as String? ?? '');
    }
    if (v.containsKey('mapValue')) {
      final fields = v['mapValue']['fields'] as Map<String, dynamic>? ?? {};
      return fields.map((k, val) => MapEntry(k, decode(val)));
    }
    if (v.containsKey('arrayValue')) {
      final values = v['arrayValue']['values'] as List? ?? [];
      return values.map(decode).toList();
    }
    if (v.containsKey('referenceValue')) return v['referenceValue'];
    return v;
  }

  static Map<String, dynamic> encode(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
    if (v is List) {
      return {
        'arrayValue': {'values': v.map(encode).toList()}
      };
    }
    if (v is Map) {
      return {
        'mapValue': {'fields': v.map((k, val) => MapEntry('$k', encode(val)))}
      };
    }
    return {'stringValue': '$v'};
  }

  static String _docId(String name) =>
      name.split('/').where((s) => s.isNotEmpty).last;

  static Map<String, dynamic> _docToMap(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};
    final m = fields.map((k, v) => MapEntry(k, decode(v)));
    m['id'] = _docId('${doc['name'] ?? ''}');
    return m;
  }

  /// Get a single document by full path (e.g. 'app_exam_sets/abc'). Null on 404.
  static Future<Map<String, dynamic>?> getDoc(String path) async {
    final token = await _token();
    final res =
        await http.get(Uri.parse('$_base/$path'), headers: _headers(token));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200)
      throw Exception('getDoc $path: ${res.statusCode}');
    return _docToMap(json.decode(res.body) as Map<String, dynamic>);
  }

  /// List documents in a collection (or subcollection path like
  /// 'users/{uid}/exam_attempts'). Returned maps include 'id'.
  static Future<List<Map<String, dynamic>>> listDocs(
    String collectionPath, {
    int pageSize = 200,
  }) async {
    final token = await _token();
    final res = await http.get(
      Uri.parse('$_base/$collectionPath?pageSize=$pageSize'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) {
      throw Exception('listDocs $collectionPath: ${res.statusCode}');
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    final docs = body['documents'] as List? ?? [];
    return docs.map((d) => _docToMap(d as Map<String, dynamic>)).toList();
  }

  /// Structured query. [parent] scopes a collection-group style query under a
  /// document path (e.g. 'users/{uid}' for subcollection 'attempts').
  /// [startAfter] holds already-encoded cursor values matching [orderBy]
  /// (a `startAt` cursor with `before: false`).
  static Future<List<Map<String, dynamic>>> runQuery(
    String collectionId, {
    String? parent,
    Map<String, dynamic>? where,
    List<Map<String, dynamic>>? orderBy,
    int limit = 100,
    List<Map<String, dynamic>>? startAfter,
  }) async {
    final token = await _token();
    final from = {
      'collectionId': collectionId,
    };
    final structured = <String, dynamic>{
      'from': [from]
    };
    // NOTE: `parent` is NOT a valid StructuredQuery field (Firestore returns
    // 400 "Unknown name parent"). Like React's runQuery, the parent document
    // path goes in the URL: .../documents/{parent}:runQuery.
    if (where != null) structured['where'] = where;
    if (orderBy != null) structured['orderBy'] = orderBy;
    if (startAfter != null) {
      structured['startAt'] = {'values': startAfter, 'before': false};
    }
    structured['limit'] = limit;
    final url = parent != null ? '$_base/$parent:runQuery' : '$_base:runQuery';
    final res = await http.post(
      Uri.parse(url),
      headers: _headers(token),
      body: json.encode({'structuredQuery': structured}),
    );
    if (res.statusCode != 200) {
      if (_isMissingIndex(res.statusCode, res.body)) {
        throw MissingIndexException('runQuery $collectionId: ${res.body}');
      }
      throw Exception('runQuery $collectionId: ${res.statusCode} ${res.body}');
    }
    final list = json.decode(res.body) as List? ?? [];
    return list
        .map((e) => (e as Map)['document'] as Map<String, dynamic>?)
        .where((d) => d != null)
        .map((d) => _docToMap(d!))
        .toList();
  }

  /// True when Firestore refused a query because the composite index does not
  /// exist yet (HTTP 400 + FAILED_PRECONDITION / "requires an index").
  static bool _isMissingIndex(int statusCode, String body) {
    if (statusCode != 400) return false;
    return body.contains('FAILED_PRECONDITION') ||
        body.contains('requires an index');
  }

  /// Count aggregation over a structured query — used for rank computation
  /// without reading every document. Billed ~1 read per 1000 index entries
  /// matched. Throws [MissingIndexException] when the composite index
  /// backing the query does not exist yet.
  static Future<int> runCount(
    String collectionId, {
    Map<String, dynamic>? where,
  }) async {
    final token = await _token();
    final structured = <String, dynamic>{
      'from': [
        {'collectionId': collectionId}
      ],
    };
    if (where != null) structured['where'] = where;
    final res = await http.post(
      Uri.parse('$_base:runAggregationQuery'),
      headers: _headers(token),
      body: json.encode({
        'structuredQuery': structured,
        'aggregations': [
          {
            'alias': 'cnt',
            'count': <String, dynamic>{},
          }
        ],
      }),
    );
    if (res.statusCode != 200) {
      if (_isMissingIndex(res.statusCode, res.body)) {
        throw MissingIndexException('runCount $collectionId: ${res.body}');
      }
      throw Exception('runCount $collectionId: ${res.statusCode} ${res.body}');
    }
    final list = json.decode(res.body) as List? ?? [];
    if (list.isEmpty) return 0;
    final agg =
        ((list.first as Map)['result'] as Map?)?['aggregateFields']?['cnt'];
    return int.tryParse('${agg?['integerValue'] ?? 0}') ?? 0;
  }

  /// Operator aliases are normalized: '==' → 'EQUAL', '!=' → 'NOT_EQUAL',
  /// '<' → 'LESS_THAN', '<=' → 'LESS_THAN_OR_EQUAL', '>' → 'GREATER_THAN',
  /// '>=' → 'GREATER_THAN_OR_EQUAL'. Raw Firestore REST enum values pass
  /// through unchanged.
  static Map<String, dynamic> fieldFilter(
      String field, String op, dynamic value) {
    const aliases = {
      '==': 'EQUAL',
      '!=': 'NOT_EQUAL',
      '<': 'LESS_THAN',
      '<=': 'LESS_THAN_OR_EQUAL',
      '>': 'GREATER_THAN',
      '>=': 'GREATER_THAN_OR_EQUAL',
    };
    final norm = aliases[op] ?? op;
    return {
      'fieldFilter': {
        'field': {'fieldPath': field},
        'op': norm,
        'value': encode(value),
      }
    };
  }

  static Map<String, dynamic> orderField(String field, String direction) => {
        'field': {'fieldPath': field},
        'direction': direction,
      };

  /// Create a document with an auto-generated ID; returns the new doc ID.
  ///
  /// [serverTimestampFields] lists field paths that must be set to the real
  /// Firestore server time (REQUEST_TIME), e.g. `createdAt`. The plain
  /// createDocument endpoint cannot do server timestamps, so when the list is
  /// non-empty the write goes through `:commit` with `updateTransforms` and a
  /// client-generated ID (same 20-char alphabet Firestore uses).
  static Future<String> createDoc(
    String collectionPath,
    Map<String, dynamic> data, {
    List<String> serverTimestampFields = const [],
  }) async {
    final token = await _token();
    if (serverTimestampFields.isEmpty) {
      final res = await http.post(
        Uri.parse('$_base/$collectionPath'),
        headers: _headers(token),
        body:
            json.encode({'fields': data.map((k, v) => MapEntry(k, encode(v)))}),
      );
      if (res.statusCode != 200) {
        throw Exception(
            'createDoc $collectionPath: ${res.statusCode} ${res.body}');
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      return _docId('${body['name'] ?? ''}');
    }
    final id = _newDocId();
    final fields = Map<String, dynamic>.fromEntries(
        data.entries.map((e) => MapEntry(e.key, encode(e.value))));
    for (final f in serverTimestampFields) {
      fields.remove(f);
    }
    final body = {
      'writes': [
        {
          'update': {
            'name':
                'projects/${AppConfig.firebaseProjectId}/databases/(default)/documents/$collectionPath/$id',
            'fields': fields,
          },
          'updateTransforms': [
            for (final f in serverTimestampFields)
              {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
          ],
        },
      ],
    };
    final res = await http.post(
      Uri.parse('$_base:commit'),
      headers: _headers(token),
      body: json.encode(body),
    );
    if (res.statusCode != 200) {
      throw Exception(
          'createDoc $collectionPath: ${res.statusCode} ${res.body}');
    }
    return id;
  }

  static final _rand = Random();

  /// Client-side Firestore-style document ID (20 chars, same alphabet).
  static String _newDocId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (_) => chars[_rand.nextInt(chars.length)]).join();
  }

  /// Full-document PATCH write (no update mask).
  ///
  /// [serverTimestampFields] lists field paths set to the real Firestore
  /// server time (REQUEST_TIME) via a `:commit` update transform — mirrors
  /// `serverTimestamp()` in the React code.
  static Future<void> setDoc(String path, Map<String, dynamic> data,
      {List<String> serverTimestampFields = const []}) async {
    final token = await _token();
    if (serverTimestampFields.isEmpty) {
      final res = await http.patch(
        Uri.parse('$_base/$path'),
        headers: _headers(token),
        body:
            json.encode({'fields': data.map((k, v) => MapEntry(k, encode(v)))}),
      );
      if (res.statusCode != 200) {
        throw Exception('setDoc $path: ${res.statusCode} ${res.body}');
      }
      return;
    }
    final fields = Map<String, dynamic>.fromEntries(
        data.entries.map((e) => MapEntry(e.key, encode(e.value))));
    for (final f in serverTimestampFields) {
      fields.remove(f);
    }
    final res = await http.post(
      Uri.parse('$_base:commit'),
      headers: _headers(token),
      body: json.encode({
        'writes': [
          {
            'update': {
              'name':
                  'projects/${AppConfig.firebaseProjectId}/databases/(default)/documents/$path',
              'fields': fields,
            },
            'updateTransforms': [
              for (final f in serverTimestampFields)
                {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
            ],
          },
        ],
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('setDoc $path: ${res.statusCode} ${res.body}');
    }
  }

  static String? get uid => AuthService.currentUser?.uid;
}

// ---------------------------------------------------------------------------
// Safe parsing helpers
// ---------------------------------------------------------------------------

int _num(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  return fallback;
}

double _dbl(dynamic v, [double fallback = 0.0]) {
  if (v is num) return v.toDouble();
  return fallback;
}

String _str(dynamic v, [String fallback = '']) {
  if (v is String) return v;
  return fallback;
}

bool _bool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (['false', '0', 'no', 'off', 'draft', 'unpublished'].contains(s)) {
      return false;
    }
    return true;
  }
  if (v is num) return v != 0;
  return fallback;
}

List<String> _strList(dynamic v) {
  if (v is List) return v.whereType<String>().toList();
  return [];
}

DateTime? _dt(dynamic v) {
  if (v is DateTime) return v;
  return null;
}

/// True when the user's profile doc stores courseId/subcourseId.
Future<Map<String, String>> fetchCourseScope(String uid) async {
  final doc = await ExamRest.getDoc('users/$uid').catchError((_) => null);
  return {
    'courseId': _str(doc?['courseId']),
    'subcourseId': _str(doc?['subcourseId']),
  };
}

// ---------------------------------------------------------------------------
// Profile (users/{uid}) — name/photo/premium used by rankings + gating
// ---------------------------------------------------------------------------

class UserProfile {
  final String uid;
  final String name;
  final String? photoURL;
  final bool isPro;
  final bool isPremium;
  final DateTime? premiumExpiryDate;
  final String courseId;
  final String subcourseId;

  /// Whether the raw `premiumExpiryDate` key was present and non-empty.
  /// Needed to mirror React exactly: absent => active, present-but-unparseable
  /// => expired.
  final bool _hasPremiumExpiry;

  UserProfile({
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.isPro,
    required this.isPremium,
    required this.premiumExpiryDate,
    required this.courseId,
    required this.subcourseId,
    bool hasPremiumExpiry = false,
  }) : _hasPremiumExpiry = hasPremiumExpiry;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) {
    var isPro = _bool(m['isPro']);
    final premiumUntil = _dt(m['premiumUntil']);
    if (premiumUntil != null && premiumUntil.isAfter(DateTime.now())) {
      isPro = true;
    }
    final status = _str(m['subscriptionStatus']);
    if (status == 'active' || status == 'premium') isPro = true;
    final expiryRaw = m['premiumExpiryDate'];
    final hasExpiryValue =
        expiryRaw != null && !(expiryRaw is String && expiryRaw.isEmpty);
    return UserProfile(
      uid: uid,
      name: _str(m['name'], _str(m['displayName'], 'Anonymous')),
      photoURL: m['photoURL'] is String ? m['photoURL'] as String : null,
      isPro: isPro,
      isPremium: _bool(m['isPremium']),
      premiumExpiryDate: _parseFlexibleDateTime(expiryRaw),
      courseId: _str(m['courseId']),
      subcourseId: _str(m['subcourseId']),
      hasPremiumExpiry: hasExpiryValue,
    );
  }

  /// Mirrors hasActivePremium() in profile.ts exactly:
  /// `isPremium` must be true; an absent (or empty) expiry means active;
  /// a present-but-unparseable expiry means expired; otherwise the expiry
  /// must be in the future (server-corrected clock, so the device clock
  /// cannot extend premium).
  bool get hasActivePremium {
    if (!isPremium) return false;
    if (!_hasPremiumExpiry) return true;
    final expiry = premiumExpiryDate;
    if (expiry == null) return false;
    return expiry.isAfter(ServerClock.nowUtc());
  }
}

/// Parses a Firestore-decoded date that may be a DateTime (timestampValue),
/// an ISO-8601 string, or epoch millis. Null when absent or unparseable.
DateTime? _parseFlexibleDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is num) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    } catch (_) {
      return null;
    }
  }
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
  return null;
}

Future<UserProfile?> fetchUserProfile(String uid) async {
  final doc = await ExamRest.getDoc('users/$uid').catchError((_) => null);
  if (doc == null) return null;
  return UserProfile.fromMap(uid, doc);
}

// ---------------------------------------------------------------------------
// Exam Hub (app_exam_sets / app_exam_rules / exam_attempts / app_exam_rankings)
// ---------------------------------------------------------------------------

class ExamQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  ExamQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory ExamQuestion.fromMap(Map<String, dynamic> m) => ExamQuestion(
        question: _str(m['question']),
        options: (m['options'] as List?)?.map((e) => '$e').toList() ?? [],
        correctIndex: _num(m['correctIndex']),
        explanation: _str(m['explanation']),
      );
}

class ExamSet {
  final String id;
  final String courseId;
  final String subcourseId;
  final List<String> courseIds;
  final List<String> subcourseIds;
  final String provinceId;
  final String sectionId;
  final bool isPublished;
  final String title;
  final double price;
  final String currency;
  final DateTime? startTime;
  final int totalQuestions;
  final int durationMinutes;
  final int passPercent;
  final String accessType; // free | pro
  final String difficulty;
  final String contentType; // mcq | pdf
  final String? pdfUrl;
  final List<ExamQuestion> questions;

  ExamSet({
    required this.id,
    required this.courseId,
    required this.subcourseId,
    required this.courseIds,
    required this.subcourseIds,
    required this.provinceId,
    required this.sectionId,
    required this.isPublished,
    required this.title,
    required this.price,
    required this.currency,
    required this.startTime,
    required this.totalQuestions,
    required this.durationMinutes,
    required this.passPercent,
    required this.accessType,
    required this.difficulty,
    required this.contentType,
    required this.pdfUrl,
    required this.questions,
  });

  factory ExamSet.fromMap(Map<String, dynamic> m) {
    // Legacy alias normalisation on read (React: examHub):
    // old 'mcq'/'theory' ids map to the current section ids.
    final rawSection = _str(m['sectionId']);
    final rawSubIds = _strList(m['subcourseIds']);
    final rawCourseIds = _strList(m['courseIds']);
    return ExamSet(
        id: _str(m['id']),
        courseId: _str(m['courseId']),
        subcourseId: _str(m['subcourseId']),
        courseIds:
            rawCourseIds.isNotEmpty ? rawCourseIds : [_str(m['courseId'])]
              ..removeWhere((e) => e.isEmpty),
        subcourseIds:
            rawSubIds.isNotEmpty ? rawSubIds : [_str(m['subcourseId'])]
              ..removeWhere((e) => e.isEmpty),
        provinceId: _str(m['provinceId']),
        sectionId: normalizeExamSectionId(rawSection),
        isPublished: _bool(m['isPublished'], true),
        title: _str(m['title']),
        price: _dbl(m['price']),
        currency: _str(m['currency'], 'NPR'),
        startTime: _dt(m['startTime']),
        totalQuestions: _num(m['totalQuestions']),
        durationMinutes: _num(m['durationMinutes'], 60),
        passPercent: _num(m['passPercent'], 40),
        accessType: _str(m['accessType'], 'free'),
        difficulty: _str(m['difficulty'], 'medium'),
        contentType: _str(m['contentType'], 'mcq'),
        pdfUrl: m['pdfUrl'] is String ? m['pdfUrl'] as String : null,
        questions: ((m['questions'] as List?) ?? [])
            .map(
                (q) => ExamQuestion.fromMap((q as Map).cast<String, dynamic>()))
            .toList(),
      );
  }

  bool get isPro => accessType == 'pro';
}

class ExamAttempt {
  final String id;
  final String examSetId;
  final String courseId;
  final String subcourseId;
  final int attemptNumber;
  final int score; // percent 0..100
  final int totalQuestions;
  final int correct;
  final int incorrect;
  final int skipped;
  final bool passed;
  final int timeTakenSeconds;
  final List<int> answers; // -1 = skipped
  final DateTime? createdAt;

  ExamAttempt({
    required this.id,
    required this.examSetId,
    required this.courseId,
    required this.subcourseId,
    required this.attemptNumber,
    required this.score,
    required this.totalQuestions,
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.passed,
    required this.timeTakenSeconds,
    required this.answers,
    required this.createdAt,
  });

  factory ExamAttempt.fromMap(Map<String, dynamic> m) => ExamAttempt(
        id: _str(m['id']),
        examSetId: _str(m['examSetId']),
        courseId: _str(m['courseId']),
        subcourseId: _str(m['subcourseId']),
        attemptNumber: _num(m['attemptNumber'], 1),
        score: _num(m['score']),
        totalQuestions: _num(m['totalQuestions']),
        correct: _num(m['correct']),
        incorrect: _num(m['incorrect']),
        skipped: _num(m['skipped']),
        passed: _num(m['passed']) == 1,
        timeTakenSeconds: _num(m['timeTakenSeconds']),
        answers:
            ((m['answers'] as List?) ?? []).map((a) => _num(a, -1)).toList(),
        createdAt: _dt(m['createdAt']),
      );
}

class RankingRow {
  final String id;
  final String uid;
  final String name;
  final String? photoURL;
  final bool isPro;
  final int score;
  final int timeTakenSeconds;
  final DateTime? createdAt;

  RankingRow({
    required this.id,
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.isPro,
    required this.score,
    required this.timeTakenSeconds,
    required this.createdAt,
  });

  factory RankingRow.fromMap(Map<String, dynamic> m) => RankingRow(
        id: _str(m['id']),
        uid: _str(m['uid']),
        name: _str(m['name'], 'Anonymous'),
        photoURL: m['photoURL'] is String ? m['photoURL'] as String : null,
        isPro: _bool(m['isPro']),
        score: _num(m['score']),
        timeTakenSeconds: _num(m['timeTakenSeconds']),
        createdAt: _dt(m['createdAt']),
      );
}

class ExamRule {
  final String icon;
  final String title;
  final String description;

  ExamRule(
      {required this.icon, required this.title, required this.description});

  factory ExamRule.fromMap(Map<String, dynamic> m) => ExamRule(
        icon: _str(m['icon']),
        title: _str(m['title']),
        description: _str(m['description']),
      );
}

class ScoreBreakdown {
  final int correct;
  final int incorrect;
  final int skipped;
  final double marks;
  final int percent;
  final double negativeMarks;
  final bool passed;

  ScoreBreakdown({
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.marks,
    required this.percent,
    required this.negativeMarks,
    required this.passed,
  });
}

/// Single source of truth for exam scoring — mirrors scoreAttempt().
ScoreBreakdown scoreExamAttempt(
    List<ExamQuestion> questions, List<int?> answers, int passPercent) {
  var correct = 0;
  var incorrect = 0;
  var skipped = 0;
  for (var i = 0; i < questions.length; i++) {
    final chosen = i < answers.length ? answers[i] : null;
    if (chosen == null || chosen < 0) {
      skipped += 1;
    } else if (chosen == questions[i].correctIndex) {
      correct += 1;
    } else {
      incorrect += 1;
    }
  }
  const negativePerWrong = 0.25;
  final negativeMarks = incorrect * negativePerWrong;
  final marks = (correct - negativeMarks).clamp(0.0, double.infinity);
  final total = questions.isEmpty ? 1 : questions.length;
  final percent = ((marks / total) * 100).round();
  return ScoreBreakdown(
    correct: correct,
    incorrect: incorrect,
    skipped: skipped,
    marks: marks,
    percent: percent,
    negativeMarks: negativeMarks,
    passed: percent >= passPercent,
  );
}

/// Review/ranking unlock once the exam window has closed (start + duration).
bool areResultsUnlocked(ExamSet set, DateTime now) =>
    !now.isBefore(resultsUnlockAt(set, now));

/// The instant results unlock: start + duration. Sets with no scheduled start
/// are always unlocked. (React: examHub.resultsUnlockAt.)
DateTime resultsUnlockAt(ExamSet set, DateTime now) {
  if (set.startTime == null) return now;
  return set.startTime!.add(Duration(minutes: set.durationMinutes));
}

/// Lead-in before a scheduled exam start at which a hidden card switches to
/// the visible countdown state (React: examHub.CARD_REVEAL_LEAD_MS).
const cardRevealLead = Duration(minutes: 10);

/// Province id meaning "every province" — mirrors examHub.ALL_PROVINCES.
/// When selected, [fetchExamSets] skips the province filter entirely.
const allProvinces = 'all';

/// Exam-card lifecycle state — mirrors examHub.resolveExamCardState.
enum ExamCardState { hidden, countdown, ready, rejoin, pending, locked }

/// Resolves the lifecycle state of an exam card (React: resolveExamCardState):
/// - pro && pending purchase && !purchased  -> pending
/// - pro && !purchased                      -> locked
/// - no startTime                           -> always open
/// - now < start - 10min                    -> hidden
/// - now < start                            -> countdown
/// - attempted                              -> rejoin else ready
ExamCardState resolveExamCardState({
  required ExamSet set,
  required DateTime now,
  required bool hasAttempted,
  required bool isPurchased,
  required bool hasPendingPurchase,
}) {
  if (set.isPro && !isPurchased) {
    return hasPendingPurchase ? ExamCardState.pending : ExamCardState.locked;
  }
  final start = set.startTime;
  if (start == null) return hasAttempted ? ExamCardState.rejoin : ExamCardState.ready;
  if (now.isBefore(start.subtract(cardRevealLead))) return ExamCardState.hidden;
  if (now.isBefore(start)) return ExamCardState.countdown;
  return hasAttempted ? ExamCardState.rejoin : ExamCardState.ready;
}

/// Exam sections (tabs) — mirrors examHub.fetchExamSections: filters by
/// courseIds/subcourseIds when present, always sorted by `order`.
class ExamSection {
  final String id;
  final String nameEn;
  final String nameNe;
  final String description;
  final String kind; // 'mcq' | 'theory' | 'mixed'
  final int colorValue; // ARGB, parsed from the doc's hex color string
  final int order;
  final List<String> courseIds;
  final List<String> subcourseIds;

  ExamSection({
    required this.id,
    required this.nameEn,
    required this.nameNe,
    required this.description,
    required this.kind,
    required this.colorValue,
    required this.order,
    required this.courseIds,
    required this.subcourseIds,
  });

  /// Display name in the current app language (React: language === 'ne' ? nameNe : nameEn).
  String displayName(bool nepali) =>
      nepali && nameNe.isNotEmpty ? nameNe : nameEn;

  factory ExamSection.fromMap(Map<String, dynamic> doc) {
    final fields = doc['_fields'] as Map<String, dynamic>? ?? doc;
    List<String> ids(dynamic v) => v is List
        ? v.map((e) => e.toString()).toList()
        : <String>[];
    int ord = 0;
    final raw = fields['order'];
    if (raw is num) ord = raw.toInt();
    final rawKind = (fields['kind'] ?? 'mcq').toString();
    final kind =
        rawKind == 'theory' || rawKind == 'mixed' ? rawKind : 'mcq';
    int colorValue = 0xFF2563EB;
    final rawColor = (fields['color'] ?? '').toString();
    if (RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(rawColor)) {
      colorValue =
          int.parse('FF${rawColor.replaceFirst('#', '')}', radix: 16);
    }
    return ExamSection(
      id: (doc['id'] ?? fields['id'] ?? '').toString(),
      nameEn: (fields['nameEn'] ?? fields['name'] ?? '').toString(),
      nameNe: (fields['nameNe'] ?? '').toString(),
      description: (fields['description'] ?? '').toString(),
      kind: kind,
      colorValue: colorValue,
      order: ord,
      courseIds: ids(fields['courseIds']),
      subcourseIds: ids(fields['subcourseIds']),
    );
  }

  /// Matches React: doc applies when its scope list contains our id, or when
  /// it carries no scope list at all.
  bool inScope({String? courseId, String? subcourseId}) {
    if (courseId != null &&
        courseId.isNotEmpty &&
        courseIds.isNotEmpty &&
        !courseIds.contains(courseId)) {
      return false;
    }
    if (subcourseId != null &&
        subcourseId.isNotEmpty &&
        subcourseIds.isNotEmpty &&
        !subcourseIds.contains(subcourseId)) {
      return false;
    }
    return true;
  }
}

Future<List<ExamSection>> fetchExamSections({
  String? courseId,
  String? subcourseId,
}) async {
  final docs = await ExamRest.listDocs('app_exam_sections');
  final sections = docs
      .map(ExamSection.fromMap)
      .where((s) => s.inScope(courseId: courseId, subcourseId: subcourseId))
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return sections;
}

/// Exam provinces (chips) — mirrors examHub.fetchProvinces.
class ExamProvince {
  final String id;
  final String nameEn;
  final String nameNe;
  final int order;

  ExamProvince(
      {required this.id,
      required this.nameEn,
      required this.nameNe,
      required this.order});

  /// Display name in the current app language.
  String displayName(bool nepali) =>
      nepali && nameNe.isNotEmpty ? nameNe : nameEn;

  factory ExamProvince.fromMap(Map<String, dynamic> doc) {
    final fields = doc['_fields'] as Map<String, dynamic>? ?? doc;
    int ord = 0;
    final raw = fields['order'];
    if (raw is num) ord = raw.toInt();
    return ExamProvince(
      id: (doc['id'] ?? fields['id'] ?? '').toString(),
      nameEn: (fields['nameEn'] ?? fields['name'] ?? '').toString(),
      nameNe: (fields['nameNe'] ?? '').toString(),
      order: ord,
    );
  }
}

Future<List<ExamProvince>> fetchExamProvinces() async {
  final docs = await ExamRest.listDocs('app_exam_provinces');
  final provinces = docs.map(ExamProvince.fromMap).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return provinces;
}

/// Normalises legacy section/province aliases on read (React: examHub).
String normalizeExamSectionId(String raw) {
  switch (raw) {
    case 'mcq':
      return 'mcq-tests';
    case 'theory':
      return 'theory-desk';
    default:
      return raw;
  }
}

/// Fetches exam sets for a subcourse — mirrors examHub.fetchExamSets:
/// dual query (subcourseIds array-contains + legacy subcourseId ==), merged by
/// id, published-only, in-memory section/province narrowing, sorted by
/// startTime desc (nulls last).
/// Visibility predicate for an exam set — mirrors the in-memory filters in
/// examHub.fetchExamSets: published-only, section narrowing, and province
/// narrowing that is SKIPPED when [allProvinces] is selected ("All Board"
/// shows every province's sets).
bool examSetVisible(ExamSet s, {String? sectionId, String? provinceId}) {
  if (!s.isPublished) return false;
  if (sectionId != null &&
      sectionId.isNotEmpty &&
      s.sectionId != sectionId) {
    return false;
  }
  if (provinceId != null &&
      provinceId.isNotEmpty &&
      provinceId != allProvinces &&
      s.provinceId != provinceId) {
    return false;
  }
  return true;
}

Future<List<ExamSet>> fetchExamSets({
  String? subcourseId,
  String? sectionId,
  String? provinceId,
}) async {
  final merged = <String, Map<String, dynamic>>{};
  if (subcourseId != null && subcourseId.isNotEmpty) {
    final byList = await ExamRest.runQuery(
      'app_exam_sets',
      where: ExamRest.fieldFilter('subcourseIds', 'ARRAY_CONTAINS', subcourseId),
      limit: 500,
    );
    for (final d in byList) {
      merged[(d['id'] ?? '').toString()] = d;
    }
    final byLegacy = await ExamRest.runQuery(
      'app_exam_sets',
      where: ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
      limit: 500,
    );
    for (final d in byLegacy) {
      merged[(d['id'] ?? '').toString()] = d;
    }
  } else {
    final all = await ExamRest.listDocs('app_exam_sets');
    for (final d in all) {
      merged[(d['id'] ?? '').toString()] = d;
    }
  }
  final sets = merged.values
      .map(ExamSet.fromMap)
      .where((s) => examSetVisible(s,
          sectionId: sectionId, provinceId: provinceId))
      .toList()
    ..sort((a, b) {
      // startTime desc, nulls last (React order).
      if (a.startTime == null && b.startTime == null) return 0;
      if (a.startTime == null) return 1;
      if (b.startTime == null) return -1;
      return b.startTime!.compareTo(a.startTime!);
    });
  return sets;
}

Future<ExamSet?> fetchExamSet(String setId) async {
  final doc = await ExamRest.getDoc('app_exam_sets/$setId');
  return doc == null ? null : ExamSet.fromMap(doc);
}

/// Builds the doc-id fallback chain for exam rules
/// (React: examHub.fetchExamRules).
List<String> examRuleCandidateIds({
  String? subcourseId,
  String? provinceId,
  String? sectionId,
}) {
  final candidates = <String>[];
  if (subcourseId != null &&
      subcourseId.isNotEmpty &&
      provinceId != null &&
      provinceId.isNotEmpty &&
      sectionId != null &&
      sectionId.isNotEmpty) {
    candidates.add('${subcourseId}__${provinceId}__${sectionId}');
  }
  if (subcourseId != null &&
      subcourseId.isNotEmpty &&
      sectionId != null &&
      sectionId.isNotEmpty) {
    candidates.add('${subcourseId}__${sectionId}');
  }
  if (sectionId != null && sectionId.isNotEmpty) {
    candidates.add('default__${sectionId}');
  }
  candidates.add('default');
  return candidates;
}

/// Loads exam rules via the doc-ID fallback chain — mirrors
/// examHub.fetchExamRules. First existing candidate wins.
Future<List<ExamRule>> fetchExamRules({
  String? courseId,
  String? subcourseId,
  String? provinceId,
  String? sectionId,
}) async {
  for (final id in examRuleCandidateIds(
    subcourseId: subcourseId,
    provinceId: provinceId,
    sectionId: sectionId,
  )) {
    final doc = await ExamRest.getDoc('app_exam_rules/$id');
    if (doc != null) {
      final fields = doc['_fields'] as Map<String, dynamic>? ?? doc;
      final raw = fields['rules'];
      if (raw is List) {
        return raw
            .whereType<Map<String, dynamic>>()
            .map(ExamRule.fromMap)
            .toList();
      }
      return [ExamRule.fromMap(doc)];
    }
  }
  return const [];
}

/// Lists every exam attempt of a user across all sets (the whole
/// `users/{uid}/exam_attempts` subcollection, newest attempt first).
Future<List<ExamAttempt>> fetchAllExamAttempts(String uid) async {
  final docs = await ExamRest.listDocs('users/$uid/exam_attempts');
  final attempts = docs.map(ExamAttempt.fromMap).toList()
    ..sort((a, b) => b.attemptNumber.compareTo(a.attemptNumber));
  return attempts;
}

/// Mirrors fetchAttemptsForSet in services/examHub.ts: list the whole
/// subcollection (no query — avoids composite-index requirements), filter by
/// examSetId client-side, sort by attemptNumber like React.
Future<List<ExamAttempt>> fetchAttemptsForSet(
    String uid, String examSetId) async {
  final docs = await ExamRest.listDocs('users/$uid/exam_attempts');
  final attempts = docs
      .map(ExamAttempt.fromMap)
      .where((a) => a.examSetId == examSetId)
      .toList()
    ..sort((a, b) => a.attemptNumber.compareTo(b.attemptNumber));
  return attempts;
}

/// A student's written-answer submission (flat `app_exam_answers` collection,
/// ownership via the `uid` field). Mirrors examHub's ExamAnswer.
class ExamAnswer {
  final String id;
  final String uid;
  final String examSetId;
  final String status; // pending | reviewed | ...

  ExamAnswer({
    required this.id,
    required this.uid,
    required this.examSetId,
    required this.status,
  });

  factory ExamAnswer.fromMap(Map<String, dynamic> m) {
    final fields = m['_fields'] as Map<String, dynamic>? ?? m;
    return ExamAnswer(
      id: (m['id'] ?? fields['id'] ?? '').toString(),
      uid: (fields['uid'] ?? '').toString(),
      examSetId: (fields['examSetId'] ?? '').toString(),
      status: (fields['status'] ?? 'pending').toString(),
    );
  }
}

/// Mirrors fetchMyExamAnswersBySet (examAnswers.ts): the user's own answer
/// docs keyed by examSetId, so PDF cards can look up "did I already submit?"
/// in O(1).
Future<Map<String, ExamAnswer>> fetchMyExamAnswersBySet(String uid) async {
  final docs = await ExamRest.runQuery(
    'app_exam_answers',
    where: ExamRest.fieldFilter('uid', 'EQUAL', uid),
    limit: 200,
  );
  final bySet = <String, ExamAnswer>{};
  for (final d in docs) {
    final a = ExamAnswer.fromMap(d);
    if (a.examSetId.isNotEmpty) bySet[a.examSetId] = a;
  }
  return bySet;
}

/// Saves an attempt twice: private doc + public ranking row (best-effort).
Future<void> saveExamAttempt({
  required String uid,
  required ExamSet set,
  required ScoreBreakdown score,
  required List<int> answers,
  required int attemptNumber,
  required int timeTakenSeconds,
  required String name,
  String? photoURL,
  required bool isPro,
}) async {
  final now = DateTime.now().toUtc();
  await ExamRest.createDoc('users/$uid/exam_attempts', {
    'examSetId': set.id,
    'courseId': set.courseId,
    'subcourseId': set.subcourseId,
    'attemptNumber': attemptNumber,
    'score': score.percent,
    'totalQuestions': set.questions.length,
    'correct': score.correct,
    'incorrect': score.incorrect,
    'skipped': score.skipped,
    'passed': score.passed ? 1 : 0,
    'timeTakenSeconds': timeTakenSeconds,
    'answers': answers,
    'createdAt': now,
  });
  // Public ranking row — failures must not break the attempt save.
  try {
    await ExamRest.createDoc('app_exam_rankings', {
      'examSetId': set.id,
      'courseId': set.courseId,
      'subcourseId': set.subcourseId,
      'uid': uid,
      'name': name,
      'photoURL': photoURL,
      'isPro': isPro,
      'score': score.percent,
      'timeTakenSeconds': timeTakenSeconds,
      'createdAt': now,
    });
  } catch (_) {}
}

/// Best score per uid for a set — mirrors fetchExamRankings in
/// services/examHub.ts: filter on examSetId ONLY (a server-side orderBy on a
/// different field would require a composite index), keep each uid's best row
/// (higher score wins; ties broken by lower time), sort client-side.
Future<List<RankingRow>> fetchExamRanking(String examSetId) async {
  final docs = await ExamRest.runQuery(
    'app_exam_rankings',
    where: ExamRest.fieldFilter('examSetId', 'EQUAL', examSetId),
    limit: 300,
  );
  final bestByUid = <String, RankingRow>{};
  for (final d in docs) {
    final row = RankingRow.fromMap(d);
    if (row.uid.isEmpty) continue;
    final existing = bestByUid[row.uid];
    final better = existing == null ||
        row.score > existing.score ||
        (row.score == existing.score &&
            row.timeTakenSeconds < existing.timeTakenSeconds);
    if (better) bestByUid[row.uid] = row;
  }
  final rows = bestByUid.values.toList()
    ..sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return a.timeTakenSeconds.compareTo(b.timeTakenSeconds);
    });
  return rows;
}

// ---------------------------------------------------------------------------
// Mock tests / live exams (mockTests / liveExams / questions / users/{uid}/attempts)
// ---------------------------------------------------------------------------

class MockQuestion {
  final String id;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  MockQuestion({
    required this.id,
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory MockQuestion.fromMap(Map<String, dynamic> m) => MockQuestion(
        id: _str(m['id']),
        text: _str(m['text']),
        options: (m['options'] as List?)?.map((e) => '$e').toList() ?? [],
        correctIndex: _num(m['correctIndex']),
        explanation: _str(m['explanation']),
      );
}

class ExamDefinition {
  final String id;
  final String title;
  final List<String> questionIds;
  final int durationMinutes;
  final String markingScheme;
  final DateTime? scheduledStart;

  ExamDefinition({
    required this.id,
    required this.title,
    required this.questionIds,
    required this.durationMinutes,
    required this.markingScheme,
    required this.scheduledStart,
  });

  factory ExamDefinition.fromMap(Map<String, dynamic> m) => ExamDefinition(
        id: _str(m['id']),
        title: _str(m['title']),
        questionIds: _strList(m['questionIds']),
        durationMinutes: _num(m['durationMinutes'], 60),
        markingScheme: _str(m['markingScheme']),
        scheduledStart: _dt(m['scheduledStart']),
      );
}

class AttemptAnswer {
  final String questionId;
  final int? selectedIndex;
  final bool flagged;

  AttemptAnswer({
    required this.questionId,
    required this.selectedIndex,
    required this.flagged,
  });
}

class AttemptResult {
  final String id;
  final String examId;
  final String examTitle;
  final List<AttemptAnswer> answers;
  final double score;
  final int totalMarks;
  final int correctCount;
  final int incorrectCount;
  final int unattemptedCount;
  final int timeTakenSeconds;
  final DateTime? submittedAt;

  AttemptResult({
    required this.id,
    required this.examId,
    required this.examTitle,
    required this.answers,
    required this.score,
    required this.totalMarks,
    required this.correctCount,
    required this.incorrectCount,
    required this.unattemptedCount,
    required this.timeTakenSeconds,
    required this.submittedAt,
  });

  factory AttemptResult.fromMap(Map<String, dynamic> m) => AttemptResult(
        id: _str(m['id']),
        examId: _str(m['examId']),
        examTitle: _str(m['examTitle']),
        answers: ((m['answers'] as List?) ?? []).map((a) {
          final am = (a as Map).cast<String, dynamic>();
          return AttemptAnswer(
            questionId: _str(am['questionId']),
            selectedIndex:
                am['selectedIndex'] == null ? null : _num(am['selectedIndex']),
            flagged: _bool(am['flagged']),
          );
        }).toList(),
        score: _dbl(m['score']),
        totalMarks: _num(m['totalMarks']),
        correctCount: _num(m['correctCount']),
        incorrectCount: _num(m['incorrectCount']),
        unattemptedCount: _num(m['unattemptedCount']),
        timeTakenSeconds: _num(m['timeTakenSeconds']),
        submittedAt: _dt(m['submittedAt']),
      );
}

class MockScore {
  final double score;
  final int totalMarks;
  final int correctCount;
  final int incorrectCount;
  final int unattemptedCount;

  MockScore({
    required this.score,
    required this.totalMarks,
    required this.correctCount,
    required this.incorrectCount,
    required this.unattemptedCount,
  });
}

/// Mirrors scoreAttempt() in services/exams.ts.
MockScore scoreMockAttempt(
    List<MockQuestion> questions, List<AttemptAnswer> answers) {
  var correctCount = 0;
  var incorrectCount = 0;
  var unattemptedCount = 0;
  for (final q in questions) {
    AttemptAnswer? answer;
    for (final a in answers) {
      if (a.questionId == q.id) {
        answer = a;
        break;
      }
    }
    if (answer == null || answer.selectedIndex == null) {
      unattemptedCount += 1;
    } else if (answer.selectedIndex == q.correctIndex) {
      correctCount += 1;
    } else {
      incorrectCount += 1;
    }
  }
  final raw = correctCount - incorrectCount * 0.25;
  final score = (raw < 0 ? 0.0 : (raw * 100).round() / 100);
  return MockScore(
    score: score,
    totalMarks: questions.length,
    correctCount: correctCount,
    incorrectCount: incorrectCount,
    unattemptedCount: unattemptedCount,
  );
}

Future<ExamDefinition?> fetchMockTest(String id) async {
  final doc = await ExamRest.getDoc('mockTests/$id');
  return doc == null ? null : ExamDefinition.fromMap(doc);
}

Future<ExamDefinition?> fetchLiveExam(String id) async {
  final doc = await ExamRest.getDoc('liveExams/$id');
  return doc == null ? null : ExamDefinition.fromMap(doc);
}

Future<List<MockQuestion>> fetchQuestionsByIds(List<String> ids) async {
  final results = <MockQuestion>[];
  for (final id in ids) {
    final doc = await ExamRest.getDoc('questions/$id');
    if (doc != null) results.add(MockQuestion.fromMap(doc));
  }
  return results;
}

/// Submits a mock/live attempt and returns the attempt doc ID.
Future<String> submitAttempt({
  required String uid,
  required String examId,
  required String examTitle,
  required List<MockQuestion> questions,
  required List<AttemptAnswer> answers,
  required int timeTakenSeconds,
}) async {
  final s = scoreMockAttempt(questions, answers);
  return ExamRest.createDoc('users/$uid/attempts', {
    'examId': examId,
    'examTitle': examTitle,
    'answers': answers
        .map((a) => {
              'questionId': a.questionId,
              'selectedIndex': a.selectedIndex,
              'flagged': a.flagged,
            })
        .toList(),
    'score': s.score,
    'totalMarks': s.totalMarks,
    'correctCount': s.correctCount,
    'incorrectCount': s.incorrectCount,
    'unattemptedCount': s.unattemptedCount,
    'timeTakenSeconds': timeTakenSeconds,
    'submittedAt': DateTime.now().toUtc(),
  });
}

Future<AttemptResult?> fetchAttemptResult(String uid, String attemptId) async {
  final doc = await ExamRest.getDoc('users/$uid/attempts/$attemptId');
  return doc == null ? null : AttemptResult.fromMap(doc);
}

Future<List<AttemptResult>> fetchAttemptHistory(String uid,
    {int max = 50}) async {
  final docs = await ExamRest.runQuery(
    'attempts',
    parent: 'users/$uid',
    orderBy: [ExamRest.orderField('submittedAt', 'DESCENDING')],
    limit: max,
  );
  return docs.map(AttemptResult.fromMap).toList();
}

// ---------------------------------------------------------------------------
// Daily tests (app_daily_test_models / users/{uid}/daily_test_results)
// ---------------------------------------------------------------------------

class DailyTestQuestion {
  final String category;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int timeSeconds;
  final double marks;

  DailyTestQuestion({
    required this.category,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.timeSeconds,
    required this.marks,
  });

  factory DailyTestQuestion.fromMap(Map<String, dynamic> m) =>
      DailyTestQuestion(
        category: _str(m['category'], 'Medium'),
        question: _str(m['question']),
        options: (m['options'] as List?)?.map((e) => '$e').toList() ?? [],
        correctIndex: _num(m['correctIndex']),
        explanation: _str(m['explanation']),
        timeSeconds: _num(m['timeSeconds']),
        marks: _dbl(m['marks']),
      );
}

class DailyTestModel {
  final String id;
  final String name;
  final String modelName;
  final String courseId;
  final String subcourseId;
  final String testDate; // YYYY-MM-DD
  final List<DailyTestQuestion> questions;
  final String category;
  final int perQuestionTimeSeconds;
  final bool negativeMarking;
  final double negativeMarkPercent;
  final double marksPerQuestion;
  final int passPercent;
  final List<String> rules;
  final bool isPro;
  final String subscriptionType; // 'on' | 'off'
  final double price;
  final bool active;
  final int order;

  DailyTestModel({
    required this.id,
    required this.name,
    required this.modelName,
    required this.courseId,
    required this.subcourseId,
    required this.testDate,
    required this.questions,
    required this.category,
    required this.perQuestionTimeSeconds,
    required this.negativeMarking,
    required this.negativeMarkPercent,
    required this.marksPerQuestion,
    required this.passPercent,
    required this.rules,
    required this.isPro,
    required this.subscriptionType,
    required this.price,
    required this.active,
    required this.order,
  });

  factory DailyTestModel.fromMap(Map<String, dynamic> m) => DailyTestModel(
        id: _str(m['id']),
        name: _str(m['name']),
        modelName: _str(m['modelName'], _str(m['name'])),
        courseId: _str(m['courseId']),
        subcourseId: _str(m['subcourseId']),
        // Release date: explicit testDate, else older `scheduledFor`, else the
        // creation day — mirrors dateKeyFromRaw() in services/dailyTest.ts.
        testDate: _dailyTestDateKey(m),
        questions: ((m['questions'] as List?) ?? [])
            .whereType<Map>()
            .map((q) =>
                DailyTestQuestion.fromMap(q.map((k, v) => MapEntry('$k', v))))
            .toList(),
        category: _str(m['category'], 'medium'),
        perQuestionTimeSeconds: _num(m['perQuestionTimeSeconds'], 30),
        negativeMarking: _bool(m['negativeMarking']),
        negativeMarkPercent: _dbl(m['negativeMarkPercent'], 0.2),
        marksPerQuestion: _dbl(m['marksPerQuestion'], 1),
        passPercent: _num(m['passPercent'], 40),
        rules: _strList(m['rules']),
        isPro: _bool(m['isPro']),
        subscriptionType: _str(m['subscriptionType'], 'off'),
        price: _dbl(m['price']),
        active: _bool(m['active'], true),
        order: _num(m['order']),
      );

  /// React parity: `model.modelName || model.name` — modelName wins.
  String get displayName => modelName.isNotEmpty ? modelName : name;
}

class DailyTestResult {
  final String id;
  final String modelId;
  final String modelName;
  final String courseId;
  final String subcourseId;
  final int score; // percent
  final int totalQuestions;
  final int correct;
  final int incorrect;
  final int skipped;
  final int timeTakenSeconds;
  final List<int> answers; // -1 = skipped
  final DateTime? createdAt;

  DailyTestResult({
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.courseId,
    required this.subcourseId,
    required this.score,
    required this.totalQuestions,
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.timeTakenSeconds,
    required this.answers,
    required this.createdAt,
  });

  factory DailyTestResult.fromMap(Map<String, dynamic> m) => DailyTestResult(
        id: _str(m['id']),
        modelId: _str(m['modelId']),
        modelName: _str(m['modelName']),
        courseId: _str(m['courseId']),
        subcourseId: _str(m['subcourseId']),
        score: _num(m['score']),
        totalQuestions: _num(m['totalQuestions']),
        correct: _num(m['correct']),
        incorrect: _num(m['incorrect']),
        skipped: _num(m['skipped']),
        timeTakenSeconds: _num(m['timeTakenSeconds']),
        answers:
            ((m['answers'] as List?) ?? []).map((a) => _num(a, -1)).toList(),
        createdAt: _dt(m['createdAt']),
      );
}

class DailyScore {
  final int correct;
  final int incorrect;
  final int skipped;
  final double marksEarned;
  final double marksLost;
  final double netMarks;
  final double totalMarks;
  final int percent;
  final int accuracy;
  final bool passed;

  DailyScore({
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.marksEarned,
    required this.marksLost,
    required this.netMarks,
    required this.totalMarks,
    required this.percent,
    required this.accuracy,
    required this.passed,
  });
}

/// Mirrors scoreDailyTest() in services/dailyTest.ts — exact algorithm:
/// perQuestion = marksPerQuestion (>0 else 1);
/// penaltyRate = negativeMarking ? max(0, negativeMarkPercent || 0.2) : 0;
/// marksLost = round(incorrect * perQuestion * penaltyRate * 100) / 100;
/// netMarks = max(0, round((earned - lost) * 100) / 100);
/// percent = round(netMarks / totalMarks * 100); accuracy = round(correct / Q * 100);
/// passed = percent >= (passPercent || 40).
DailyScore scoreDailyTest(DailyTestModel model,
    List<DailyTestQuestion> questions, List<int?> answers) {
  var correct = 0;
  var incorrect = 0;
  var skipped = 0;
  for (var i = 0; i < questions.length; i++) {
    final chosen = i < answers.length ? answers[i] : null;
    if (chosen == null || chosen < 0) {
      skipped += 1;
    } else if (chosen == questions[i].correctIndex) {
      correct += 1;
    } else {
      incorrect += 1;
    }
  }
  final perQuestion = model.marksPerQuestion > 0 ? model.marksPerQuestion : 1.0;
  final penaltyRate = model.negativeMarking
      ? ((model.negativeMarkPercent > 0 ? model.negativeMarkPercent : 0.2)
          .clamp(0.0, double.infinity))
      : 0.0;
  final marksEarned = correct * perQuestion;
  final marksLost =
      ((incorrect * perQuestion * penaltyRate * 100).round()) / 100;
  final netMarks = (((marksEarned - marksLost) * 100).round() / 100)
      .clamp(0.0, double.infinity);
  final totalMarks = questions.length * perQuestion;
  final percent = totalMarks > 0 ? ((netMarks / totalMarks) * 100).round() : 0;
  final accuracy =
      questions.isNotEmpty ? ((correct / questions.length) * 100).round() : 0;
  final passPercent = model.passPercent > 0 ? model.passPercent : 40;
  return DailyScore(
    correct: correct,
    incorrect: incorrect,
    skipped: skipped,
    marksEarned: marksEarned,
    marksLost: marksLost,
    netMarks: netMarks,
    totalMarks: totalMarks,
    percent: percent,
    accuracy: accuracy,
    passed: percent >= passPercent,
  );
}

/// Kathmandu date key YYYY-MM-DD (NPT = UTC+5:45).
/// Uses the server-corrected clock so winding the device clock cannot unlock
/// future tests — mirrors todayDateKey()/serverNow() in dailyTest.ts.
String todayDateKey() {
  final kathmandu =
      ServerClock.nowUtc().add(const Duration(hours: 5, minutes: 45));
  return '${kathmandu.year.toString().padLeft(4, '0')}-'
      '${kathmandu.month.toString().padLeft(2, '0')}-'
      '${kathmandu.day.toString().padLeft(2, '0')}';
}

Future<List<DailyTestModel>> fetchDailyTestModels(String subcourseId) async {
  final docs = await ExamRest.runQuery(
    'app_daily_test_models',
    where: ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
    limit: 100,
  );
  // Same as React: active filtered client-side (single-field index is enough),
  // models without questions never shown, sorted by release date then order.
  return docs
      .map(DailyTestModel.fromMap)
      .where((m) => m.active && m.questions.isNotEmpty)
      .toList()
    ..sort((a, b) => a.testDate == b.testDate
        ? a.order.compareTo(b.order)
        : a.testDate.compareTo(b.testDate));
}

Future<DailyTestModel?> fetchDailyTestModel(String modelId) async {
  final doc = await ExamRest.getDoc('app_daily_test_models/$modelId');
  return doc == null ? null : DailyTestModel.fromMap(doc);
}

/// Existing result for a model (re-attempt guard). Null if never attempted.
Future<DailyTestResult?> fetchDailyTestResultForModel(
    String uid, String modelId) async {
  final docs = await ExamRest.runQuery(
    'daily_test_results',
    parent: 'users/$uid',
    where: ExamRest.fieldFilter('modelId', 'EQUAL', modelId),
    limit: 1,
  );
  return docs.isEmpty ? null : DailyTestResult.fromMap(docs.first);
}

Future<List<DailyTestResult>> fetchDailyTestResults(String uid) async {
  final docs = await ExamRest.runQuery(
    'daily_test_results',
    parent: 'users/$uid',
    orderBy: [ExamRest.orderField('createdAt', 'DESCENDING')],
    limit: 50,
  );
  return docs.map(DailyTestResult.fromMap).toList();
}

/// Saves a daily-test attempt. Returns the new result document's ID (React
/// parity: saveDailyTestResult resolves the id). `createdAt` is a real
/// Firestore server timestamp, never the device clock.
Future<String> saveDailyTestResult({
  required String uid,
  required DailyTestModel model,
  required DailyScore score,
  required List<int> answers,
  required int timeTakenSeconds,
}) async {
  final id = await ExamRest.createDoc(
    'users/$uid/daily_test_results',
    {
      'modelId': model.id,
      'modelName': model.displayName,
      'courseId': model.courseId,
      'subcourseId': model.subcourseId,
      'score': score.percent,
      'totalQuestions': model.questions.length,
      'correct': score.correct,
      'incorrect': score.incorrect,
      'skipped': score.skipped,
      'timeTakenSeconds': timeTakenSeconds,
      'answers': answers,
    },
    serverTimestampFields: const ['createdAt'],
  );
  return id;
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// In-memory catalogue cache — mirrors cachedOrInFlight in the React services
// (subjectDetails.ts, subjectChapterDetails.ts, subjectUnitDetails.ts):
// 3-minute TTL plus in-flight dedupe so concurrent callers share a single
// Firestore request. Only catalogue data is cached (never per-user progress).
// ---------------------------------------------------------------------------
const _catalogStaleMs = 3 * 60 * 1000;

class _CatalogCacheEntry {
  final List<Map<String, dynamic>> result;
  final int cachedAt;
  _CatalogCacheEntry(this.result, this.cachedAt);
}

final Map<String, _CatalogCacheEntry> _catalogCache = {};
final Map<String, Future<List<Map<String, dynamic>>>> _catalogInFlight = {};

Future<List<Map<String, dynamic>>> _cachedOrInFlight(
  String key,
  Future<List<Map<String, dynamic>>> Function() loader,
) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final entry = _catalogCache[key];
  if (entry != null && now - entry.cachedAt <= _catalogStaleMs) {
    return Future.value(entry.result);
  }
  final existing = _catalogInFlight[key];
  if (existing != null) return existing;
  final request = loader().then((result) {
    _catalogCache[key] =
        _CatalogCacheEntry(result, DateTime.now().millisecondsSinceEpoch);
    return result;
  }).whenComplete(() {
    _catalogInFlight.remove(key);
  });
  _catalogInFlight[key] = request;
  return request;
}

// Learning progress stats — mirrors fetchSubjectLearningStats() in
// learningProgress.ts: counts progress docs (one per subject+chapter) as
// complete when percentage >= 100 (or completed with no remaining questions),
// in-progress when percentage > 0. The denominator refresh from the live
// practice question set is skipped — the persisted totalQuestions is used.
// ---------------------------------------------------------------------------

/// Logical id: last `__` segment, lowercased, non-alphanumerics -> dashes
/// (normalizeLogicalId in the React learningProgress.ts — the catalog slug
/// is the last segment of composite Firestore document IDs).
String _canonicalLearningId(String v) {
  final parts = v.split('__').where((p) => p.isNotEmpty).toList();
  final last = parts.isNotEmpty ? parts.last : v;
  return last
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class SubjectLearningStats {
  final int complete;
  final int inProgress;

  const SubjectLearningStats(
      {required this.complete, required this.inProgress});
}

Future<SubjectLearningStats> fetchSubjectLearningStats({
  required String uid,
  required String courseId,
  required String subcourseId,
  required List<String> subjectIds,
}) async {
  final ids = subjectIds
      .map(_canonicalLearningId)
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  if (ids.isEmpty)
    return const SubjectLearningStats(complete: 0, inProgress: 0);
  final docs = await ExamRest.runQuery(
    'learning_progress',
    parent: 'users/$uid',
    where: ExamRest.fieldFilter('subjectId', 'IN', ids),
    limit: 200,
  );
  // React refreshes every denominator concurrently (Promise.all) — a
  // sequential await per document is what made the subject page take minutes.
  final refreshed = await Future.wait(docs.map((d) async {
    final attempted =
        ((d['attemptedQuestionIds'] as List?) ?? []).whereType<String>().length;
    final total = _num(d['totalQuestions']);
    final done = _bool(d['completed']);
    // Refresh the denominator from the current practice question-set doc for
    // chapters that already have progress (question banks grow over time).
    var currentTotal = total;
    try {
      final qs = await fetchPracticeQuestionSet(
        courseId: courseId,
        subcourseId: subcourseId,
        subjectId: '${d['subjectId'] ?? ''}',
        unitId: d['unitId'] as String?,
        chapterId: '${d['chapterId'] ?? ''}',
      );
      if (qs.isNotEmpty) currentTotal = qs.length;
    } catch (_) {}
    return (attempted: attempted, done: done, currentTotal: currentTotal);
  }));
  var complete = 0;
  var inProgress = 0;
  for (final r in refreshed) {
    final pct = r.currentTotal > 0
        ? ((r.attempted / r.currentTotal * 100).round().clamp(0, 100))
        : (r.done ? 100 : 0);
    if (pct >= 100 || (r.done && r.currentTotal <= r.attempted)) {
      complete++;
    } else if (pct > 0) {
      inProgress++;
    }
  }
  return SubjectLearningStats(complete: complete, inProgress: inProgress);
}

// ---------------------------------------------------------------------------
// Subject pages — exact ports of subjectDetails.ts, subjectChapterDetails.ts,
// subjectUnitDetails.ts, learningProgress.ts and learningContent.ts.
// ---------------------------------------------------------------------------

/// Seed slugs for the deterministic subject catalogue
/// (subjectDetails.ts SUBJECT_SEED). Doc ids: `{course}__{subcourse}__{slug}`.
const List<String> subjectSeedSlugs = [
  'general-awareness',
  'public-management',
  'technical-subject',
];

/// Last `__` segment, lowercased, non-alphanumerics -> dashes
/// (normalizeCatalogId / canonicalCatalogId in the React services).
String canonicalCatalogSlug(String v) {
  final parts = v.split('__').where((p) => p.isNotEmpty).toList();
  final last = parts.isNotEmpty ? parts.last : v;
  return last
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Canonical app subject slug: catalogue slug + the job-based-knowledge alias.
String appSubjectSlug(String v) {
  final slug = canonicalCatalogSlug(v);
  return slug == 'job-based-knowledge' ? 'technical-subject' : slug;
}

/// Deterministic direct reads — never scans the collection (subjectDetails.ts).
/// The 3 seed reads run concurrently and the scope is cached for 3 minutes,
/// mirroring React's cachedOrInFlight.
Future<List<Map<String, dynamic>>> fetchSubjectDetails(
    String courseId, String subcourseId) {
  return _cachedOrInFlight('${courseId}__${subcourseId}', () async {
    final docs = await Future.wait(subjectSeedSlugs.map((slug) =>
        ExamRest.getDoc(
            'app_subjects_details/${courseId}__${subcourseId}__$slug')));
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      if (doc == null) continue;
      final slug = subjectSeedSlugs[i];
      out.add({...doc, 'id': '${courseId}__${subcourseId}__$slug'});
    }
    out.sort((a, b) => (_num(a['order'], 0)).compareTo(_num(b['order'], 0)));
    return out;
  });
}

Map<String, dynamic> _subjectChapterFromDoc(Map<String, dynamic> doc) {
  final unitRaw = doc['unitId'];
  final unitId =
      unitRaw is String && unitRaw.trim().isNotEmpty ? doc['unitId'] : null;
  return {
    'id': '${doc['id'] ?? ''}',
    'name':
        (doc['name'] as String?)?.isNotEmpty == true ? doc['name'] : 'Chapter',
    'nameNe': doc['nameNe'] ?? doc['name'] ?? 'Chapter',
    'order': _num(doc['order'], 0),
    'course': doc['course'] ?? '',
    'subcourse': doc['subcourse'] ?? '',
    'subjectId': doc['subjectId'] ?? '',
    'unitId': unitId,
    'unit': doc['unit'] ?? '',
    'unitNameNe': doc['unitNameNe'] ?? doc['unit'] ?? '',
    'pro': _bool(doc['pro']),
    'price': _num(doc['price'], 0),
    'isPublished': doc['isPublished'] != false,
  };
}

/// Direct (unit-less) chapters: runQuery where course==, client filters
/// (subjectChapterDetails.ts loadDirectChapters). Cached 3 minutes per scope,
/// mirroring React's cachedOrInFlight.
Future<List<Map<String, dynamic>>> fetchSubjectChapters(
    String course, String subcourse, String subjectId) {
  final logical = canonicalCatalogSlug(subjectId);
  return _cachedOrInFlight('${course}__${subcourse}__$logical', () async {
    final docs = await ExamRest.runQuery(
      'app_subjects_chapter_details',
      where: ExamRest.fieldFilter('course', 'EQUAL', course),
      limit: 300,
    );
    final out = docs
        .where((d) =>
            '${d['subcourse'] ?? ''}' == subcourse &&
            canonicalCatalogSlug('${d['subjectId'] ?? ''}') == logical &&
            _bool(d['isPublished']) == true &&
            !(d['unitId'] is String &&
                (d['unitId'] as String).trim().isNotEmpty))
        .map(_subjectChapterFromDoc)
        .toList();
    out.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return out;
  });
}

/// Direct chapters with per-user learning progress attached
/// (subjectChapterDetails.ts fetchSubjectChaptersWithProgress).
/// Progress doc read: users/{uid}/learning_progress/{logicalSlug}__{chapterId}.
/// Progress reads run concurrently (React: Promise.all). The cached chapter
/// maps are never mutated — progress is attached on copies, like React's
/// withProgress spread.
Future<List<Map<String, dynamic>>> fetchSubjectChaptersWithProgress(
    String course, String subcourse, String subjectId, String? uid) async {
  final logical = _canonicalLearningId(subjectId);
  final chapters = await fetchSubjectChapters(course, subcourse, logical);
  Future<Map<String, dynamic>> withProgress(Map<String, dynamic> c) async {
    Map<String, dynamic>? p;
    if (uid != null && uid.isNotEmpty) {
      try {
        p = await fetchLearningProgress(uid, logical, '${c['id']}');
      } catch (_) {}
    }
    final total = (p?['totalQuestions'] as int?) ?? 0;
    final attempted = (p?['attempted'] as int?) ?? 0;
    final correct =
        ((p?['correctQuestionIds'] as List?) ?? []).whereType<String>().length;
    final completed = _bool(p?['completed']);
    final pct = total > 0
        ? ((attempted / total * 100).round().clamp(0, 100))
        : (completed ? 100 : 0);
    return {
      ...c,
      'progress': {
        'chapterId': '${c['id']}',
        'attempted': attempted,
        'correct': correct,
        'totalQuestions': total,
        'percentage': pct,
        'completed': completed || pct >= 100,
      },
    };
  }

  return Future.wait(chapters.map(withProgress));
}

/// Units for a subject (subjectUnitDetails.ts). Cached 3 minutes per scope,
/// mirroring React's cachedOrInFlight.
Future<List<Map<String, dynamic>>> fetchSubjectUnits(
    String course, String subcourse, String subjectId) {
  final logical = canonicalCatalogSlug(subjectId);
  return _cachedOrInFlight('${course}__${subcourse}__$logical', () async {
    final docs = await ExamRest.runQuery(
      'app_subjects_units_details',
      where: ExamRest.fieldFilter('course', 'EQUAL', course),
      limit: 300,
    );
    final out = docs
        .where((d) =>
            '${d['subcourse'] ?? ''}' == subcourse &&
            canonicalCatalogSlug('${d['subjectId'] ?? ''}') == logical &&
            _bool(d['isPublished']) == true)
        .map((d) => {
              'id': '${d['id'] ?? ''}',
              'name': (d['name'] as String?)?.isNotEmpty == true
                  ? d['name']
                  : 'Unit',
              'nameNe': d['nameNe'] ?? d['name'] ?? 'Unit',
              'order': _num(d['order'], 0),
              'course': d['course'] ?? '',
              'subcourse': d['subcourse'] ?? '',
              'subjectId': d['subjectId'] ?? '',
              'pro': _bool(d['pro']),
              'price': _num(d['price'], 0),
            })
        .toList();
    out.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return out;
  });
}

/// Unit-chapters for one unit (subjectUnitDetails.ts loadUnitChapters).
/// Cached 3 minutes per unit, mirroring React's cachedOrInFlight.
Future<List<Map<String, dynamic>>> fetchUnitChapters(
    String course, String subcourse, String subjectId, String unitId) {
  final logical = canonicalCatalogSlug(subjectId);
  final targetUnit = canonicalCatalogSlug(unitId);
  return _cachedOrInFlight('${course}__${subcourse}__${logical}__$targetUnit',
      () async {
    final docs = await ExamRest.runQuery(
      'app_subjects_unit-chapters_details',
      where: ExamRest.fieldFilter('course', 'EQUAL', course),
      limit: 300,
    );
    final out = docs
        .where((d) =>
            '${d['subcourse'] ?? ''}' == subcourse &&
            canonicalCatalogSlug('${d['subjectId'] ?? ''}') == logical &&
            canonicalCatalogSlug('${d['unitId'] ?? ''}') == targetUnit &&
            _bool(d['isPublished']) == true)
        .map(_subjectChapterFromDoc)
        .toList();
    out.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return out;
  });
}

/// Units with their unit-chapters and per-user learning progress attached
/// (subjectUnitDetails.ts fetchSubjectUnitsWithChapters).
/// Every unit's chapter lookup and every chapter's progress read runs
/// concurrently (React: nested Promise.all) — the sequential awaits here were
/// the main reason the units page took minutes. Cached maps are never mutated.
Future<List<Map<String, dynamic>>> fetchSubjectUnitsWithChapters(
    String course, String subcourse, String subjectId, String? uid) async {
  final logical = _canonicalLearningId(subjectId);
  final units = await fetchSubjectUnits(course, subcourse, logical);
  Future<Map<String, dynamic>> withChapters(Map<String, dynamic> u) async {
    List<Map<String, dynamic>> chapters = [];
    try {
      chapters =
          await fetchUnitChapters(course, subcourse, logical, '${u['id']}');
    } catch (_) {
      // Keep the unit visible even if its chapter lookup is unavailable.
    }
    final withP = await Future.wait(chapters.map((c) async {
      Map<String, dynamic>? p;
      if (uid != null && uid.isNotEmpty) {
        try {
          p = await fetchLearningProgress(uid, logical, '${c['id']}');
        } catch (_) {}
      }
      final total = (p?['totalQuestions'] as int?) ?? 0;
      final attempted = (p?['attempted'] as int?) ?? 0;
      final correct = ((p?['correctQuestionIds'] as List?) ?? [])
          .whereType<String>()
          .length;
      final completed = _bool(p?['completed']);
      final pct = total > 0
          ? ((attempted / total * 100).round().clamp(0, 100))
          : (completed ? 100 : 0);
      return {
        ...c,
        'progress': {
          'chapterId': '${c['id']}',
          'attempted': attempted,
          'correct': correct,
          'totalQuestions': total,
          'percentage': pct,
          // Units layer: completed is the persisted flag only (no pct>=100).
          'completed': completed,
        },
      };
    }));
    return {...u, 'chapters': withP};
  }

  return Future.wait(units.map(withChapters));
}

/// Per-chapter learning progress doc:
/// `users/{uid}/learning_progress/{subjectSlug}__{chapterSlug}`
/// (learningProgress.ts progressId).
String learningProgressDocId(String subjectId, String chapterId) =>
    '${_canonicalLearningId(subjectId)}__${_canonicalLearningId(chapterId)}';

Future<Map<String, dynamic>?> fetchLearningProgress(
    String uid, String subjectId, String chapterId) async {
  final doc = await ExamRest.getDoc(
      'users/$uid/learning_progress/${learningProgressDocId(subjectId, chapterId)}');
  if (doc == null) return null;
  final attempted =
      ((doc['attemptedQuestionIds'] as List?) ?? []).whereType<String>().length;
  final total = _num(doc['totalQuestions'], 0);
  final completed = _bool(doc['completed']);
  final percentage = total > 0
      ? ((attempted / total * 100).round().clamp(0, 100))
      : (completed ? 100 : 0);
  return {
    ...doc,
    'attempted': attempted,
    'percentage': percentage,
  };
}

/// Merge write to the learning progress doc (learningProgress.ts
/// saveLearningProgress — setDocument with merge).
Future<void> saveLearningProgress(
  String uid, {
  required String subjectId,
  String? unitId,
  required String chapterId,
  String? courseId,
  String? subcourseId,
  List<String>? attemptedQuestionIds,
  List<String>? correctQuestionIds,
  Map<String, int>? selectedAnswerIndexes,
  int? totalQuestions,
  bool? bookmarked,
  bool? completed,
  String? lastMode,
  String? dailyDate,
  List<String>? dailyQuestionIds,
  List<String>? dailyAttemptedQuestionIds,
  List<String>? dailyCorrectQuestionIds,
}) async {
  final data = <String, dynamic>{
    'subjectId': _canonicalLearningId(subjectId),
    'unitId': unitId == null ? null : _canonicalLearningId(unitId),
    'chapterId': _canonicalLearningId(chapterId),
    if (courseId != null && courseId.isNotEmpty) 'courseId': courseId,
    if (subcourseId != null && subcourseId.isNotEmpty)
      'subcourseId': subcourseId,
    'attemptedQuestionIds': attemptedQuestionIds ?? <String>[],
    'correctQuestionIds': correctQuestionIds ?? <String>[],
    if (selectedAnswerIndexes != null)
      'selectedAnswerIndexes': selectedAnswerIndexes,
    if (totalQuestions != null) 'totalQuestions': totalQuestions,
    'bookmarked': bookmarked ?? false,
    'completed': completed ?? false,
    'lastMode': lastMode ?? 'practice',
    if (dailyDate != null) 'dailyDate': dailyDate,
    if (dailyQuestionIds != null) 'dailyQuestionIds': dailyQuestionIds,
    if (dailyAttemptedQuestionIds != null)
      'dailyAttemptedQuestionIds': dailyAttemptedQuestionIds,
    if (dailyCorrectQuestionIds != null)
      'dailyCorrectQuestionIds': dailyCorrectQuestionIds,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  await ExamRest.setDoc(
      'users/$uid/learning_progress/${learningProgressDocId(subjectId, chapterId)}',
      data);
}

/// Activity progress record (activityProgress.ts recordActivityProgress —
/// used by read/theory modes). Doc: `users/{uid}/app_activity_progress/{source}__{refId}`.
String activityProgressDocId(String source, String refId) {
  final raw = '${source}__$refId'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return raw.length > 128 ? raw.substring(0, 128) : raw;
}

Future<void> recordActivityProgress(
  String uid, {
  required String source,
  required String refId,
  required String courseId,
  required String subcourseId,
  List<String>? attemptedQuestionIds,
  List<String>? correctQuestionIds,
  List<String>? viewedItemIds,
  int? totalItems,
  int? secondsSpent,
  bool countVisit = false,
  bool completed = false,
}) async {
  if (uid.isEmpty || refId.isEmpty || subcourseId.isEmpty) return;
  try {
    final path =
        'users/$uid/app_activity_progress/${activityProgressDocId(source, refId)}';
    final existing = await ExamRest.getDoc(path);
    Set<String> merge(List<String>? incoming, dynamic existingValue) {
      final out = <String>{
        ...((existingValue as List?) ?? []).whereType<String>()
      };
      if (incoming != null) out.addAll(incoming);
      return out;
    }

    final prevCompleted = existing?['completed'] == true;
    await ExamRest.setDoc(path, {
      'source': source,
      'refId': refId,
      'courseId': courseId,
      'subcourseId': subcourseId,
      'attemptedQuestionIds':
          merge(attemptedQuestionIds, existing?['attemptedQuestionIds'])
              .toList(),
      'correctQuestionIds':
          merge(correctQuestionIds, existing?['correctQuestionIds']).toList(),
      'viewedItemIds':
          merge(viewedItemIds, existing?['viewedItemIds']).toList(),
      'totalItems': totalItems != null
          ? (totalItems < 0 ? 0 : totalItems)
          : (_num(existing?['totalItems'], 0)),
      'secondsSpent': _num(existing?['secondsSpent'], 0) +
          (secondsSpent != null && secondsSpent > 0 ? secondsSpent : 0),
      'visits': _num(existing?['visits'], 0) + (countVisit ? 1 : 0),
      'completed': completed || prevCompleted,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  } catch (_) {
    // Silent by design — usage tracking must never surface an error.
  }
}

/// App activity counter (appUsage.ts recordAppActivity — simplified: reads the
/// summary doc and bumps activityCount by [count], merge-writes it back).
Future<void> recordAppActivity(String uid, [int count = 1]) async {
  if (uid.isEmpty || count <= 0) return;
  try {
    final path = 'users/$uid/app_usage/summary';
    final existing = await ExamRest.getDoc(path);
    await ExamRest.setDoc(path, {
      'activityCount': _num(existing?['activityCount'], 0) + count,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  } catch (_) {}
}

/// My content purchases: `app_content_purchases` where uid == (contentPurchases.ts
/// fetchMyContentPurchases — newest first). Fields: status, contentType
/// ('chapter'|'subject'), contentId.
Future<List<Map<String, dynamic>>> fetchMyContentPurchases(String uid) async {
  final docs = await ExamRest.runQuery(
    'app_content_purchases',
    where: ExamRest.fieldFilter('uid', 'EQUAL', uid),
  );
  return docs.map((d) {
    final created = d['createdAt'];
    int ts = 0;
    if (created is String) {
      ts = DateTime.tryParse(created)?.millisecondsSinceEpoch ?? 0;
    }
    return {...d, '_ts': ts};
  }).toList()
    ..sort((a, b) => (b['_ts'] as int).compareTo(a['_ts'] as int));
}

/// One question-set doc:
/// `app_subject_cucqdata_Allmode/{course}__{subcourse}__{subject}__{unit|no-unit}__{chapter}__{mode}`
/// (learningContent.ts learningQuestionSetId).
String learningQuestionSetDocId(String courseId, String subcourseId,
    String subjectId, String? unitId, String chapterId, String mode) {
  final subject = appSubjectSlug(subjectId);
  final unit = unitId == null || unitId.isEmpty
      ? 'no-unit'
      : canonicalCatalogSlug(unitId);
  final chapter = canonicalCatalogSlug(chapterId);
  return '${courseId}__${subcourseId}__${subject}__${unit}__${chapter}__$mode';
}

Future<Map<String, dynamic>?> fetchQuestionSetDoc(
    String courseId,
    String subcourseId,
    String subjectId,
    String? unitId,
    String chapterId,
    String mode) async {
  return ExamRest.getDoc(
      'app_subject_cucqdata_Allmode/${learningQuestionSetDocId(courseId, subcourseId, subjectId, unitId, chapterId, mode)}');
}

/// Theory resource doc:
/// `app_subject_theory_resources/{course}__{subcourse}__{subject}__{unit|no-unit}__{chapter}__theory`.
Future<Map<String, dynamic>?> fetchTheoryResource(
    String courseId,
    String subcourseId,
    String subjectId,
    String? unitId,
    String chapterId) async {
  return ExamRest.getDoc(
      'app_subject_theory_resources/${learningQuestionSetDocId(courseId, subcourseId, subjectId, unitId, chapterId, 'theory')}');
}

class SubjectQuestion {
  final String id;
  final String text;
  final String textNe;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String explanationNe;
  final String difficulty;
  final int order;

  const SubjectQuestion({
    required this.id,
    required this.text,
    required this.textNe,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.explanationNe,
    required this.difficulty,
    required this.order,
  });
}

/// Exact port of questionFromArrayItem (learningContent.ts).
List<SubjectQuestion> parseQuestionItems(
    Map<String, dynamic> doc, String docId, String mode) {
  final raw = doc['questions'];
  if (raw is! List) return [];
  final out = <SubjectQuestion>[];
  final docPublished = doc['isPublished'] != false;
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map<String, dynamic>) continue;
    if (item['isActive'] == false || !docPublished) continue;
    final opts = <String>[];
    final rawOpts = item['options'];
    if (rawOpts is List) {
      for (var j = 0; j < rawOpts.length; j++) {
        final o = rawOpts[j];
        if (o is String) {
          opts.add(o);
        } else if (o is Map<String, dynamic>) {
          opts.add((o['textEn'] as String?) ?? (o['text'] as String?) ?? '');
        }
      }
    }
    final correctId = (item['correctOptionId'] as String?) ?? '';
    var correctIndex = _num(item['correctIndex'], 0);
    if (correctId.isNotEmpty && rawOpts is List) {
      final found = rawOpts.indexWhere(
          (o) => o is Map<String, dynamic> && '${o['id'] ?? ''}' == correctId);
      if (found >= 0) correctIndex = found;
    }
    if (correctIndex < 0) correctIndex = 0;
    final text =
        (item['questionEn'] as String?) ?? (item['text'] as String?) ?? '';
    final textNe = (item['questionNe'] as String?) ??
        (item['textNe'] as String?) ??
        (item['questionEn'] as String?) ??
        (item['text'] as String?) ??
        '';
    final explanation = (item['explanationEn'] as String?) ??
        (item['explanation'] as String?) ??
        '';
    final explanationNe = (item['explanationNe'] as String?) ??
        (item['explanationEn'] as String?) ??
        (item['explanation'] as String?) ??
        '';
    final diff = (item['difficulty'] as String?) ?? 'easy';
    out.add(SubjectQuestion(
      id: (item['questionId'] as String?) ??
          (item['id'] as String?) ??
          '${docId}__question-${i + 1}',
      text: text,
      textNe: textNe,
      options: opts,
      correctIndex: correctIndex,
      explanation: explanation,
      explanationNe: explanationNe,
      difficulty: (diff == 'hard' || diff == 'medium') ? diff : 'easy',
      order: _num(item['order'], i + 1),
    ));
  }
  out.sort((a, b) => a.order.compareTo(b.order));
  return out;
}

/// bilingual(english, nepali): "en | ne" when they differ.
String bilingual(String english, String nepali) {
  final ne = nepali.trim();
  return ne.isNotEmpty && ne != english.trim() ? '$english | $ne' : english;
}

/// fetchPracticeQuestionSet / fetchReadQuestionSet (learningContent.ts):
/// read the one question-set doc for the mode, parse with parseQuestionItems,
/// return [] when the doc is unseeded/deleted.
Future<List<SubjectQuestion>> fetchPracticeQuestionSet({
  required String courseId,
  required String subcourseId,
  required String subjectId,
  String? unitId,
  required String chapterId,
}) async {
  final doc = await fetchQuestionSetDoc(
      courseId, subcourseId, subjectId, unitId, chapterId, 'practice');
  if (doc == null) return [];
  return parseQuestionItems(
      doc,
      learningQuestionSetDocId(
          courseId, subcourseId, subjectId, unitId, chapterId, 'practice'),
      'practice');
}

Future<List<SubjectQuestion>> fetchReadQuestionSet({
  required String courseId,
  required String subcourseId,
  required String subjectId,
  String? unitId,
  required String chapterId,
}) async {
  final doc = await fetchQuestionSetDoc(
      courseId, subcourseId, subjectId, unitId, chapterId, 'read');
  if (doc == null) return [];
  return parseQuestionItems(
      doc,
      learningQuestionSetDocId(
          courseId, subcourseId, subjectId, unitId, chapterId, 'read'),
      'read');
}

/// Local device date YYYY-MM-DD (practice.tsx dayKey).
String localDayKey([DateTime? now]) {
  final n = now ?? DateTime.now();
  String p(int v) => '$v'.padLeft(2, '0');
  return '${n.year}-${p(n.month)}-${p(n.day)}';
}

/// Fisher-Yates shuffle (practice.tsx shuffleQuestions).
List<T> shuffleList<T>(List<T> items) {
  final out = List<T>.from(items);
  final rnd = DateTime.now().microsecondsSinceEpoch;
  var seed = rnd & 0x7fffffff;
  int nextInt(int max) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % max;
  }

  for (var i = out.length - 1; i > 0; i--) {
    final j = nextInt(i + 1);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Practice questions (questions collection)
// ---------------------------------------------------------------------------

class PracticeQuestion {
  final String id;
  final String subjectId;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String difficulty;
  final String? textNe;
  final String? explanationNe;

  PracticeQuestion({
    required this.id,
    required this.subjectId,
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
    this.textNe,
    this.explanationNe,
  });

  factory PracticeQuestion.fromMap(Map<String, dynamic> m) => PracticeQuestion(
        id: _str(m['id']),
        subjectId: _str(m['subjectId']),
        text: _str(m['text']),
        options: (m['options'] as List?)?.map((e) => '$e').toList() ?? [],
        correctIndex: _num(m['correctIndex']),
        explanation: _str(m['explanation']),
        difficulty: _str(m['difficulty'], 'medium'),
        textNe: m['textNe'] is String ? m['textNe'] as String : null,
        explanationNe:
            m['explanationNe'] is String ? m['explanationNe'] as String : null,
      );

  String get bilingualText {
    final ne = (textNe ?? '').trim();
    return text.trim() + (ne.isNotEmpty && ne != text.trim() ? ' | $ne' : '');
  }

  String get bilingualExplanation {
    final ne = (explanationNe ?? '').trim();
    final en = explanation.trim();
    return en + (ne.isNotEmpty && ne != en ? ' | $ne' : '');
  }
}

Future<List<PracticeQuestion>> fetchPracticeQuestions(String subjectId,
    {int limit = 50}) async {
  final docs = await ExamRest.runQuery(
    'questions',
    where: ExamRest.fieldFilter('subjectId', 'EQUAL', subjectId),
    limit: limit,
  );
  return docs.map(PracticeQuestion.fromMap).toList();
}

// ---------------------------------------------------------------------------
// Main leaderboard (app_main_leaderboard)
// ---------------------------------------------------------------------------

class MainLeaderboardRow {
  final String id;
  final String uid;
  final String name;
  final String? photoURL;
  final bool isPro;
  final double percent;
  final int points;
  final int usageSeconds;
  final int activityCount;

  /// One-time signup bonus baked into [points] (see ensureMainLeaderboardRow).
  /// Absent on rows published before the bonus existed - defaults to 0.
  final int signupBonus;

  MainLeaderboardRow({
    required this.id,
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.isPro,
    required this.percent,
    required this.points,
    required this.usageSeconds,
    this.activityCount = 0,
    this.signupBonus = 0,
  });

  factory MainLeaderboardRow.fromMap(Map<String, dynamic> m) =>
      MainLeaderboardRow(
        id: _str(m['id']),
        uid: _str(m['uid']),
        name: _str(m['name'], 'Anonymous'),
        photoURL: m['photoURL'] is String ? m['photoURL'] as String : null,
        isPro: _bool(m['isPro']),
        percent: _dbl(m['percent']),
        points: _num(m['points']),
        usageSeconds: _num(m['usageSeconds']),
        activityCount: _num(m['activityCount']),
        signupBonus: _num(m['signupBonus']),
      );
}

/// Mirrors compareMainLeaderboardRows in services/mainLeaderboard.ts:
/// points desc, then percent desc, then usageSeconds desc, then
/// activityCount desc, then uid asc (stable order across refetches).
int compareMainLeaderboardRows(MainLeaderboardRow a, MainLeaderboardRow b) {
  if (b.points != a.points) return b.points.compareTo(a.points);
  if (b.percent != a.percent) return b.percent.compareTo(a.percent);
  if (b.usageSeconds != a.usageSeconds) {
    return b.usageSeconds.compareTo(a.usageSeconds);
  }
  if (b.activityCount != a.activityCount) {
    return b.activityCount.compareTo(a.activityCount);
  }
  return a.uid.compareTo(b.uid);
}

/// Mirrors fetchMainLeaderboard in services/mainLeaderboard.ts: filter on
/// subcourseId ONLY and sort client-side. A server-side orderBy on a
/// different field would require a composite index which does not exist in
/// the project (the REST API fails the whole query instead of returning
/// results). One row per uid: a stale duplicate from an older id scheme must
/// not let the same person occupy two positions.
Future<List<MainLeaderboardRow>> fetchMainLeaderboard(
    String subcourseId) async {
  if (subcourseId.isEmpty) return [];
  try {
    final docs = await ExamRest.runQuery(
      'app_main_leaderboard',
      where: ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
      limit: 300,
    );
    final bestByUid = <String, MainLeaderboardRow>{};
    for (final d in docs) {
      final row = MainLeaderboardRow.fromMap(d);
      if (row.uid.isEmpty) continue;
      final existing = bestByUid[row.uid];
      if (existing == null || compareMainLeaderboardRows(row, existing) < 0) {
        bestByUid[row.uid] = row;
      }
    }
    final rows = bestByUid.values.toList()..sort(compareMainLeaderboardRows);
    return rows;
  } catch (_) {
    return [];
  }
}

/// Page size for the paged leaderboard: the podium (3) plus roughly one
/// screen of ranking rows. The board reveals only after this page — data and
/// photos — is fully loaded, so the first paint never pops in half-ready.
const mainLeaderboardPageSize = 15;

/// One page of the main leaderboard, ordered server-side by points desc
/// (document name asc as the stable tiebreak).
///
/// Requires the composite index
/// `app_main_leaderboard (subcourseId ASC, points DESC, __name__ ASC)`.
/// Throws [MissingIndexException] when that index does not exist yet — the
/// caller falls back to [fetchMainLeaderboard] (full fetch + client sort).
/// [startAfter] continues from the last row of the previous page.
/// One row per uid: a stale duplicate id scheme must not let the same person
/// occupy two positions, so callers drop uids they have already seen
/// (the better duplicate always sorts first under points DESC).
Future<List<MainLeaderboardRow>> fetchMainLeaderboardPage(
  String subcourseId, {
  int limit = mainLeaderboardPageSize,
  MainLeaderboardRow? startAfter,
}) async {
  if (subcourseId.isEmpty) return [];
  List<Map<String, dynamic>>? cursor;
  if (startAfter != null) {
    cursor = [
      ExamRest.encode(startAfter.points),
      {
        'referenceValue':
            '${ExamRest._base}/app_main_leaderboard/${startAfter.id}',
      },
    ];
  }
  final docs = await ExamRest.runQuery(
    'app_main_leaderboard',
    where: ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
    orderBy: [
      ExamRest.orderField('points', 'DESCENDING'),
      ExamRest.orderField('__name__', 'ASCENDING'),
    ],
    limit: limit,
    startAfter: cursor,
  );
  final rows = <MainLeaderboardRow>[];
  for (final d in docs) {
    final row = MainLeaderboardRow.fromMap(d);
    if (row.uid.isEmpty) continue;
    rows.add(row);
  }
  return rows;
}

/// Exact 1-based rank of a points value without reading every document:
/// count of rows in the same subcourse with strictly more points, + 1
/// (standard competition ranking — ties share the rank).
/// Needs the same composite index as [fetchMainLeaderboardPage];
/// throws [MissingIndexException] when it is missing.
Future<int> countMainLeaderboardRank(String subcourseId, int points) async {
  final where = {
    'compositeFilter': {
      'op': 'AND',
      'filters': [
        ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
        ExamRest.fieldFilter('points', 'GREATER_THAN', points),
      ],
    },
  };
  final ahead = await ExamRest.runCount('app_main_leaderboard', where: where);
  return ahead + 1;
}

// ---------------------------------------------------------------------------
// Question of the Day (app_qotd_daily / users/{uid}/questionofdata)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Question of the Day — exact port of src/core/firebase/services/qotd.ts.
// The daily question is published by the admin, NOT rotated client-side:
// doc id `{kathmanduDateKey}__{courseId}__{subcourseId}` in `app_qotd_daily`.
// The "new question at 12AM" behavior is the Kathmandu date key rolling over
// at midnight + a midnight refresh timer on the screens.
// Result doc: `users/{uid}/questionofdata/{attemptId}` where attemptId =
// `{dateKey}__{courseId}__{subcourseId}__v{version}__{fingerprint}`
// (FNV-1a 32-bit of content|options|correctOptionId, base36).
// Summary: `users/{uid}/questionofdata/summary`. Greetings: `meta/qotd_greetings`.
// ---------------------------------------------------------------------------

class QotdOption {
  final String id;
  final String content;

  QotdOption({required this.id, required this.content});

  factory QotdOption.fromMap(Map m) => QotdOption(
        id: _str(m['id']),
        content: _str(m['content']),
      );

  Map<String, dynamic> toMap() => {'id': id, 'content': content};
}

class QotdCategory {
  final String id;
  final String name;
  final String color;

  QotdCategory({required this.id, required this.name, required this.color});

  factory QotdCategory.fromMap(Map m) => QotdCategory(
        id: _str(m['id']),
        name: _str(m['name']),
        color: _str(m['color'], '#2563EB'),
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'color': color};
}

class QotdQuestion {
  final String id;
  final String dateKey;
  final String showingDate;
  final String courseId;
  final String courseName;
  final String subcourseId;
  final String subcourseName;
  final String content;
  final List<QotdOption> options;
  final String correctOptionId;
  final String explanation;
  final String correctGreeting;
  final String wrongGreeting;
  final String difficulty;
  final List<QotdCategory> categories;
  final int version;
  final bool isPublished;

  QotdQuestion({
    required this.id,
    required this.dateKey,
    required this.showingDate,
    required this.courseId,
    required this.courseName,
    required this.subcourseId,
    required this.subcourseName,
    required this.content,
    required this.options,
    required this.correctOptionId,
    required this.explanation,
    required this.correctGreeting,
    required this.wrongGreeting,
    required this.difficulty,
    required this.categories,
    required this.version,
    required this.isPublished,
  });

  /// Mirrors normalizeQuestion(): defaults + caps, greetings overlaid from
  /// `meta/qotd_greetings`.
  factory QotdQuestion.normalized(Map<String, dynamic> raw, String fallbackId,
      Map<String, dynamic>? greetings) {
    const abcd = 'ABCD';
    final rawOpts = (raw['options'] as List?) ?? [];
    final options = <QotdOption>[];
    for (var i = 0; i < rawOpts.length && i < 4; i++) {
      final o = rawOpts[i];
      if (o is Map) {
        options.add(QotdOption(
          id: _str(o['id']).isEmpty ? abcd[i] : _str(o['id']),
          content: _str(o['content']),
        ));
      } else {
        options.add(QotdOption(id: abcd[i], content: '$o'));
      }
    }
    final snapshots = (raw['categorySnapshots'] as List?) ?? [];
    final names =
        ((raw['categoryNames'] as List?) ?? []).map((e) => '$e').toList();
    final ids = ((raw['categoryIds'] as List?) ?? []).map((e) => '$e').toList();
    final cats = <QotdCategory>[];
    final source = snapshots.isNotEmpty
        ? snapshots
        : List.generate(
            names.length,
            (i) => {
                  'id': i < ids.length ? ids[i] : names[i],
                  'name': names[i],
                  'color': '#2563EB'
                });
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (c is Map) {
        cats.add(QotdCategory(
          id: _str(c['id']).isEmpty
              ? (i < ids.length ? ids[i] : 'category-$i')
              : _str(c['id']),
          name: _str(c['name'], i < names.length ? names[i] : ''),
          color: _str(c['color'], '#2563EB'),
        ));
      }
    }
    final diff = _str(raw['difficulty']);
    return QotdQuestion(
      id: _str(raw['id'], fallbackId),
      dateKey: _str(raw['dateKey'], todayDateKey()),
      showingDate: _str(raw['showingDate']),
      courseId: _str(raw['courseId']),
      courseName: _str(raw['courseName'], _str(raw['courseId'])),
      subcourseId: _str(raw['subcourseId']),
      subcourseName: _str(raw['subcourseName'], _str(raw['subcourseId'])),
      content: _str(raw['content']),
      options: options,
      correctOptionId: _str(raw['correctOptionId'], 'A'),
      explanation: _str(raw['explanation']),
      correctGreeting:
          _str(greetings?['correctGreeting'], _str(raw['correctGreeting'])),
      wrongGreeting:
          _str(greetings?['wrongGreeting'], _str(raw['wrongGreeting'])),
      difficulty: (diff == 'easy' || diff == 'medium' || diff == 'hard')
          ? diff
          : 'medium',
      categories: cats,
      version: _num(raw['version'], 1),
      isPublished: raw['isPublished'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'dateKey': dateKey,
        'showingDate': showingDate,
        'courseId': courseId,
        'courseName': courseName,
        'subcourseId': subcourseId,
        'subcourseName': subcourseName,
        'content': content,
        'options': options.map((o) => o.toMap()).toList(),
        'correctOptionId': correctOptionId,
        'explanation': explanation,
        'correctGreeting': correctGreeting,
        'wrongGreeting': wrongGreeting,
        'difficulty': difficulty,
        'categories': categories.map((c) => c.toMap()).toList(),
        'version': version,
      };
}

class QotdResult {
  final String dateKey;
  final String courseId;
  final String subcourseId;
  final String selectedOptionId;
  final bool isCorrect;
  final DateTime? answeredAt;
  final QotdQuestion? snapshot;

  QotdResult({
    required this.dateKey,
    required this.courseId,
    required this.subcourseId,
    required this.selectedOptionId,
    required this.isCorrect,
    required this.answeredAt,
    this.snapshot,
  });

  factory QotdResult.fromMap(Map<String, dynamic> m) {
    final snap = m['snapshot'];
    return QotdResult(
      dateKey: _str(m['dateKey']),
      courseId: _str(m['courseId']),
      subcourseId: _str(m['subcourseId']),
      selectedOptionId: _str(m['selectedOptionId']),
      isCorrect: _bool(m['isCorrect']),
      answeredAt: _dt(m['answeredAt']),
      snapshot: snap is Map
          ? QotdQuestion.normalized(
              snap.cast<String, dynamic>(), _str(snap['id']), null)
          : null,
    );
  }
}

class QotdSummary {
  final int totalAttempts;
  final int correct;
  final double averagePercent;

  QotdSummary({
    required this.totalAttempts,
    required this.correct,
    required this.averagePercent,
  });

  factory QotdSummary.fromMap(Map<String, dynamic> m) => QotdSummary(
        totalAttempts: _num(m['totalAttempts']),
        correct: _num(m['correct']),
        averagePercent: _dbl(m['averagePercent']),
      );
}

class QotdDay {
  final String dateKey;
  final String courseId;
  final String subcourseId;
  final QotdQuestion? question;
  final QotdResult? result;
  final QotdSummary summary;

  QotdDay({
    required this.dateKey,
    required this.courseId,
    required this.subcourseId,
    required this.question,
    required this.result,
    required this.summary,
  });
}

/// FNV-1a 32-bit fingerprint of content|options|correctOptionId, base36 —
/// mirrors contentFingerprint() in qotd.ts (UTF-16 code units on both sides).
String _qotdFingerprint(QotdQuestion q) {
  final source =
      '${q.content}|${q.options.map((o) => '${o.id}:${o.content}').join('|')}|${q.correctOptionId}';
  var hash = 2166136261;
  for (final unit in source.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash.toRadixString(36);
}

String qotdDocumentId(String key, String courseId, String subcourseId) =>
    '${key}__${courseId}__${subcourseId}';

String qotdAttemptId(QotdQuestion q) =>
    '${q.dateKey}__${q.courseId}__${q.subcourseId}__v${q.version}__${_qotdFingerprint(q)}';

/// Mirrors fetchQotdDay(): today's published question + today's result +
/// summary, with the legacy `{dateKey}`-only result lookup fallback.
Future<QotdDay> fetchQotdDay(String uid, String courseId, String subcourseId,
    {String? key}) async {
  final k = key ?? todayDateKey();
  final emptySummary =
      QotdSummary(totalAttempts: 0, correct: 0, averagePercent: 0);
  if (courseId.isEmpty || subcourseId.isEmpty) {
    return QotdDay(
        dateKey: k,
        courseId: courseId,
        subcourseId: subcourseId,
        question: null,
        result: null,
        summary: emptySummary);
  }
  final docId = qotdDocumentId(k, courseId, subcourseId);
  final results = await Future.wait([
    ExamRest.getDoc('app_qotd_daily/$docId').catchError((_) => null),
    ExamRest.getDoc('users/$uid/questionofdata/summary')
        .catchError((_) => null),
    ExamRest.getDoc('meta/qotd_greetings').catchError((_) => null),
  ]);
  final qRaw = results[0];
  final summary = QotdSummary.fromMap(results[1] ?? {});
  final greetings = results[2];
  if (qRaw == null || qRaw['isPublished'] == false) {
    return QotdDay(
        dateKey: k,
        courseId: courseId,
        subcourseId: subcourseId,
        question: null,
        result: null,
        summary: summary);
  }
  final question = QotdQuestion.normalized(qRaw, docId, greetings);

  QotdResult? result;
  final attemptDoc = await ExamRest.getDoc(
          'users/$uid/questionofdata/${qotdAttemptId(question)}')
      .catchError((_) => null);
  Map<String, dynamic>? rRaw = attemptDoc;
  if (rRaw == null) {
    // Legacy lookup: result stored under the bare date key; valid only if the
    // snapshot still matches today's question id + version.
    final legacy = await ExamRest.getDoc('users/$uid/questionofdata/$k')
        .catchError((_) => null);
    final snap = legacy?['snapshot'];
    if (legacy != null &&
        snap is Map &&
        '${snap['id'] ?? ''}' == question.id &&
        _num(snap['version']) == question.version) {
      rRaw = legacy;
    }
  }
  if (rRaw != null && rRaw['snapshot'] is Map) {
    final snapRaw = Map<String, dynamic>.from(rRaw['snapshot'] as Map);
    snapRaw['correctGreeting'] =
        _str(greetings?['correctGreeting'], _str(snapRaw['correctGreeting']));
    snapRaw['wrongGreeting'] =
        _str(greetings?['wrongGreeting'], _str(snapRaw['wrongGreeting']));
    final merged = Map<String, dynamic>.from(rRaw)..['snapshot'] = snapRaw;
    result = QotdResult.fromMap(merged);
  }
  return QotdDay(
      dateKey: k,
      courseId: courseId,
      subcourseId: subcourseId,
      question: question,
      result: result,
      summary: summary);
}

/// Mirrors submitQotdAnswer(): expiry guard, idempotent (returns existing
/// result), stores the full question snapshot, updates the summary with
/// Math.round(correct*10000/total)/100.
Future<({QotdResult result, QotdSummary summary})> submitQotdAnswer(String uid,
    QotdQuestion question, String selectedOptionId, QotdSummary prior) async {
  final key = todayDateKey();
  if (question.dateKey != key) {
    throw Exception(
        'This daily question has expired. Please load today\u2019s question.');
  }
  final path = 'users/$uid/questionofdata/${qotdAttemptId(question)}';
  final existing = await ExamRest.getDoc(path).catchError((_) => null);
  if (existing != null) {
    return (result: QotdResult.fromMap(existing), summary: prior);
  }
  final isCorrect = selectedOptionId == question.correctOptionId;
  final result = QotdResult(
    dateKey: key,
    courseId: question.courseId,
    subcourseId: question.subcourseId,
    selectedOptionId: selectedOptionId,
    isCorrect: isCorrect,
    answeredAt: DateTime.now().toUtc(),
    snapshot: question,
  );
  final total = prior.totalAttempts + 1;
  final correct = prior.correct + (isCorrect ? 1 : 0);
  final avg = (correct * 10000 / total).round() / 100;
  final summaryDoc = await ExamRest.getDoc('users/$uid/questionofdata/summary')
      .catchError((_) => null);
  final mergedSummary = {
    ...?summaryDoc,
    'totalAttempts': total,
    'correct': correct,
    'averagePercent': avg,
    'updatedAt': DateTime.now().toUtc(),
  };
  await ExamRest.setDoc(path, {
    'dateKey': key,
    'courseId': question.courseId,
    'subcourseId': question.subcourseId,
    'selectedOptionId': selectedOptionId,
    'isCorrect': isCorrect,
    'answeredAt': DateTime.now().toUtc(),
    'snapshot': question.toMap(),
  });
  await ExamRest.setDoc('users/$uid/questionofdata/summary', mergedSummary);
  return (
    result: result,
    summary: QotdSummary.fromMap(mergedSummary),
  );
}

/// Split bilingual `en || ne` content — the Flutter app is English-only, so
/// this returns the English half (mirrors split(v, 'en') in qotd screens).
String qotdEn(String v) {
  final p = v.split('||');
  final en = p[0].trim();
  return en.isNotEmpty ? en : v.trim();
}

/// Legacy helpers kept for existing callers.
Future<QotdQuestion?> fetchTodayQuestion(
    String courseId, String subcourseId) async {
  final docId = '${todayDateKey()}__${courseId}__${subcourseId}';
  final doc =
      await ExamRest.getDoc('app_qotd_daily/$docId').catchError((_) => null);
  if (doc == null || doc['isPublished'] == false) return null;
  return QotdQuestion.normalized(doc, docId, null);
}

Future<QotdResult?> fetchQotdResult(String uid, String attemptId) async {
  final doc = await ExamRest.getDoc('users/$uid/questionofdata/$attemptId')
      .catchError((_) => null);
  return doc == null ? null : QotdResult.fromMap(doc);
}

Future<QotdSummary> fetchQotdSummary(String uid) async {
  final doc = await ExamRest.getDoc('users/$uid/questionofdata/summary')
      .catchError((_) => null);
  return QotdSummary.fromMap(doc ?? {});
}

/// Saves an answer + rolls it into the summary; returns the updated summary.
Future<QotdSummary> answerQotd({
  required String uid,
  required String attemptId,
  required QotdQuestion question,
  required String selectedOptionId,
}) async {
  final prior = await fetchQotdSummary(uid);
  final saved = await submitQotdAnswer(uid, question, selectedOptionId, prior);
  return saved.summary;
}

// ---------------------------------------------------------------------------
// Daily Test scheduling + formatting helpers.
// Mirrors services/dailyTest.ts: date keys, release scheduling, rules, formats.
// ---------------------------------------------------------------------------

/// Marks the placeholder "upcoming" card for subcourses with nothing scheduled.
const String demoUpcomingModelId = '__demo-upcoming';

/// Milliseconds until the next local midnight — for the auto-rollover timer.
int msUntilNextLocalMidnight([DateTime? now]) {
  final n = now ?? DateTime.now();
  final next = DateTime(n.year, n.month, n.day + 1);
  return next.difference(n).inMilliseconds;
}

final RegExp _dateKeyRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Reads a release date off a raw document: `testDate` string, an older
/// `scheduledFor` field, or finally the `createdAt` timestamp — so documents
/// written before scheduling existed count as released on their creation day.
String _dailyTestDateKey(Map<String, dynamic> m) {
  String from(dynamic v) {
    if (v is String) {
      final t = v.trim();
      if (_dateKeyRe.hasMatch(t)) return t;
      if (t.length >= 10 && _dateKeyRe.hasMatch(t.substring(0, 10))) {
        return t.substring(0, 10);
      }
      return '';
    }
    if (v is DateTime) {
      final d = v.toLocal();
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  final a = from(m['testDate']);
  if (a.isNotEmpty) return a;
  final b = from(m['scheduledFor']);
  if (b.isNotEmpty) return b;
  return from(m['createdAt']);
}

/// True for the placeholder upcoming card — never playable.
bool isDailyTestDemo(DailyTestModel? model) =>
    model != null && model.id == demoUpcomingModelId;

/// True once the model's release date has arrived (or passed).
bool isDailyTestReleased(DailyTestModel model, String today) =>
    model.testDate.isNotEmpty && model.testDate.compareTo(today) <= 0;

/// Countdown for one question — its own value, else the model default.
int questionTimeSeconds(DailyTestModel model, int index) {
  final own =
      index < model.questions.length ? model.questions[index].timeSeconds : 0;
  if (own > 0) return own;
  if (model.perQuestionTimeSeconds > 0) return model.perQuestionTimeSeconds;
  return 30;
}

/// Total time budget for the whole model, in seconds.
int totalTestSeconds(DailyTestModel model) {
  var sum = 0;
  for (var i = 0; i < model.questions.length; i++) {
    sum += questionTimeSeconds(model, i);
  }
  return sum;
}

/// "1m 30s" / "45s" — shared by every Daily Test screen.
String formatDailyTestDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = safe % 60;
  if (m == 0) return '${s}s';
  if (s == 0) return '${m}m';
  return '${m}m ${s}s';
}

/// Every model scheduled for exactly this date, in `order`.
List<DailyTestModel> modelsForDate(
    List<DailyTestModel> models, String dateKey) {
  if (dateKey.isEmpty) return [];
  final out = models.where((m) => m.testDate == dateKey).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return out;
}

/// Released models the user never attempted, most recent first — the "Missed"
/// slides. Today's own models are excluded (still playable).
List<DailyTestModel> missedDailyTestModels(
    List<DailyTestModel> models, Set<String> doneIds, String today) {
  final out = models
      .where((m) =>
          m.testDate.isNotEmpty &&
          m.testDate.compareTo(today) < 0 &&
          !doneIds.contains(m.id))
      .toList()
    ..sort((a, b) => a.testDate == b.testDate
        ? b.order.compareTo(a.order)
        : b.testDate.compareTo(a.testDate));
  return out;
}

/// The next date on which anything is scheduled, or null when nothing is queued.
String? nextScheduledDate(List<DailyTestModel> models, String today) {
  DailyTestModel? next;
  for (final m in models) {
    if (m.testDate.isEmpty || m.testDate.compareTo(today) <= 0) continue;
    if (next == null ||
        m.testDate.compareTo(next.testDate) < 0 ||
        (m.testDate == next.testDate && m.order < next.order)) {
      next = m;
    }
  }
  return next?.testDate;
}

/// Stand-in for the "Upcoming" slot in subcourses with nothing scheduled ahead.
/// NOT labelled a sample — the card reads like any other upcoming test.
DailyTestModel buildDemoUpcomingModel({
  required String courseId,
  required String subcourseId,
  required String dateKey,
  String? subcourseName,
}) {
  final title = (subcourseName ?? '').trim().isNotEmpty
      ? '${subcourseName!.trim()} New Set'
      : 'New Set';
  return DailyTestModel(
    id: demoUpcomingModelId,
    name: title,
    modelName: title,
    courseId: courseId,
    subcourseId: subcourseId,
    testDate: dateKey,
    questions: const [],
    category: 'medium',
    perQuestionTimeSeconds: 30,
    negativeMarking: false,
    negativeMarkPercent: 0.2,
    marksPerQuestion: 1,
    passPercent: 40,
    rules: const [],
    isPro: false,
    subscriptionType: 'off',
    price: 0,
    active: true,
    order: 9999,
  );
}

const Map<String, String> _weekdayShort = {
  '1': 'Mon',
  '2': 'Tue',
  '3': 'Wed',
  '4': 'Thu',
  '5': 'Fri',
  '6': 'Sat',
  '7': 'Sun',
};

const List<String> _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

const List<String> _monthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

DateTime? _dateFromKey(String key) {
  if (!_dateKeyRe.hasMatch(key)) return null;
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

/// "Sat, 12 Sep" — the compact form used on cards and chips.
String formatDateKeyShort(String key) {
  final d = _dateFromKey(key);
  if (d == null) return key;
  return '${_weekdayShort['${d.weekday}']}, ${d.day} ${_monthShort[d.month - 1]}';
}

/// "Saturday, 12 September 2026" — the long form used in the empty-state card.
String formatDateKeyLong(String key) {
  final d = _dateFromKey(key);
  if (d == null) return key;
  const names = {
    '1': 'Monday',
    '2': 'Tuesday',
    '3': 'Wednesday',
    '4': 'Thursday',
    '5': 'Friday',
    '6': 'Saturday',
    '7': 'Sunday',
  };
  return '${names['${d.weekday}']}, ${d.day} ${_monthLong[d.month - 1]} ${d.year}';
}

/// "Today" / "Tomorrow" / "Yesterday" / "in 3 days" / "5 days ago", else the
/// short date. Used on the upcoming/missed cards.
String relativeDayLabel(String key, [String? today]) {
  if (!_dateKeyRe.hasMatch(key)) return '';
  final t = today ?? todayDateKey();
  final a = _dateFromKey(t);
  final b = _dateFromKey(key);
  if (a == null || b == null) return formatDateKeyShort(key);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff <= 6) return 'in $diff days';
  if (diff < -1 && diff >= -6) return '${diff.abs()} days ago';
  return formatDateKeyShort(key);
}

String addDaysToKey(String key, int days) {
  final d = _dateFromKey(key);
  if (d == null) return key;
  final n = d.add(Duration(days: days));
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

/// Builds the point-by-point rule list from a model's config. The seed stores
/// the result on each document; this regenerates it for models that have none.
/// Mirrors composeRules()/buildDailyTestRules() in services/dailyTest.ts.
List<String> buildDailyTestRules(DailyTestModel model) {
  if (model.rules.isNotEmpty) return model.rules;
  final count = model.questions.length;
  final perQ = model.marksPerQuestion > 0 ? model.marksPerQuestion : 1.0;
  final perQLabel = perQ == perQ.roundToDouble() ? '${perQ.toInt()}' : '$perQ';
  final negPct =
      (model.negativeMarkPercent > 0 ? model.negativeMarkPercent : 0.2)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0$'), '');
  final penaltyMarks = (perQ *
              (model.negativeMarkPercent > 0
                  ? model.negativeMarkPercent
                  : 0.2) *
              100)
          .round() /
      100;
  final penaltyLabel = penaltyMarks == penaltyMarks.roundToDouble()
      ? '${penaltyMarks.toInt()}'
      : '$penaltyMarks';
  final passPct = model.passPercent > 0 ? model.passPercent : 40;
  final perQTime =
      model.perQuestionTimeSeconds > 0 ? model.perQuestionTimeSeconds : 30;
  final categoryLabel = model.category.isEmpty
      ? 'Medium'
      : model.category[0].toUpperCase() + model.category.substring(1);

  return [
    'This test has $count question${count == 1 ? '' : 's'} and must be finished in one sitting.',
    'Difficulty level of this model is $categoryLabel.',
    "Every question has its own timer of ${perQTime} seconds.",
    'Total time for the whole test is about ${formatDailyTestDuration(totalTestSeconds(model))}.',
    "When a question timer runs out the app moves to the next question automatically — the timer blinks for the last 5 seconds as a warning.",
    'Each correct answer awards $perQLabel mark${perQ == 1 ? '' : 's'}.',
    model.negativeMarking
        ? 'Negative Marking is ON — ${(model.negativeMarkPercent * 100).round()}% ($negPct) of the marks is deducted for every wrong answer, so a wrong answer costs $penaltyLabel mark${penaltyLabel == '1' ? '' : 's'}.'
        : 'Negative Marking is OFF — a wrong answer does not reduce your marks.',
    'Skipped questions carry no marks and no penalty.',
    'Only one option can be selected per question. Tap the selected option again to clear it.',
    'You cannot go back to a previous question, so read carefully before moving on.',
    'Each model can be attempted only ONCE — the result is saved to your account, so it stays completed even if you sign in on another phone.',
    'You need $passPct% or more to pass this test.',
    'Leaving the test before you submit will discard the whole attempt.',
    model.isPro
        ? 'This is a Premium model — an active subscription is required to attempt it.'
        : 'This model is Free for every enrolled user.',
    'Your score and a full answer review are available immediately after you submit.',
  ];
}

// ---------------------------------------------------------------------------
// Session completions (in-memory).
// Mirrors dailyTestCompletionStore: flips "Start Test" to "View Result" the
// moment the user returns from the Summary, with no extra read.
// ---------------------------------------------------------------------------

final Map<String, Map<String, DailyTestResult>> _dailyTestSessionResults = {};

/// Records a just-submitted result for this session, keyed by uid then modelId.
void markDailyTestCompleted(String uid, DailyTestResult result) {
  _dailyTestSessionResults.putIfAbsent(uid, () => {})[result.modelId] = result;
}

/// In-memory completions for this account, merged over fetched results.
Map<String, DailyTestResult> sessionDailyTestCompletions(String uid) =>
    Map.unmodifiable(_dailyTestSessionResults[uid] ?? {});

// ---------------------------------------------------------------------------
// On-device Daily Test activity log (per-account, newest first, max 20).
// Mirrors src/core/services/dailyTestActivity.ts — a lightweight convenience
// feed; the authoritative result lives in users/{uid}/daily_test_results.
// ---------------------------------------------------------------------------

class DailyTestActivity {
  final String id;
  final String modelId;
  final String modelName;
  final int score;
  final int totalQuestions;
  final int correct;
  final int incorrect;
  final int skipped;
  final int timeTakenSeconds;
  final int completedAt; // epoch millis
  final List<int>? answers; // -1 = skipped
  final bool? passed;
  final int? passPercent;

  const DailyTestActivity({
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.score,
    required this.totalQuestions,
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.timeTakenSeconds,
    required this.completedAt,
    this.answers,
    this.passed,
    this.passPercent,
  });

  factory DailyTestActivity.fromJson(Map<String, dynamic> j) =>
      DailyTestActivity(
        id: '${j['id'] ?? ''}',
        modelId: '${j['modelId'] ?? ''}',
        modelName: '${j['modelName'] ?? ''}',
        score: (j['score'] as num?)?.toInt() ?? 0,
        totalQuestions: (j['totalQuestions'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        incorrect: (j['incorrect'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        timeTakenSeconds: (j['timeTakenSeconds'] as num?)?.toInt() ?? 0,
        completedAt: (j['completedAt'] as num?)?.toInt() ?? 0,
        answers: (j['answers'] as List?)
            ?.map((a) => (a as num?)?.toInt() ?? -1)
            .toList(),
        passed: j['passed'] as bool?,
        passPercent: (j['passPercent'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'modelId': modelId,
        'modelName': modelName,
        'score': score,
        'totalQuestions': totalQuestions,
        'correct': correct,
        'incorrect': incorrect,
        'skipped': skipped,
        'timeTakenSeconds': timeTakenSeconds,
        'completedAt': completedAt,
        'answers': answers,
        'passed': passed,
        'passPercent': passPercent,
      };

  /// Older entries were saved before `passed` existed — fall back to the 40%
  /// default pass mark rather than showing them as failures.
  bool get isPassed {
    if (passed != null) return passed!;
    return score >= (passPercent ?? 40);
  }
}

String? _dailyTestActivityKey(String? uid) => uid == null || uid.isEmpty
    ? null
    : '@loksewa/daily-test/recent-activities/$uid';

/// Reads one account's feed, newest first. Never throws.
Future<List<DailyTestActivity>> getRecentDailyTestActivities(
    String? uid) async {
  final key = _dailyTestActivityKey(uid);
  if (key == null) return [];
  try {
    final raw = await PrefsService.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final parsed = jsonDecode(raw);
    if (parsed is! List) return [];
    final list = parsed
        .whereType<Map>()
        .map((e) =>
            DailyTestActivity.fromJson(e.map((k, v) => MapEntry('$k', v))))
        .where((a) => a.modelId.isNotEmpty)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return list;
  } catch (_) {
    return [];
  }
}

/// Prepends a finished attempt to the account's feed, de-duplicating by
/// modelId and capping at 20 entries. Never throws.
Future<void> addDailyTestActivity(
    String? uid, DailyTestActivity activity) async {
  final key = _dailyTestActivityKey(uid);
  if (key == null) return;
  try {
    final existing = await getRecentDailyTestActivities(uid);
    final updated = [
      activity,
      ...existing.where((a) => a.modelId != activity.modelId),
    ].take(20).toList();
    await PrefsService.setString(
        key, jsonEncode(updated.map((a) => a.toJson()).toList()));
  } catch (_) {
    // best-effort: the authoritative result is already saved on the server
  }
}

// ---------------------------------------------------------------------------
// Gorkhapatra (collection `gorkhapatra`, doc id == slug).
// Mirrors fetchGorkhapatraPosts/fetchGorkhapatraPost in services/content.ts.
// ---------------------------------------------------------------------------

/// Page size used by the list — cursor-based pagination on `publishedAt`.
const int gorkhapatraPageSize = 10;

/// One native content block inside a post (heading / text / image).
class GorkhapatraBlock {
  final String type;
  final String text;
  final String url;
  final String caption;

  const GorkhapatraBlock(
      {this.type = 'text', this.text = '', this.url = '', this.caption = ''});

  factory GorkhapatraBlock.fromMap(Map m) => GorkhapatraBlock(
        type: '${m['type'] ?? 'text'}',
        text: '${m['text'] ?? ''}',
        url: '${m['url'] ?? m['src'] ?? ''}',
        caption: '${m['caption'] ?? ''}',
      );
}

/// A Gorkhapatra post. `dateLabel` is verbatim (Bikram Sambat) when present.
class GorkhapatraPost {
  final String slug;
  final String title;
  final String excerpt;
  final String coverImage;
  final String dateLabel;
  final String tag;
  final String category;
  final bool isQuestionSet;
  final String source;
  final String sourceUrl;
  final DateTime? publishedAt;
  final List<GorkhapatraBlock> blocks;

  const GorkhapatraPost({
    required this.slug,
    this.title = '',
    this.excerpt = '',
    this.coverImage = '',
    this.dateLabel = '',
    this.tag = '',
    this.category = '',
    this.isQuestionSet = false,
    this.source = '',
    this.sourceUrl = '',
    this.publishedAt,
    this.blocks = const [],
  });

  factory GorkhapatraPost.fromMap(Map<String, dynamic> m) {
    DateTime? published;
    final raw = m['publishedAt'];
    if (raw is DateTime) {
      published = raw;
    } else if (raw is Map) {
      final s = raw['seconds'] ?? raw['_seconds'];
      if (s is num) {
        published = DateTime.fromMillisecondsSinceEpoch((s * 1000).toInt());
      }
    }
    final rawBlocks = m['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.whereType<Map>().map(GorkhapatraBlock.fromMap).toList()
        : const <GorkhapatraBlock>[];
    String slug = '${m['id'] ?? m['slug'] ?? ''}';
    return GorkhapatraPost(
      slug: slug,
      title: '${m['title'] ?? ''}',
      excerpt: '${m['excerpt'] ?? ''}',
      coverImage: '${m['coverImage'] ?? ''}',
      dateLabel: '${m['dateLabel'] ?? ''}',
      tag: '${m['tag'] ?? ''}',
      category: '${m['category'] ?? ''}',
      isQuestionSet: m['isQuestionSet'] == true,
      source: '${m['source'] ?? ''}',
      sourceUrl: '${m['sourceUrl'] ?? ''}',
      publishedAt: published,
      blocks: blocks,
    );
  }
}

/// One page of the post list plus the cursor for the next page.
class GorkhapatraPage {
  final List<GorkhapatraPost> items;
  final DateTime? nextCursor;

  const GorkhapatraPage({this.items = const [], this.nextCursor});
}

/// Latest posts, newest first. Pass `before` (the oldest publishedAt you hold)
/// to get the next page. Posts flagged `status: 'hidden'` are dropped.
Future<GorkhapatraPage> fetchGorkhapatraPosts({
  int limit = gorkhapatraPageSize,
  DateTime? before,
}) async {
  final rows = await ExamRest.runQuery(
    'gorkhapatra',
    where: before != null
        ? ExamRest.fieldFilter('publishedAt', 'LESS_THAN', before)
        : null,
    orderBy: [ExamRest.orderField('publishedAt', 'DESCENDING')],
    limit: limit,
  );
  final items = rows
      .where((p) => '${p['status'] ?? ''}' != 'hidden')
      .map(GorkhapatraPost.fromMap)
      .toList();
  DateTime? cursor;
  if (items.isNotEmpty) {
    final last = items.last.publishedAt;
    if (last != null) {
      // Firestore LESS_THAN is strict: subtract a tick so the last doc
      // of this page can never reappear on the next page.
      cursor = last.subtract(const Duration(milliseconds: 1));
    }
  }
  return GorkhapatraPage(items: items, nextCursor: cursor);
}

/// One post by slug (== document id). A single direct read — never a query.
Future<GorkhapatraPost?> fetchGorkhapatraPost(String slug) async {
  final doc = await ExamRest.getDoc('gorkhapatra/$slug');
  if (doc == null) return null;
  return GorkhapatraPost.fromMap(doc);
}
