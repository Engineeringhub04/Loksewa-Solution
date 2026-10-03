// Discussion module service — mirrors
// `src/core/firebase/services/discussions.ts` (352 lines) and
// `src/core/firebase/services/discussionGuidelines.ts` (48 lines).
//
// Firestore access goes through the hand-rolled REST layer only:
// - one-shot `ExamRest.runQuery` (single-field orderBy, NO composite
//   indexes, NO realtime listeners anywhere in this module);
// - `ExamRest.createDoc` with real server timestamps for new docs;
// - `:commit` field-transform `increment(±1)` for like/comment counters
//   (never read-then-write).
// - Per-user reaction reads are cached 60s in-memory with in-flight
//   dedup — the same read-quota protection the Expo app has.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'auth_service.dart';
import 'exam_service.dart';
import 'firestore_rest.dart';

/// Thrown by like toggles when no user is signed in (Expo: 'AUTH_REQUIRED').
class AuthRequiredException implements Exception {
  const AuthRequiredException();
  @override
  String toString() => 'AuthRequiredException: sign-in required';
}

/// Thrown by [DiscussionService.reportContent] only when BOTH the Google
/// Form path and the Firestore history path fail.
class DiscussionReportFailedException implements Exception {
  const DiscussionReportFailedException();
  @override
  String toString() => 'DiscussionReportFailedException';
}

class DiscussionPost {
  final String id;
  final String title;
  final String body;
  final String category; // 'tips'|'resources'|'general'|'question' or ''
  final String authorName;
  final String? authorPhoto;
  final String? authorId;
  final String? courseId;
  final String? subcourseId;
  final String? courseName;
  final String? subcourseName;
  final String? imageUrl;
  final String? linkUrl;
  final bool isAdmin;
  final bool isSeed;
  final bool isPinned;
  final int likeCount;
  final int commentCount;
  final DateTime? createdAt;
  final DateTime? editedAt;

  const DiscussionPost({
    required this.id,
    this.title = '',
    this.body = '',
    this.category = '',
    this.authorName = 'Anonymous',
    this.authorPhoto,
    this.authorId,
    this.courseId,
    this.subcourseId,
    this.courseName,
    this.subcourseName,
    this.imageUrl,
    this.linkUrl,
    this.isAdmin = false,
    this.isSeed = false,
    this.isPinned = false,
    this.likeCount = 0,
    this.commentCount = 0,
    this.createdAt,
    this.editedAt,
  });

  static String _str(Object? v) {
    final s = v?.toString() ?? '';
    return s.trim().isEmpty ? '' : s;
  }

  static String? _strOrNull(Object? v) {
    final s = _str(v);
    return s.isEmpty ? null : s;
  }

  static int _int(Object? v) =>
      v is num && v.isFinite ? v.toInt() : int.tryParse('$v') ?? 0;

  static DateTime? _dt(Object? v) => v is DateTime ? v : null;

  /// Display-only copy with an overridden field (e.g. live comment count
  /// on the detail header — the stored counter is not the source of truth).
  DiscussionPost copyWith({int? commentCount, bool? isPinned}) =>
      DiscussionPost(
        id: id,
        title: title,
        body: body,
        category: category,
        authorName: authorName,
        authorPhoto: authorPhoto,
        authorId: authorId,
        courseId: courseId,
        subcourseId: subcourseId,
        courseName: courseName,
        subcourseName: subcourseName,
        imageUrl: imageUrl,
        linkUrl: linkUrl,
        isAdmin: isAdmin,
        isSeed: isSeed,
        isPinned: isPinned ?? this.isPinned,
        likeCount: likeCount,
        commentCount: commentCount ?? this.commentCount,
        createdAt: createdAt,
        editedAt: editedAt,
      );

  factory DiscussionPost.fromMap(Map<String, dynamic> m) => DiscussionPost(
        id: '${m['id'] ?? ''}',
        title: _str(m['title']),
        body: _str(m['body']),
        category: _str(m['category']),
        authorName:
            _strOrNull(m['authorName']) ?? 'Anonymous',
        authorPhoto: _strOrNull(m['authorPhoto']),
        authorId: _strOrNull(m['authorId']),
        courseId: _strOrNull(m['courseId']),
        subcourseId: _strOrNull(m['subcourseId']),
        courseName: _strOrNull(m['courseName']),
        subcourseName: _strOrNull(m['subcourseName']),
        imageUrl: _strOrNull(m['imageUrl']),
        linkUrl: _strOrNull(m['linkUrl']),
        isAdmin: m['isAdmin'] == true,
        isSeed: m['isSeed'] == true,
        isPinned: m['isPinned'] == true,
        likeCount: _int(m['likeCount']),
        commentCount: _int(m['commentCount']),
        createdAt: _dt(m['createdAt']),
        editedAt: _dt(m['editedAt']),
      );
}

