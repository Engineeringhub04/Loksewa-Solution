import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Bookmarks list — mirrors app/bookmarks/index.tsx.
///
/// - Bookmarks live at `users/{uid}/bookmarks`, orderBy createdAt desc.
/// - Slot meter: 15 slots per sub-course (premium = unlimited).
/// - Search covers title + preview + sourceLabel; chips sorted by count desc.
/// - Remove behind a confirm dialog; 'Removed from bookmarks' toast.
///
/// Doc id is `{context}__{safeSegment(refId)}` (see bookmarks.ts).
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

/// Mirrors `safeSegment` in src/core/firebase/services/bookmarks.ts.
String _safeSegment(String value) {
  var s = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 90) s = s.substring(0, 90);
  return s.isEmpty ? 'item' : s;
}

String _bookmarkDocId(Map<String, dynamic> b) =>
    '${b['context'] ?? 'other'}__${_safeSegment((b['refId'] ?? '').toString())}';

class _ContextStyle {
  final IconData icon;
  final Color color;
  const _ContextStyle(this.icon, this.color);
}

const _contextStyles = <String, _ContextStyle>{
  'exam': _ContextStyle(Icons.school_outlined, Color(0xFF2563EB)),
  'read': _ContextStyle(Icons.menu_book_outlined, Color(0xFF0D9488)),
  'practice': _ContextStyle(Icons.fitness_center_outlined, Color(0xFFEA580C)),
  'daily-test': _ContextStyle(Icons.calendar_today_outlined, Color(0xFF7C3AED)),
  'qotd': _ContextStyle(Icons.wb_sunny_outlined, Color(0xFFD97706)),
  'quiz': _ContextStyle(Icons.help_outline, Color(0xFFDB2777)),
  'discussion': _ContextStyle(Icons.forum_outlined, Color(0xFF4F46E5)),
  'article': _ContextStyle(Icons.newspaper_outlined, Color(0xFF059669)),
  'note': _ContextStyle(Icons.description_outlined, Color(0xFF475569)),
  'chapter': _ContextStyle(Icons.layers_outlined, Color(0xFF0891B2)),
  'other': _ContextStyle(Icons.bookmark_outline, Color(0xFF64748B)),
};

_ContextStyle _styleFor(String context) =>
    _contextStyles[context] ?? _contextStyles['other']!;

