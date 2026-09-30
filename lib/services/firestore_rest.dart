import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'app_config.dart';
import 'server_clock.dart';

/// A single document write for [FirestoreRest.commitWrites] — mirrors the
/// WriteSpec built by setWrite() in firestoreRest.ts.
class FirestoreWrite {
  final String path;
  final Map<String, dynamic> data;
  final bool merge;

  const FirestoreWrite(this.path, this.data, {this.merge = false});
}

/// Firestore REST API client — mirrors src/core/firebase/firestoreRest.ts.
/// Same endpoints, same document paths, no native SDK.
class FirestoreRest {  static String get _base =>
      'https://firestore.googleapis.com/v1/projects/${AppConfig.firebaseProjectId}/databases/(default)/documents';

  static Map<String, String> _headers(String idToken) => {
        'Content-Type': 'application/json',
        if (idToken.isNotEmpty) 'Authorization': 'Bearer $idToken',
      };

  /// Decode a Firestore document's fields into a plain map.
  /// Part B3 contract: preserves the doc-level `updateTime` (top-level
  /// RFC3339 string in the REST response) under the `__updateTime` key —
  /// the double-underscore namespace keeps it clear of real field names.
  @visibleForTesting
  static Map<String, dynamic> decodeDocument(Map<String, dynamic> body) {
    final result = _decodeFields(body);
    final updateTime = body['updateTime'];
    if (updateTime != null) {
      result['__updateTime'] = updateTime.toString();
    }
    return result;
  }

  static Map<String, dynamic> _decodeFields(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};
    return fields.map((k, v) => MapEntry(k, _decodeValue(v)));
  }

  static dynamic _decodeValue(dynamic v) {
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
      return fields.map((k, val) => MapEntry(k, _decodeValue(val)));
    }
    if (v.containsKey('arrayValue')) {
      final values = v['arrayValue']['values'] as List? ?? [];
      return values.map(_decodeValue).toList();
    }
    if (v.containsKey('referenceValue')) return v['referenceValue'];
    return v;
  }

  static Map<String, dynamic> _encodeValue(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
    if (v is _ServerTimestamp) {
      return {'timestampValue': DateTime.now().toUtc().toIso8601String()};
    }
    if (v is List) {
      return {'arrayValue': {'values': v.map(_encodeValue).toList()}};
    }
    if (v is Map) {
      return {
        'mapValue': {
          'fields': (v as Map).map((k, val) => MapEntry('$k', _encodeValue(val)))
        }
      };
    }
    return {'stringValue': '$v'};
  }

  static Future<Map<String, dynamic>?> getDocument(
    String path, {
    String idToken = '',
  }) async {
    final res = await http.get(Uri.parse('$_base/$path'), headers: _headers(idToken));
    ServerClock.updateFromHttpDate(res.headers['date']);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('getDocument $path: ${res.statusCode}');
    return decodeDocument(json.decode(res.body) as Map<String, dynamic>);
  }

  static Future<List<Map<String, dynamic>>> listDocuments(
    String collectionPath, {
    String idToken = '',
    int pageSize = 100,
  }) async {
    final res = await http.get(
      Uri.parse('$_base/$collectionPath?pageSize=$pageSize'),
      headers: _headers(idToken),
    );
    ServerClock.updateFromHttpDate(res.headers['date']);
    if (res.statusCode != 200) throw Exception('listDocuments $collectionPath: ${res.statusCode}');
    final body = json.decode(res.body) as Map<String, dynamic>;
    final docs = body['documents'] as List? ?? [];
    return docs.map((d) {
      final doc = d as Map<String, dynamic>;
      final fields = _decodeFields(doc);
      // Inject the document id from the resource name, like the Expo
      // fromFirestoreDocument() does (docs store no `id` field themselves).
      final name = doc['name'] as String? ?? '';
      final id = name.split('/').last;
      if (id.isNotEmpty) fields['id'] = id;
      return fields;
    }).toList();
  }

  static Future<void> setDocument(
    String path,
    Map<String, dynamic> data, {
    String idToken = '',
    bool merge = false,
  }) async {
    final fields = {
      'fields': (data.map((k, v) => MapEntry(k, _encodeValue(v)))),
    };
    // Firestore REST: PATCH on the document resource with updateMask for merge.
    Uri uri;
    if (merge) {
      final mask = data.keys.map((k) => 'updateMask.fieldPaths=${Uri.encodeComponent(k)}').join('&');
      uri = Uri.parse('$_base/$path?$mask');
    } else {
      uri = Uri.parse('$_base/$path');
    }
    final res = await http.patch(uri, headers: _headers(idToken), body: json.encode(fields));
    ServerClock.updateFromHttpDate(res.headers['date']);
    if (res.statusCode != 200) throw Exception('setDocument $path: ${res.statusCode} ${res.body}');
  }

  static Future<void> deleteDocument(String path, {String idToken = ''}) async {
    final res = await http.delete(Uri.parse('$_base/$path'), headers: _headers(idToken));
    ServerClock.updateFromHttpDate(res.headers['date']);
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw Exception('deleteDocument $path: ${res.statusCode}');
    }
  }

  /// Commits one or more writes atomically via the `:commit` endpoint —
  /// mirrors commitWrites() in firestoreRest.ts (replaces writeBatch).
  /// Sent in chunks of 400 writes per request, exactly like
  /// markAllNotificationsRead on the Expo side.
  static Future<void> commitWrites(List<FirestoreWrite> writes,
      {String idToken = ''}) async {
    const resourceBase =
        'projects/${AppConfig.firebaseProjectId}/databases/(default)/documents';
    for (var i = 0; i < writes.length; i += 400) {
      final end = (i + 400).clamp(0, writes.length);
      final chunk = writes.sublist(i, end);
      final body = {
        'writes': chunk.map((w) {
          final write = <String, dynamic>{
            'update': {
              'name': '$resourceBase/${w.path}',
              'fields': w.data
                  .map((k, v) => MapEntry(k, _encodeValue(v))),
            },
          };
          if (w.merge) {
            write['updateMask'] = {
              'fieldPaths': w.data.keys.toList()
            };
          }
          return write;
        }).toList(),
      };
      final res = await http.post(Uri.parse('$_base:commit'),
          headers: _headers(idToken), body: json.encode(body));
      ServerClock.updateFromHttpDate(res.headers['date']);
      if (res.statusCode != 200) {
        throw Exception('commitWrites: ${res.statusCode} ${res.body}');
      }
    }
  }

  /// Merges [data] into the document at [path] — mirrors updateDocument()
  /// in firestoreRest.ts (a merge write through :commit).
  static Future<void> updateDocument(String path, Map<String, dynamic> data,
      {String idToken = ''}) {
    return commitWrites([FirestoreWrite(path, data, merge: true)],
        idToken: idToken);
  }

  /// Marks a field to be set to the server's commit time (approximated client-side).
  static _ServerTimestamp serverTimestamp() => _ServerTimestamp();
}

class _ServerTimestamp {
  const _ServerTimestamp();
}