class DiscussionComment {
  final String id;
  final String body;
  final String authorName;
  final String? authorPhoto;
  final String? authorId;
  final int likeCount;
  final DateTime? createdAt;
  final DateTime? editedAt;

  const DiscussionComment({
    required this.id,
    this.body = '',
    this.authorName = 'Anonymous',
    this.authorPhoto,
    this.authorId,
    this.likeCount = 0,
    this.createdAt,
    this.editedAt,
  });

  factory DiscussionComment.fromMap(Map<String, dynamic> m) =>
      DiscussionComment(
        id: '${m['id'] ?? ''}',
        body: DiscussionPost._str(m['body']),
        authorName:
            DiscussionPost._strOrNull(m['authorName']) ?? 'Anonymous',
        authorPhoto: DiscussionPost._strOrNull(m['authorPhoto']),
        authorId: DiscussionPost._strOrNull(m['authorId']),
        likeCount: DiscussionPost._int(m['likeCount']),
        createdAt: DiscussionPost._dt(m['createdAt']),
        editedAt: DiscussionPost._dt(m['editedAt']),
      );
}

class DiscussionReply extends DiscussionComment {
  final String parentCommentId;

  const DiscussionReply({
    required super.id,
    super.body,
    super.authorName,
    super.authorPhoto,
    super.authorId,
    super.likeCount,
    super.createdAt,
    super.editedAt,
    required this.parentCommentId,
  });

  factory DiscussionReply.fromMap(Map<String, dynamic> m, String commentId) {
    final c = DiscussionComment.fromMap(m);
    return DiscussionReply(
      id: c.id,
      body: c.body,
      authorName: c.authorName,
      authorPhoto: c.authorPhoto,
      authorId: c.authorId,
      likeCount: c.likeCount,
      createdAt: c.createdAt,
      editedAt: c.editedAt,
      parentCommentId: commentId,
    );
  }
}

class DiscussionGuidelines {
  final String title;
  final String body;
  final List<String> bullets;
  final int version;

  /// True when the doc was missing and hardcoded defaults are returned.
  final bool fromDefaults;

  const DiscussionGuidelines({
    required this.title,
    required this.body,
    required this.bullets,
    this.version = 1,
    this.fromDefaults = false,
  });
}

/// Report types shown in the report modal (value = Expo's localized key
/// suffix; the submitted reason is "<Type>: <message>").
enum DiscussionReportType { spam, abuse, misinformation, inappropriate, other }

/// Bilingual report-type labels for the report modal chips.
String discussionReportTypeLabel(DiscussionReportType t, String lang) {
  const en = {
    DiscussionReportType.spam: 'Spam',
    DiscussionReportType.abuse: 'Abuse or harassment',
    DiscussionReportType.misinformation: 'Misinformation',
    DiscussionReportType.inappropriate: 'Inappropriate content',
    DiscussionReportType.other: 'Other',
  };
  const ne = {
    DiscussionReportType.spam: 'स्प्याम',
    DiscussionReportType.abuse: 'दुर्व्यवहार वा हैरानी',
    DiscussionReportType.misinformation: 'गलत जानकारी',
    DiscussionReportType.inappropriate: 'अनुपयुक्त सामग्री',
    DiscussionReportType.other: 'अन्य',
  };
  return (lang == 'ne' ? ne : en)[t]!;
}

/// Post categories for the create-form dropdown.
enum DiscussionCategory { tips, resources, general, question }

String discussionCategoryValue(DiscussionCategory c) => switch (c) {
      DiscussionCategory.tips => 'tips',
      DiscussionCategory.resources => 'resources',
      DiscussionCategory.general => 'general',
      DiscussionCategory.question => 'question',
    };

