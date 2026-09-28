/// Exam engine data layer — mirrors src/core/firebase/services/examHub.ts,
/// services/exams.ts, services/dailyTest.ts, services/qotd.ts and the main
/// leaderboard service from the Expo app.
///
/// Pure Dart `http` REST client (like FirestoreRest) so no native Firebase SDK
/// is needed. All functions take the raw Firestore fields and parse defensively.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'auth_service.dart';

// ---------------------------------------------------------------------------
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
    if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}');
    if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
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
      return {'arrayValue': {'values': v.map(encode).toList()}};
    }
    if (v is Map) {
      return {
        'mapValue': {
          'fields': (v as Map).map((k, val) => MapEntry('$k', encode(val)))
        }
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
    final res = await http.get(Uri.parse('$_base/$path'), headers: _headers(token));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('getDoc $path: ${res.statusCode}');
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
  static Future<List<Map<String, dynamic>>> runQuery(
    String collectionId, {
    String? parent,
    Map<String, dynamic>? where,
    List<Map<String, dynamic>>? orderBy,
    int limit = 100,
  }) async {
    final token = await _token();
    final from = {
      'collectionId': collectionId,
    };
    final structured = <String, dynamic>{'from': [from]};
    if (parent != null) structured['parent'] = parent;
    if (where != null) structured['where'] = where;
    if (orderBy != null) structured['orderBy'] = orderBy;
    structured['limit'] = limit;
    final res = await http.post(
      Uri.parse('$_base:runQuery'),
      headers: _headers(token),
      body: json.encode({'structuredQuery': structured}),
    );
    if (res.statusCode != 200) {
      throw Exception('runQuery $collectionId: ${res.statusCode} ${res.body}');
    }
    final list = json.decode(res.body) as List? ?? [];
    return list
        .map((e) => (e as Map)['document'] as Map<String, dynamic>?)
        .where((d) => d != null)
        .map((d) => _docToMap(d!))
        .toList();
  }

  static Map<String, dynamic> fieldFilter(String field, String op, dynamic value) => {
        'fieldFilter': {
          'field': {'fieldPath': field},
          'op': op,
          'value': encode(value),
        }
      };

  static Map<String, dynamic> orderField(String field, String direction) => {
        'field': {'fieldPath': field},
        'direction': direction,
      };

  /// Create a document with an auto-generated ID; returns the new doc ID.
  static Future<String> createDoc(
    String collectionPath,
    Map<String, dynamic> data,
  ) async {
    final token = await _token();
    final res = await http.post(
      Uri.parse('$_base/$collectionPath'),
      headers: _headers(token),
      body: json.encode({'fields': data.map((k, v) => MapEntry(k, encode(v)))}),
    );
    if (res.statusCode != 200) {
      throw Exception('createDoc $collectionPath: ${res.statusCode} ${res.body}');
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    return _docId('${body['name'] ?? ''}');
  }

  /// Full-document PATCH write (no update mask).
  static Future<void> setDoc(String path, Map<String, dynamic> data) async {
    final token = await _token();
    final res = await http.patch(
      Uri.parse('$_base/$path'),
      headers: _headers(token),
      body: json.encode({'fields': data.map((k, v) => MapEntry(k, encode(v)))}),
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
  final String courseId;
  final String subcourseId;

  UserProfile({
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.isPro,
    required this.courseId,
    required this.subcourseId,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) {
    var isPro = _bool(m['isPro']);
    final premiumUntil = _dt(m['premiumUntil']);
    if (premiumUntil != null && premiumUntil.isAfter(DateTime.now())) {
      isPro = true;
    }
    final status = _str(m['subscriptionStatus']);
    if (status == 'active' || status == 'premium') isPro = true;
    return UserProfile(
      uid: uid,
      name: _str(m['name'], _str(m['displayName'], 'Anonymous')),
      photoURL: m['photoURL'] is String ? m['photoURL'] as String : null,
      isPro: isPro,
      courseId: _str(m['courseId']),
      subcourseId: _str(m['subcourseId']),
    );
  }
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

  factory ExamSet.fromMap(Map<String, dynamic> m) => ExamSet(
        id: _str(m['id']),
        courseId: _str(m['courseId']),
        subcourseId: _str(m['subcourseId']),
        courseIds: _strList(m['courseIds']),
        subcourseIds: _strList(m['subcourseIds']),
        provinceId: _str(m['provinceId']),
        sectionId: _str(m['sectionId']),
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
            .map((q) => ExamQuestion.fromMap((q as Map).cast<String, dynamic>()))
            .toList(),
      );

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
        answers: ((m['answers'] as List?) ?? []).map((a) => _num(a, -1)).toList(),
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

  ExamRule({required this.icon, required this.title, required this.description});

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
bool areResultsUnlocked(ExamSet set, DateTime now) {
  if (set.startTime == null) return true;
  final unlockAt =
      set.startTime!.add(Duration(minutes: set.durationMinutes));
  return !now.isBefore(unlockAt);
}

Future<ExamSet?> fetchExamSet(String setId) async {
  final doc = await ExamRest.getDoc('app_exam_sets/$setId');
  return doc == null ? null : ExamSet.fromMap(doc);
}

Future<List<ExamRule>> fetchExamRules({
  String? courseId,
  String? subcourseId,
}) async {
  final docs = await ExamRest.listDocs('app_exam_rules');
  return docs.map(ExamRule.fromMap).where((r) {
    // Rules docs may scope by course; no scope fields => applies to all.
    final m = docs.isEmpty ? null : null;
    return m == null;
  }).toList();
}

Future<List<ExamAttempt>> fetchAttemptsForSet(
    String uid, String examSetId) async {
  final docs = await ExamRest.runQuery(
    'exam_attempts',
    parent: 'users/$uid',
    where: ExamRest.fieldFilter('examSetId', 'EQUAL', examSetId),
    orderBy: [ExamRest.orderField('createdAt', 'DESCENDING')],
    limit: 50,
  );
  return docs.map(ExamAttempt.fromMap).toList();
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

/// Best score per uid for a set, sorted score desc / time asc.
Future<List<RankingRow>> fetchExamRanking(String examSetId) async {
  final docs = await ExamRest.runQuery(
    'app_exam_rankings',
    where: ExamRest.fieldFilter('examSetId', 'EQUAL', examSetId),
    orderBy: [
      ExamRest.orderField('score', 'DESCENDING'),
      ExamRest.orderField('timeTakenSeconds', 'ASCENDING'),
    ],
    limit: 100,
  );
  final rows = docs.map(RankingRow.fromMap).toList();
  final seen = <String>{};
  final best = <RankingRow>[];
  for (final r in rows) {
    if (seen.add(r.uid)) best.add(r);
  }
  return best;
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
            selectedIndex: am['selectedIndex'] == null ? null : _num(am['selectedIndex']),
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
        modelName: _str(m['modelName']),
        courseId: _str(m['courseId']),
        subcourseId: _str(m['subcourseId']),
        testDate: _str(m['testDate']),
        questions: ((m['questions'] as List?) ?? [])
            .map((q) =>
                DailyTestQuestion.fromMap((q as Map).cast<String, dynamic>()))
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

  String get displayName => name.isNotEmpty ? name : modelName;
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
        answers: ((m['answers'] as List?) ?? []).map((a) => _num(a, -1)).toList(),
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

/// Mirrors scoreDailyTest() in services/dailyTest.ts.
DailyScore scoreDailyTest(
    DailyTestModel model, List<DailyTestQuestion> questions, List<int?> answers) {
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
  final marksEarned = correct * model.marksPerQuestion;
  final marksLost = model.negativeMarking
      ? ((incorrect * model.marksPerQuestion * model.negativeMarkPercent * 100).round() / 100)
      : 0.0;
  final netMarks = (marksEarned - marksLost).clamp(0.0, double.infinity);
  final totalMarks = questions.length * model.marksPerQuestion;
  final percent = totalMarks > 0 ? ((netMarks / totalMarks) * 100).round() : 0;
  final accuracy =
      questions.isNotEmpty ? ((correct / questions.length) * 100).round() : 0;
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
    passed: percent >= model.passPercent,
  );
}

/// Kathmandu date key YYYY-MM-DD (NPT = UTC+5:45).
String todayDateKey() {
  final kathmandu = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 45));
  return '${kathmandu.year.toString().padLeft(4, '0')}-'
      '${kathmandu.month.toString().padLeft(2, '0')}-'
      '${kathmandu.day.toString().padLeft(2, '0')}';
}

Future<List<DailyTestModel>> fetchDailyTestModels(String subcourseId) async {
  final docs = await ExamRest.runQuery(
    'app_daily_test_models',
    where: ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
    orderBy: [ExamRest.orderField('testDate', 'DESCENDING')],
    limit: 100,
  );
  return docs
      .map(DailyTestModel.fromMap)
      .where((m) => m.active)
      .toList();
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
    limit: 5,
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

Future<void> saveDailyTestResult({
  required String uid,
  required DailyTestModel model,
  required DailyScore score,
  required List<int> answers,
  required int timeTakenSeconds,
}) async {
  await ExamRest.createDoc('users/$uid/daily_test_results', {
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
    'createdAt': DateTime.now().toUtc(),
  });
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

  MainLeaderboardRow({
    required this.id,
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.isPro,
    required this.percent,
    required this.points,
    required this.usageSeconds,
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
      );
}

Future<List<MainLeaderboardRow>> fetchMainLeaderboard(String subcourseId) async {
  final docs = await ExamRest.runQuery(
    'app_main_leaderboard',
    where: ExamRest.fieldFilter('subcourseId', 'EQUAL', subcourseId),
    orderBy: [
      ExamRest.orderField('points', 'DESCENDING'),
      ExamRest.orderField('percent', 'DESCENDING'),
    ],
    limit: 100,
  );
  return docs.map(MainLeaderboardRow.fromMap).toList();
}

// ---------------------------------------------------------------------------
// Question of the Day (app_qotd_daily / users/{uid}/questionofdata)
// ---------------------------------------------------------------------------

class QotdOption {
  final String id;
  final String content;

  QotdOption({required this.id, required this.content});

  factory QotdOption.fromMap(Map m) => QotdOption(
        id: _str(m['id']),
        content: _str(m['content']),
      );
}

class QotdQuestion {
  final String id;
  final String dateKey;
  final String courseId;
  final String courseName;
  final String subcourseId;
  final String subcourseName;
  final String content;
  final List<QotdOption> options;
  final String correctOptionId;
  final String explanation;
  final String difficulty;
  final String showingDate;

  QotdQuestion({
    required this.id,
    required this.dateKey,
    required this.courseId,
    required this.courseName,
    required this.subcourseId,
    required this.subcourseName,
    required this.content,
    required this.options,
    required this.correctOptionId,
    required this.explanation,
    required this.difficulty,
    required this.showingDate,
  });

  factory QotdQuestion.fromMap(Map<String, dynamic> m) => QotdQuestion(
        id: _str(m['id']),
        dateKey: _str(m['dateKey']),
        courseId: _str(m['courseId']),
        courseName: _str(m['courseName']),
        subcourseId: _str(m['subcourseId']),
        subcourseName: _str(m['subcourseName']),
        content: _str(m['content']),
        options: ((m['options'] as List?) ?? [])
            .map((o) => QotdOption.fromMap((o as Map).cast()))
            .toList(),
        correctOptionId: _str(m['correctOptionId']),
        explanation: _str(m['explanation']),
        difficulty: _str(m['difficulty'], 'medium'),
        showingDate: _str(m['showingDate']),
      );
}

class QotdResult {
  final String selectedOptionId;
  final bool isCorrect;
  final DateTime? answeredAt;

  QotdResult({
    required this.selectedOptionId,
    required this.isCorrect,
    required this.answeredAt,
  });

  factory QotdResult.fromMap(Map<String, dynamic> m) => QotdResult(
        selectedOptionId: _str(m['selectedOptionId']),
        isCorrect: _bool(m['isCorrect']),
        answeredAt: _dt(m['answeredAt']),
      );
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

Future<QotdQuestion?> fetchTodayQuestion(String courseId, String subcourseId) async {
  final docId = '${todayDateKey()}__${courseId}__${subcourseId}';
  final doc = await ExamRest.getDoc('app_qotd_daily/$docId').catchError((_) => null);
  if (doc == null) return null;
  return QotdQuestion.fromMap(doc);
}

Future<QotdResult?> fetchQotdResult(String uid, String attemptId) async {
  final doc =
      await ExamRest.getDoc('users/$uid/questionofdata/$attemptId').catchError((_) => null);
  return doc == null ? null : QotdResult.fromMap(doc);
}

Future<QotdSummary> fetchQotdSummary(String uid) async {
  final doc =
      await ExamRest.getDoc('users/$uid/questionofdata/summary').catchError((_) => null);
  return QotdSummary.fromMap(doc ?? {});
}

/// Saves an answer + rolls it into the summary; returns the updated summary.
Future<QotdSummary> answerQotd({
  required String uid,
  required String attemptId,
  required QotdQuestion question,
  required String selectedOptionId,
}) async {
  final isCorrect = selectedOptionId == question.correctOptionId;
  await ExamRest.setDoc('users/$uid/questionofdata/$attemptId', {
    'dateKey': todayDateKey(),
    'courseId': question.courseId,
    'subcourseId': question.subcourseId,
    'selectedOptionId': selectedOptionId,
    'isCorrect': isCorrect,
    'answeredAt': DateTime.now().toUtc(),
  });
  final prior = await fetchQotdSummary(uid);
  final total = prior.totalAttempts + 1;
  final correct = prior.correct + (isCorrect ? 1 : 0);
  final avg = ((correct * 10000 / total) / 100);
  final summary = {
    'totalAttempts': total,
    'correct': correct,
    'averagePercent': avg,
    'updatedAt': DateTime.now().toUtc(),
  };
  await ExamRest.setDoc('users/$uid/questionofdata/summary', summary);
  return QotdSummary.fromMap(summary);
}
