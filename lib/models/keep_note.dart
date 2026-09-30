/// Keep Notes data model — 100% local, never sent to Firestore.
///
/// A note has a plain-text [title] (always rendered bold) and a body stored
/// as styled runs: `[{'t': 'hello', 'b': true}, {'t': ' world'}]`.
/// Run flags: `b` = bold, `u` = underline, `i` = italic. Runs without flags
/// are plain text.
class KeepTextRun {
  final String text;
  final bool bold;
  final bool underline;
  final bool italic;

  const KeepTextRun({
    required this.text,
    this.bold = false,
    this.underline = false,
    this.italic = false,
  });

  factory KeepTextRun.fromJson(Map<String, dynamic> j) => KeepTextRun(
        text: '${j['t'] ?? ''}',
        bold: j['b'] == true,
        underline: j['u'] == true,
        italic: j['i'] == true,
      );

  Map<String, dynamic> toJson() => {
        't': text,
        if (bold) 'b': true,
        if (underline) 'u': true,
        if (italic) 'i': true,
      };
}

class KeepNote {
  final String id;
  String title;
  List<KeepTextRun> runs;
  bool pinned;
  int createdAt;
  int updatedAt;

  KeepNote({
    required this.id,
    this.title = '',
    List<KeepTextRun>? runs,
    this.pinned = false,
    int? createdAt,
    int? updatedAt,
  })  : runs = runs ?? const [],
        createdAt = createdAt ?? 0,
        updatedAt = updatedAt ?? 0;

  /// Plain body text (styles stripped) — for list previews and search.
  String get plainBody => runs.map((r) => r.text).join();

  bool get isEmpty =>
      title.trim().isEmpty && plainBody.trim().isEmpty;

  factory KeepNote.fromJson(Map<String, dynamic> j) {
    final rawRuns = j['runs'];
    return KeepNote(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      runs: rawRuns is List
          ? rawRuns
              .whereType<Map<String, dynamic>>()
              .map(KeepTextRun.fromJson)
              .toList()
          : const [],
      pinned: j['pinned'] == true,
      createdAt: _asInt(j['createdAt']),
      updatedAt: _asInt(j['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'runs': runs.map((r) => r.toJson()).toList(),
        'pinned': pinned,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static String newId() {
    final now = DateTime.now();
    return '${now.millisecondsSinceEpoch}-${now.microsecond % 100000}';
  }

  /// List ordering: pinned notes first (newest first), then the rest
  /// (newest first). Pure — used by the list screen and unit-tested.
  static List<KeepNote> sortedForList(List<KeepNote> notes) {
    final pinned = notes.where((n) => n.pinned).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final others = notes.where((n) => !n.pinned).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [...pinned, ...others];
  }
}