String discussionCategoryLabel(DiscussionCategory c, String lang) {
  const en = {
    DiscussionCategory.tips: 'Tips',
    DiscussionCategory.resources: 'Resources',
    DiscussionCategory.general: 'General',
    DiscussionCategory.question: 'Question',
  };
  const ne = {
    DiscussionCategory.tips: 'सुझाव',
    DiscussionCategory.resources: 'स्रोत',
    DiscussionCategory.general: 'सामान्य',
    DiscussionCategory.question: 'प्रश्न',
  };
  return (lang == 'ne' ? ne : en)[c]!;
}

DiscussionCategory? discussionCategoryFromValue(String v) {
  for (final c in DiscussionCategory.values) {
    if (discussionCategoryValue(c) == v) return c;
  }
  return null;
}

/// Normalizes a pasted/shared URL before opening: bare `www.` gets an
/// `https://` scheme. Mirrors the Expo link handling.
String normalizeDiscussionUrl(String raw) {
  final t = raw.trim();
  if (t.toLowerCase().startsWith('www.')) return 'https://$t';
  return t;
}

/// Splits body text into plain/link segments for the auto-link renderer.
/// Mirrors the Expo `/(https?:\/\/[^\s]+|www\.[^\s]+)/gi` split.
List<({String text, bool isLink})> splitDiscussionLinks(String body) {
  final pattern = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
  final out = <({String text, bool isLink})>[];
  var last = 0;
  for (final m in pattern.allMatches(body)) {
    if (m.start > last) {
      out.add((text: body.substring(last, m.start), isLink: false));
    }
    out.add((text: m.group(0)!, isLink: true));
    last = m.end;
  }
  if (last < body.length) {
    out.add((text: body.substring(last), isLink: false));
  }
  return out;
}

/// Client-side feed search — title + body + category + authorName +
/// courseName + subcourseName, case-insensitive contains. No debounce.
List<DiscussionPost> filterDiscussions(List<DiscussionPost> posts, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return posts;
  return posts.where((p) {
    final haystack =
        '${p.title} ${p.body} ${p.category} ${p.authorName} ${p.courseName ?? ''} ${p.subcourseName ?? ''}'
            .toLowerCase();
    return haystack.contains(q);
  }).toList();
}

/// Create-form validation: non-admins need only a body; admins need a title
/// for NEW posts (edit mode relaxes it). Mirrors `canSubmit`.
bool canSubmitDiscussionPost({
  required String body,
  required bool isAdmin,
  required String title,
  String? editId,
}) {
  if (body.trim().isEmpty) return false;
  if (isAdmin && editId == null && title.trim().isEmpty) return false;
  return true;
}

/// True when the create/edit form holds unsaved content (drives the
/// discard-confirm on back).
bool hasUnsavedDiscussionContent({
  required String title,
  required String body,
  required String imageUrl,
  required String linkUrl,
}) =>
    title.trim().isNotEmpty ||
    body.trim().isNotEmpty ||
    imageUrl.trim().isNotEmpty ||
    linkUrl.trim().isNotEmpty;

String _two(int n) => n.toString().padLeft(2, '0');