String _ctxLabel(String context) {
  if (context == 'quiz') return 'Quiz';
  if (context == 'exam') return 'Exam';
  final spaced = context.replaceAll('-', ' ');
  return spaced.isEmpty
      ? spaced
      : spaced[0].toUpperCase() + spaced.substring(1);
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  static const _limit = 15;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _error = false;
  bool _premium = false;
  String? _subcourseId;
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isPremiumActive(Map<String, dynamic>? userDoc) {
    if (userDoc == null || userDoc['isPremium'] != true) return false;
    final expiry = userDoc['premiumExpiryDate'];
    if (expiry == null) return true;
    DateTime? dt;
    if (expiry is DateTime) {
      dt = expiry;
    } else {
      dt = DateTime.tryParse('$expiry');
    }
    return dt == null || dt.isAfter(DateTime.now());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final uid = AuthService.currentUser?.uid;
      if (uid == null) throw Exception('Not signed in.');
      final idToken = await AuthService.getValidIdToken();
      final userDoc =
          await FirestoreRest.getDocument('users/$uid', idToken: idToken)
              .catchError((_) => null);
      final rows = await FirestoreRest.listDocuments('users/$uid/bookmarks',
          idToken: idToken);
      rows.sort((a, b) {
        final da = a['createdAt'];
        final db = b['createdAt'];
        final ta = da is DateTime ? da.millisecondsSinceEpoch : 0;
        final tb = db is DateTime ? db.millisecondsSinceEpoch : 0;
        return tb.compareTo(ta);
      });
      if (!mounted) return;
      setState(() {
        _items = rows;
        _premium = _isPremiumActive(userDoc);
        _subcourseId = userDoc?['subcourseId']?.toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  int get _used {
    if (_subcourseId == null) return _items.length;
    final scoped = _items
        .where((b) => (b['subcourseId'] ?? '').toString() == _subcourseId)
        .length;
    // Docs written before subcourse scoping carry no subcourseId — fall back
    // to the total so the meter never reads 0 on old data.
    return scoped == 0 ? _items.length : scoped;
  }

  List<MapEntry<String, int>> get _chips {
    final counts = <String, int>{};
    for (final b in _items) {
      final c = (b['context'] ?? 'other').toString();
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _items.where((b) {
      if (_filter != 'all' &&
          (b['context'] ?? 'other').toString() != _filter) {
        return false;
      }
      if (q.isEmpty) return true;
      return (b['title'] ?? '').toString().toLowerCase().contains(q) ||
          (b['preview'] ?? '').toString().toLowerCase().contains(q) ||
          (b['sourceLabel'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _confirmRemove(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.bookmark_outline),
        title: const Text('Remove this bookmark?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((b['title'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('You can save it again any time.'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    try {
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument(
          'users/$uid/bookmarks/${_bookmarkDocId(b)}',
          idToken: idToken);
      if (mounted) {
        showToast(context, 'Removed from bookmarks', ToastVariant.info);
        _load();
      }
    } catch (_) {
      if (mounted) {
        showToast(context, 'Something went wrong', ToastVariant.error);
      }
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _savedDate(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return '';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Bookmarks'),
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Loading...'),
                      ],
                    ),
                  )
                : _error && _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Could not load bookmarks.'),
                            const SizedBox(height: 12),
                            ElevatedButton(
                                onPressed: _load,
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _slotMeter(),
                            if (_items.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _searchBar(),
                              const SizedBox(height: 10),
                              _chipRow(),
                            ],
                            const SizedBox(height: 10),
                            if (_visible.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 40),
                                child: Column(
                                  children: [
                                    Icon(
                                      _items.isEmpty
                                          ? Icons.bookmark_outline
                                          : Icons.search_off,
                                      size: 40,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _items.isEmpty
                                          ? 'No bookmarks yet'
                                          : 'Nothing matches your search',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    if (_items.isEmpty) ...[
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Save questions and chapters while studying and they appear here',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 14),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            context.push('/subjects'),
                                        icon: const Icon(Icons.search,
                                            size: 18),
                                        label:
                                            const Text('Browse Subjects'),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            else
                              for (final b in _visible) _bookmarkCard(b),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _slotMeter() {
    final used = _used;
    final left = (_limit - used).clamp(0, _limit);
    final ratio = _premium ? 1.0 : (used / _limit).clamp(0.0, 1.0);
    final fillColor =
        !_premium && left == 0 ? const Color(0xFFFCA5A5) : const Color(0xFF93C5FD);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _premium
              ? const [Color(0xFF0F3D2E), Color(0xFF166534), Color(0xFF15803D)]
              : const [Color(0xFF0B1F51), Color(0xFF153E90), Color(0xFF2257C7)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BOOKMARK SLOTS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Color(0xFF93C5FD)),
                    ),
                    SizedBox(height: 3),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _premium
                          ? Icons.diamond_outlined
                          : Icons.bookmark,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _premium
                          ? 'Premium members can save more'
                          : '$used/$_limit',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Text(
            _premium
                ? 'Unlimited with Premium'
                : '$used of $_limit used',
            style: const TextStyle(
                color: Color(0xD8EFF6FF), fontSize: 12),
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(fillColor),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Text(
                  _premium
                      ? '${_items.length} item(s)'
                      : left == 0
                          ? 'Bookmark slots are full'
                          : '$left left this sub-course',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xD8EFF6FF)),
                ),
              ),
              if (!_premium && left == 0)
                GestureDetector(
                  onTap: () => context.push('/subscription'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0B1F51)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search bookmarks...',
        prefixIcon: const Icon(Icons.search, size: 17),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.cancel, size: 17),
                onPressed: () => setState(() => _query = ''),
              )
            : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) => setState(() => _query = v),
    );
  }

  Widget _chipRow() {
    final chips = _chips;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('all', 'All', _items.length, null),
          for (final e in chips)
            _filterChip(e.key, _ctxLabel(e.key), e.value, _styleFor(e.key)),
        ],
      ),
    );
  }

  Widget _filterChip(
      String value, String label, int count, _ContextStyle? style) {
    final active = _filter == value;
    final accent = style?.color ?? AppColors.navy;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? accent.withValues(alpha: 0.12)
                : Theme.of(context).cardColor,
            border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.4)
                    : Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (style != null) ...[
                Icon(style.icon,
                    size: 13,
                    color: active ? accent : Colors.grey),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.w500,
                    color: active ? accent : Colors.grey.shade700),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: active ? accent : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookmarkCard(Map<String, dynamic> b) {
    final contextKey = (b['context'] ?? 'other').toString();
    final style = _styleFor(contextKey);
    final date = _savedDate(b['createdAt']);
    final badge = (b['sourceLabel'] ?? '').toString().isNotEmpty
        ? (b['sourceLabel'] ?? '').toString()
        : _ctxLabel(contextKey);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            context.push('/bookmarks/${_bookmarkDocId(b)}'),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: style.color,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12)),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(12),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, size: 19, color: style.color),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (b['title'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      if ((b['preview'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            (b['preview'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    onSurface.withValues(alpha: 0.6)),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: style.color
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: style.color),
                            ),
                          ),
                          if (date.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Saved on $date',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: onSurface.withValues(
                                      alpha: 0.45)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 17, color: Colors.grey),
                onPressed: () => _confirmRemove(b),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