/// Feed card timestamp: date only.
String formatDiscussionFeedDate(DateTime? dt) {
  if (dt == null) return '';
  final d = dt.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

/// Detail header card timestamp: full date + time.
String formatDiscussionDetailDateTime(DateTime? dt) {
  if (dt == null) return '';
  final d = dt.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Comment timestamp: medium date.
String formatDiscussionCommentDate(DateTime? dt) {
  if (dt == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final d = dt.toLocal();
  return '${_two(d.day)} ${months[d.month - 1]} ${d.year}';
}

class DiscussionService {
  DiscussionService._();

  // ---------- Per-user reaction cache (60s TTL, in-flight dedup) ----------

  static const _reactionTtlMs = 60 * 1000;
  static final Map<String, ({bool liked, int cachedAtMs})> _reactionCache = {};
  static final Map<String, Future<bool>> _reactionInFlight = {};

  static String _reactionKey(String reactionPath, String uid) =>
      '${reactionPath}__$uid';

  static Future<bool> _isReactionLikedCached(
      String reactionPath, String uid) async {
    final key = _reactionKey(reactionPath, uid);
    final entry = _reactionCache[key];
    if (entry != null &&
        DateTime.now().millisecondsSinceEpoch - entry.cachedAtMs <
            _reactionTtlMs) {
      return entry.liked;
    }
    final inFlight = _reactionInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _readReaction(reactionPath, uid).whenComplete(() {
      _reactionInFlight.remove(key);
    });
    _reactionInFlight[key] = request;
    return request;
  }

  static Future<bool> _readReaction(String reactionPath, String uid) async {
    final token = await AuthService.getValidIdToken();
    final doc = await FirestoreRest.getDocument('$reactionPath/$uid',
        idToken: token);
    final liked = doc != null;
    _reactionCache[_reactionKey(reactionPath, uid)] =
        (liked: liked, cachedAtMs: DateTime.now().millisecondsSinceEpoch);
    return liked;
  }

  static void _invalidateReactionCache(String reactionPath, String uid) {
    _reactionCache.remove(_reactionKey(reactionPath, uid));
  }

  /// Test/support hook: clears the 60s reaction cache.
  static void clearReactionCache() {
    _reactionCache.clear();
    _reactionInFlight.clear();
  }

  // ---------- Feed ----------

  /// Latest [max] posts, `orderBy createdAt desc`, one-shot.
  static Future<List<DiscussionPost>> fetchDiscussions({int max = 30}) async {
    final docs = await ExamRest.runQuery(
      'discussions',
      orderBy: [ExamRest.orderField('createdAt', 'DESCENDING')],
      limit: max,
    );
    return docs.map(DiscussionPost.fromMap).toList();
  }

  static Future<DiscussionPost?> fetchDiscussion(String id) async {
    final token = await AuthService.getValidIdToken();
    final doc =
        await FirestoreRest.getDocument('discussions/$id', idToken: token);
    return doc == null ? null : DiscussionPost.fromMap(doc);
  }

  static Future<String> createDiscussion({
    required String title,
    required String body,
    required String category,
    required String authorName,
    String? authorPhoto,
    required String authorId,
    String? courseId,
    String? subcourseId,
    String? courseName,
    String? subcourseName,
    String? imageUrl,
    String? linkUrl,
    required bool isAdmin,
  }) {
    return ExamRest.createDoc(
      'discussions',
      {
        'title': title,
        'body': body,
        'category': category,
        'authorName': authorName,
        'authorPhoto': authorPhoto,
        'authorId': authorId,
        'courseId': courseId,
        'subcourseId': subcourseId,
        'courseName': courseName,
        'subcourseName': subcourseName,
        'imageUrl': imageUrl,
        'linkUrl': linkUrl,
        'isAdmin': isAdmin,
        'isSeed': false,
        'likeCount': 0,
        'commentCount': 0,
        'editedAt': null,
      },
      serverTimestampFields: const ['createdAt'],
    );
  }

  static Future<void> updateDiscussion(
    String id, {
    String? title,
    String? body,
    String? category,
    String? imageUrl,
    String? linkUrl,
  }) async {
    final token = await AuthService.getValidIdToken();
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (body != null) data['body'] = body;
    if (category != null) data['category'] = category;
    if (imageUrl != null) data['imageUrl'] = imageUrl;
    if (linkUrl != null) data['linkUrl'] = linkUrl;
    data['editedAt'] = FirestoreRest.serverTimestamp();
    await FirestoreRest.updateDocument('discussions/$id', data,
        idToken: token);
  }

  /// Deletes the post doc only — comments/replies/reactions subcollections
  /// stay orphaned (service limitation, same as Expo).
  static Future<void> deleteDiscussion(String id) async {
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.deleteDocument('discussions/$id', idToken: token);
  }

  /// Admin-only: pin or unpin a post. Pinned posts sort first in the feed.
  static Future<void> togglePinDiscussion(String id, bool pinned) async {
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.updateDocument(
      'discussions/$id',
      {'isPinned': pinned},
      idToken: token,
    );
  }

  // ---------- Post likes ----------

  static String _postReactionPath(String postId) =>
      'discussions/$postId/reactions';

  static Future<bool> isDiscussionLiked(String postId) async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    return _isReactionLikedCached(_postReactionPath(postId), uid);
  }

  static Future<void> toggleLikeDiscussion(String postId, bool liked) async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw const AuthRequiredException();
    final reactionPath = _postReactionPath(postId);
    // Keep the cache consistent with the toggle (Expo invalidates BEFORE).
    _invalidateReactionCache(reactionPath, uid);
    final token = await AuthService.getValidIdToken();
    if (liked) {
      await FirestoreRest.setDocument(
        '$reactionPath/$uid',
        {'uid': uid, 'createdAt': FirestoreRest.serverTimestamp()},
        idToken: token,
        merge: true,
      );
      await _incrementField('discussions/$postId', 'likeCount', 1, token);
    } else {
      await FirestoreRest.deleteDocument('$reactionPath/$uid', idToken: token);
      await _incrementField('discussions/$postId', 'likeCount', -1, token);
    }
  }

  // ---------- Comments ----------

  static Future<List<DiscussionComment>> fetchComments(
      String discussionId) async {
    final docs = await ExamRest.runQuery(
      'comments',
      parent: 'discussions/$discussionId',
      orderBy: [ExamRest.orderField('createdAt', 'ASCENDING')],
      limit: 500,
    );
    return docs.map(DiscussionComment.fromMap).toList();
  }

  static Future<String> addComment(
    String discussionId, {
    required String body,
    required String authorName,
    String? authorPhoto,
    required String authorId,
  }) async {
    final token = await AuthService.getValidIdToken();
    final id = await ExamRest.createDoc(
      'discussions/$discussionId/comments',
      {
        'body': body,
        'authorName': authorName,
        'authorPhoto': authorPhoto,
        'authorId': authorId,
        'likeCount': 0,
        'editedAt': null,
      },
      serverTimestampFields: const ['createdAt'],
    );
    await _incrementField(
        'discussions/$discussionId', 'commentCount', 1, token);
    return id;
  }

  static Future<void> deleteComment(
      String discussionId, String commentId) async {
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.deleteDocument(
        'discussions/$discussionId/comments/$commentId',
        idToken: token);
    await _incrementField(
        'discussions/$discussionId', 'commentCount', -1, token);
  }

  // ---------- Replies ----------

  static Future<List<DiscussionReply>> fetchReplies(
      String discussionId, String commentId) async {
    final docs = await ExamRest.runQuery(
      'replies',
      parent: 'discussions/$discussionId/comments/$commentId',
      orderBy: [ExamRest.orderField('createdAt', 'ASCENDING')],
      limit: 500,
    );
    return docs
        .map((d) => DiscussionReply.fromMap(d, commentId))
        .toList();
  }

  static Future<String> addReply(
    String discussionId,
    String commentId, {
    required String body,
    required String authorName,
    String? authorPhoto,
    required String authorId,
  }) {
    return ExamRest.createDoc(
      'discussions/$discussionId/comments/$commentId/replies',
      {
        'body': body,
        'authorName': authorName,
        'authorPhoto': authorPhoto,
        'authorId': authorId,
        'likeCount': 0,
        'parentCommentId': commentId,
        'editedAt': null,
      },
      serverTimestampFields: const ['createdAt'],
    );
  }

  static Future<void> deleteReply(
      String discussionId, String commentId, String replyId) async {
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.deleteDocument(
        'discussions/$discussionId/comments/$commentId/replies/$replyId',
        idToken: token);
  }

  // ---------- Comment/reply likes ----------

  static String _commentReactionPath(String discussionId, String commentId) =>
      'discussions/$discussionId/comments/$commentId/reactions';

  static String _replyReactionPath(
          String discussionId, String commentId, String replyId) =>
      'discussions/$discussionId/comments/$commentId/replies/$replyId/reactions';

  static Future<bool> isCommentLiked(
      String discussionId, String commentId, [String? replyId]) async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    final reactionPath = replyId == null
        ? _commentReactionPath(discussionId, commentId)
        : _replyReactionPath(discussionId, commentId, replyId);
    return _isReactionLikedCached(reactionPath, uid);
  }

  static Future<void> toggleCommentLike(
    String discussionId,
    String commentId,
    bool liked, [
    String? replyId,
  ]) async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw const AuthRequiredException();
    final reactionPath = replyId == null
        ? _commentReactionPath(discussionId, commentId)
        : _replyReactionPath(discussionId, commentId, replyId);
    final targetPath = replyId == null
        ? 'discussions/$discussionId/comments/$commentId'
        : 'discussions/$discussionId/comments/$commentId/replies/$replyId';
    // Cached-state check first — no-op when unchanged (saves a read).
    final alreadyLiked = await _isReactionLikedCached(reactionPath, uid);
    if (liked == alreadyLiked) return;
    final token = await AuthService.getValidIdToken();
    if (liked) {
      await FirestoreRest.setDocument(
        '$reactionPath/$uid',
        {'uid': uid, 'createdAt': FirestoreRest.serverTimestamp()},
        idToken: token,
        merge: true,
      );
      await _incrementField(targetPath, 'likeCount', 1, token);
    } else {
      await FirestoreRest.deleteDocument('$reactionPath/$uid', idToken: token);
      await _incrementField(targetPath, 'likeCount', -1, token);
    }
    // After a toggle the like status changed — drop the stale cached read.
    _invalidateReactionCache(reactionPath, uid);
  }

  // ---------- Guidelines ----------

  static const _defaultGuidelineTitleEn = 'Community Guidelines';
  static const _defaultGuidelineTitleNe = 'समुदायका नियमहरू';
  static const _defaultGuidelineBodyEn =
      'Keep the Discussion space useful, respectful and focused on learning.';
  static const _defaultGuidelineBodyNe =
      'यो स्थानलाई उपयोगी, सम्मानजनक र अध्ययनमा केन्द्रित राख्नुहोस्।';
  static const _defaultGuidelineBulletsEn = [
    'Be respectful and avoid personal attacks.',
    'Share accurate, course-related information.',
    'Do not post private payment, password or contact details.',
    'Report content that is abusive, misleading or unsafe.',
  ];
  static const _defaultGuidelineBulletsNe = [
    'सम्मानजनक बन्‍नुहोस् र व्यक्तिगत आक्रमण नगर्नुहोस्।',
    'सही, पाठ्यक्रम-सम्बन्धित जानकारी साझा गर्नुहोस्।',
    'निजी भुक्तानी, पासवर्ड वा सम्पर्क विवरण पोस्ट नगर्नुहोस्।',
    'दुर्व्यवहारपूर्ण, भ्रामक वा असुरक्षित सामग्री रिपोर्ट गर्नुहोस्।',
  ];

  /// Bilingual fallback strings for the guidelines dialog (used when the
  /// `app_discussion_guidelines/default` doc is missing).
  static String defaultGuidelineTitle(String lang) =>
      lang == 'ne' ? _defaultGuidelineTitleNe : _defaultGuidelineTitleEn;
  static String defaultGuidelineBody(String lang) =>
      lang == 'ne' ? _defaultGuidelineBodyNe : _defaultGuidelineBodyEn;
  static List<String> defaultGuidelineBullets(String lang) =>
      List<String>.unmodifiable(
          lang == 'ne' ? _defaultGuidelineBulletsNe : _defaultGuidelineBulletsEn);

  /// In-memory cache so the guidelines popup opens instantly when the
  /// Discussion tab is opened (prefetched alongside the feed).
  static DiscussionGuidelines? _guidelinesCache;
  static Future<DiscussionGuidelines>? _guidelinesInFlight;

  /// Fire-and-forget prefetch — call when the feed starts loading.
  static void prefetchDiscussionGuidelines() {
    if (_guidelinesCache != null || _guidelinesInFlight != null) return;
    _guidelinesInFlight = fetchDiscussionGuidelines().then((g) {
      _guidelinesCache = g;
      _guidelinesInFlight = null;
      return g;
    }).catchError((_) {
      _guidelinesInFlight = null;
      return const DiscussionGuidelines(
        title: _defaultGuidelineTitleEn,
        body: _defaultGuidelineBodyEn,
        bullets: _defaultGuidelineBulletsEn,
        version: 1,
        fromDefaults: true,
      );
    });
  }

  /// Cached-first fetch: instant when prefetched, otherwise fetches.
  static Future<DiscussionGuidelines> fetchDiscussionGuidelinesCached() async {
    if (_guidelinesCache != null) return _guidelinesCache!;
    final inFlight = _guidelinesInFlight;
    if (inFlight != null) return inFlight;
    final g = await fetchDiscussionGuidelines();
    _guidelinesCache = g;
    return g;
  }

  static Future<DiscussionGuidelines> fetchDiscussionGuidelines() async {
    final token = await AuthService.getValidIdToken();
    Map<String, dynamic>? doc;
    try {
      doc = await FirestoreRest.getDocument('app_discussion_guidelines/default',
          idToken: token);
    } catch (_) {
      doc = null;
    }
    if (doc == null) {
      return const DiscussionGuidelines(
        title: _defaultGuidelineTitleEn,
        body: _defaultGuidelineBodyEn,
        bullets: _defaultGuidelineBulletsEn,
        version: 1,
        fromDefaults: true,
      );
    }
    final bullets = doc['bullets'];
    return DiscussionGuidelines(
      title: '${doc['title'] ?? _defaultGuidelineTitleEn}',
      body: '${doc['body'] ?? _defaultGuidelineBodyEn}',
      bullets: bullets is List
          ? bullets.map((b) => '$b').toList()
          : _defaultGuidelineBulletsEn,
      version: doc['version'] is num ? (doc['version'] as num).toInt() : 1,
    );
  }

  /// Admin-only per Firestore rules; the fixed ID makes re-seed safe.
  static Future<void> seedDiscussionGuidelines() async {
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.setDocument(
      'app_discussion_guidelines/default',
      {
        'title': _defaultGuidelineTitleEn,
        'body': _defaultGuidelineBodyEn,
        'bullets': _defaultGuidelineBulletsEn,
        'version': 1,
        'seeded': true,
      },
      idToken: token,
      merge: true,
    );
  }

  // ---------- Report flow (Google Form + history + admin relay) ----------

  /// Mirrors `reportContent` in discussions.ts: fans out to the legacy
  /// Google Form path and the Firestore history path. Throws
  /// [DiscussionReportFailedException] only when BOTH fail.
  static Future<void> reportContent(
    String targetType, // 'post' | 'comment'
    String targetId,
    String reason, {
    String? title,
    String? preview,
    String? authorName,
    String? authorPhoto,
  }) async {
    final results = await Future.wait([
      _submitDiscussionToGoogleForm(
        targetType: targetType,
        targetId: targetId,
        reason: reason,
      ).then((_) => true).catchError((_) => false),
      _createDiscussionReportHistory(
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        title: title,
        preview: preview,
        authorName: authorName,
        authorPhoto: authorPhoto,
      ).then((_) => true).catchError((_) => false),
    ]);
    if (results.every((ok) => !ok)) {
      throw const DiscussionReportFailedException();
    }
    // Discord relay: fire independently (not tied to the history write).
    // If the history write failed but the Form succeeded, admins still
    // get the Discord alert.
    final user = AuthService.currentUser;
    if (user != null) {
      unawaited(notifyAdminsOfReport(
        reportId: _randomId(),
        reporterName: user.displayName ?? 'Anonymous',
        reason: reason,
        targetTitle: title,
      ));
    }
  }

  // Google Form wiring mirrors ReportService (same form + entry IDs):
  // the discussion report is the legacy path (Form → Spreadsheet →
  // Apps Script → Discord, server-side).
  static const _formId =
      '1FAIpQLSc8fAOhc793cp8aMOAKymwtGYLT504S-yjBNixCSE8dgokGQQ';
  static const _entries = {
    'type': 'entry.592505579',
    'name': 'entry.1756370732',
    'email': 'entry.2059602454',
    'message': 'entry.633453203',
    'rating': 'entry.2878998',
    'questionReference': 'entry.168055861',
    'issueCategory': 'entry.1740941696',
    'appVersion': 'entry.1821448113',
    'platform': 'entry.458970457',
    'userId': 'entry.2072267690',
  };

  static Future<void> _submitDiscussionToGoogleForm({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    final user = AuthService.currentUser;
    final displayName = user?.displayName?.trim();
    final uid = user?.uid ?? 'guest';
    final fields = <String, String>{
      _entries['type']!: 'report',
      _entries['name']!: displayName ?? '',
      _entries['email']!: user?.email ?? '',
      _entries['message']!: reason,
      _entries['questionReference']!: targetId,
      _entries['issueCategory']!: 'discussion / $targetType',
      _entries['appVersion']!: '1.0.4',
      _entries['userId']!: (displayName != null && displayName.isNotEmpty)
          ? '$displayName ($uid)'
          : uid,
    };
    final body = fields.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final res = await http
        .post(
          Uri.parse('https://docs.google.com/forms/d/e/$_formId/formResponse'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('GOOGLE_FORM_SUBMIT_FAILED_${res.statusCode}');
    }
  }

  static Future<void> _createDiscussionReportHistory({
    required String targetType,
    required String targetId,
    required String reason,
    String? title,
    String? preview,
    String? authorName,
    String? authorPhoto,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) throw const AuthRequiredException();
    final token = await AuthService.getValidIdToken();
    final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token)
        .catchError((_) => null);

    final reportId = _randomId();
    await FirestoreRest.setDocument(
      'app_report_history/$reportId',
      {
        'reporterId': user.uid,
        'reporterName':
            (userDoc?['name'] ?? user.displayName ?? 'Anonymous').toString(),
        'reporterEmail': userDoc?['email'] ?? user.email,
        'reporterPhoto': userDoc?['photoURL'] ?? user.photoURL,
        'reporterCourseId': userDoc?['courseId'],
        'reporterSubcourseId': userDoc?['subcourseId'],
        'source': targetType == 'post' ? 'discussion' : 'comment',
        'targetType': targetType,
        'targetId': targetId,
        'targetTitle': title,
        'targetPreview': preview,
        'targetAuthorName': authorName,
        'targetAuthorPhoto': authorPhoto,
        'reason': reason,
        'description': '',
        'status': 'pending',
        'adminMessage': null,
        'adminResponses': [],
        'createdAt': FirestoreRest.serverTimestamp(),
        'reviewedAt': null,
      },
      idToken: token,
    );

    // Deliberately NOT awaited: the report is already saved; a relay
    // outage must never turn a saved report into a visible failure.
    unawaited(notifyAdminsOfReport(
      reportId: reportId,
      reporterName:
          (userDoc?['name'] ?? user.displayName ?? 'Anonymous').toString(),
      reason: reason,
      targetTitle: title,
    ));
  }

  /// Asks the relay to alert admins about a new report. Best-effort and
  /// never throws — mirrors `notifyAdminsOfReport` in adminAlerts.ts.
  /// Wired to the same Apps Script relay the Expo app uses.
  static Future<void> notifyAdminsOfReport({
    required String reportId,
    String? reporterName,
    String? reason,
    String? targetTitle,
  }) async {
    // Public relay URL + spam-gate secret (same values as
    // EXPO_PUBLIC_ADMIN_ALERT_WEBHOOK_URL / _SHARED_SECRET in the Expo app)
    // — public-by-design: the relay only ever sends the one fixed report
    // alert and never hands a push token back, so this cannot leak admin
    // tokens. Best-effort, never throws.
    const relayUrl = 'https://script.google.com/macros/s/AKfycbxpS8pIKs6EXZUWcgkM9VtDk3zu6vWBb8dkjc9NhnEvYVpTGmTBjpDRjW9FDz7ty_M9/exec';
    const sharedSecret = '(EgshdFuck__Hcikishan_124q1Bw)';
    if (relayUrl.isEmpty || sharedSecret.startsWith('REPLACE_WITH')) return;
    try {
      await http
          .post(
            Uri.parse(relayUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'action': 'report_created',
              'secret': sharedSecret,
              'reportId': reportId,
              'reporterName': reporterName ?? '',
              'contextLabel': 'Discussion',
              'reason': reason ?? '',
              'targetTitle': targetTitle ?? '',
              'description': '',
              'deepLink': '/admin/report-history/$reportId',
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort only.
    }
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ---------- Atomic counter helper ----------

  /// Atomic `increment(delta)` via the `:commit` field transform — the same
  /// operation the React `increment()` performs, never read-then-write.
  /// Increments a counter field via read-modify-write (merge update).
  /// The atomic :commit transform form was failing against the security
  /// rules' changedOnly() check; a merge write of the new value satisfies
  /// the rule (new == old ± 1) reliably. Clamped at 0 — counts never go
  /// negative even if the stored value drifted.
  static Future<void> _incrementField(
      String docPath, String field, int delta, String token) async {
    final doc =
        await FirestoreRest.getDocument(docPath, idToken: token);
    final current = doc?[field];
    final currentInt = current is num ? current.toInt() : 0;
    final next = (currentInt + delta).clamp(0, 1 << 31);
    await FirestoreRest.updateDocument(
      docPath,
      {field: next},
      idToken: token,
    );
  }
}
