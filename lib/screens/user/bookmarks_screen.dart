import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/trash_icon.dart';
import 'bookmark_tracks.dart';
import 'bookmark_remove_dialog.dart';

/// Bookmarks list — mirrors `app/bookmarks/index.tsx` exactly.
///
/// - Bookmarks live at `users/{uid}/bookmarks`, orderBy `createdAt` desc.
/// - Slot meter: 15 slots per sub-course (premium = unlimited).
/// - Search covers title + preview + sourceLabel; chips only for contexts the
///   user has, sorted by count desc.
/// - Tapping a card opens `/bookmarks/[id]` (the saved snapshot, never the
///   source flow). Remove sits behind a confirm dialog.
///
/// Design tokens (radius / type / spacing) mirror
/// `src/core/theme/tokens.ts` via [ExpoPalette]/[ExpoRadius]/[ExpoType].
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

class _BookmarksScreenState extends State<BookmarksScreen> {
  static const _limit = 15;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _error = false;
  bool _premium = false;
  String? _subcourseId;
  String _query = '';
  String _filter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
        final ta = _millis(a['createdAt']);
        final tb = _millis(b['createdAt']);
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

  int _millis(dynamic raw) {
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
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

  /// Filter chips: one per track present in the bookmarks (auto-created from
  /// the actual sources), sorted by count desc. Only tracks the user has
  /// appear, plus "All".
  List<MapEntry<String, int>> get _chips => buildTrackChips(_items);

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _items.where((b) {
      if (_filter != 'all' && bookmarkTrackKey(b) != _filter) {
        return false;
      }
      if (q.isEmpty) return true;
      return (b['title'] ?? '').toString().toLowerCase().contains(q) ||
          (b['preview'] ?? '').toString().toLowerCase().contains(q) ||
          (b['sourceLabel'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _confirmRemove(Map<String, dynamic> b) async {
    final ok = await AppModalShell.show<bool>(
      context: context,
      builder: (c) => BookmarkRemoveDialog(item: b),
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
        showToast(
            context,
            AppLanguage.tr('Removed from bookmarks', 'बुकमार्कबाट हटाइयो'),
            ToastVariant.info);
        _load();
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
            ToastVariant.error);
      }
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _savedDate(dynamic raw) {
    final ms = _millis(raw);
    if (ms == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Bookmarks', 'बुकमार्कहरू')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                    hint: AppLanguage.tr(
                        'Fetching your content', 'सामग्री ल्याउँदै'),
                  )
                : _error && _items.isEmpty
                    ? _errorBody(pal)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: pal.primary,
                        child: _listBody(pal),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody(ExpoPalette pal) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 44, color: pal.textDisabled),
          const SizedBox(height: 12),
          Text(AppLanguage.tr('Could not load bookmarks.', 'बुकमार्क लोड हुन सकेन।'),
              style:
                  TextStyle(fontSize: 14, color: pal.textPrimary)),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _load,
              child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास'))),
        ],
      ),
    );
  }

  Widget _listBody(ExpoPalette pal) {
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // List header: slot meter + (search + chips when there are items).
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _slotMeter(pal),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 14),
              _searchBar(pal),
              const SizedBox(height: 10),
              _chipRow(pal),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          _emptyBody(pal)
        else
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _Entrance(
              delayMs: (i < 8 ? i : 8) * 45,
              child: _BookmarkCard(
                item: visible[i],
                pal: pal,
                date: _savedDate(visible[i]['createdAt']),
                onTap: () =>
                    context.push('/bookmarks/${_bookmarkDocId(visible[i])}'),
                onRemove: () => _confirmRemove(visible[i]),
              ),
            ),
          ],
      ],
    );
  }

  /// Slot meter — the 15-per-sub-course cap made visible before it bites.
  Widget _slotMeter(ExpoPalette pal) {
    final used = _used;
    final left = (_limit - used).clamp(0, _limit);
    final ratio = _premium ? 1.0 : (used / _limit).clamp(0.0, 1.0);
    final full = !_premium && left == 0;
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(0x1A),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr('Bookmark slots', 'बुकमार्क स्लट')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Color(0xFF93C5FD),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _premium
                          ? AppLanguage.tr('Unlimited with Premium',
                              'प्रिमियममा असीमित')
                          : AppLanguage.tr('$used of $_limit used',
                              '$_limit मध्ये $used प्रयोग'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xD2EFF6FF),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withAlpha(0x29),
                  border: Border.all(
                    color: Colors.white.withAlpha(0x38),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _premium ? Icons.diamond_outlined : Icons.bookmark,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _premium
                          ? AppLanguage.tr('Premium members can save more',
                              'प्रिमियम सदस्यले थप सुरक्षित गर्न सक्छन्')
                          : '$used/$_limit',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 7,
              color: Colors.white.withAlpha(0x2E),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: full
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFF93C5FD),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Text(
                  _premium
                      ? AppLanguage.tr('${_items.length} item(s)',
                          '${_items.length} वस्तु')
                      : full
                          ? AppLanguage.tr('Bookmark slots are full',
                              'बुकमार्क स्लट भरियो')
                          : AppLanguage.tr('$left left this sub-course',
                              'यो सब-कोर्समा $left बाँकी'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xC2FFFFFF),
                  ),
                ),
              ),
              if (full)
                GestureDetector(
                  onTap: () => context.push('/subscription'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      AppLanguage.tr('Upgrade', 'अपग्रेड'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B1F51),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchBar(ExpoPalette pal) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.search_outlined, size: 17, color: pal.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(fontSize: 14, color: pal.textPrimary),
              decoration: InputDecoration(
                hintText: AppLanguage.tr(
                    'Search bookmarks...', 'बुकमार्क खोज्नुहोस्...'),
                hintStyle:
                    TextStyle(fontSize: 14, color: pal.textDisabled),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _searchCtrl.clear();
              }),
              child: Icon(Icons.cancel,
                  size: 17, color: pal.textDisabled),
            ),
        ],
      ),
    );
  }

  Widget _chipRow(ExpoPalette pal) {
    final dark =
        Theme.of(context).brightness == Brightness.dark;
    final chips = _chips;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
              pal, dark, 'all', AppLanguage.tr('All', 'सबै'), _items.length, null),
          for (final e in chips) ...[
            const SizedBox(width: 7),
            _filterChip(
                pal,
                dark,
                e.key,
                AppLanguage.tr(bookmarkTracks[e.key]?.label ?? e.key,
                    bookmarkTracks[e.key]?.labelNe ?? e.key),
                e.value,
                bookmarkTracks[e.key]),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(ExpoPalette pal, bool dark, String value, String label,
      int count, BookmarkTrack? track) {
    final active = _filter == value;
    final accent = track?.color ?? pal.primary;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active
              ? accent.withAlpha(dark ? 0x2E : 0x18)
              : pal.surface,
          border: Border.all(
            color: active
                ? accent.withAlpha(dark ? 0x88 : 0x55)
                : pal.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track != null) ...[
              Icon(track.icon,
                  size: 13,
                  color: active ? accent : pal.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? accent : pal.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: active ? accent : pal.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBody(ExpoPalette pal) {
    final searching = _items.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.primary.withAlpha(0x14),
            ),
            child: Icon(
              searching ? Icons.search_outlined : Icons.bookmark_outline,
              size: 32,
              color: pal.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            searching
                ? AppLanguage.tr(
                    'Nothing matches your search', 'खोजसँग मिल्ने केही छैन')
                : AppLanguage.tr('No bookmarks yet',
                    'अहिलेसम्म कुनै बुकमार्क छैन'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: pal.textPrimary),
          ),
          if (!searching) ...[
            const SizedBox(height: 8),
            Text(
              AppLanguage.tr(
                  'Save questions and chapters while studying and they appear here',
                  'पढ्दै गर्दा प्रश्न र च्याप्टर बुकमार्क गर्नुहोस्, यहाँ देखिन्छन्'),
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: pal.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/subjects'),
                icon: const Icon(Icons.search, size: 18),
                label: Text(AppLanguage.tr('Browse Subjects', 'विषयहरू ब्राउज गर्नुहोस्'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: pal.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One saved item. The left rail is tinted per context so the list reads as
/// grouped even when the filter is "All".
class _BookmarkCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final ExpoPalette pal;
  final String date;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _BookmarkCard({
    required this.item,
    required this.pal,
    required this.date,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_BookmarkCard> createState() => _BookmarkCardState();
}

class _BookmarkCardState extends State<_BookmarkCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final b = widget.item;
    final track = bookmarkTrackOf(b);
    final dark =
        Theme.of(context).brightness == Brightness.dark;
    // React: the bookmarked content's own label wins verbatim; the track
    // label is only the fallback.
    final sourceLabelRaw = (b['sourceLabel'] ?? '').toString();
    final badge = sourceLabelRaw.isNotEmpty
        ? sourceLabelRaw
        : AppLanguage.tr(track.label, track.labelNe);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        decoration: BoxDecoration(
          color: pal.surface,
          border: Border.all(
            color: _pressed
                ? track.color.withAlpha(0x66)
                : pal.border,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(0x0F),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: track.color),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(17, 13, 13, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: track.color
                          .withAlpha(dark ? 0x26 : 0x14),
                    ),
                    child: Icon(track.icon,
                        size: 19, color: track.color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (b['title'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: pal.textPrimary,
                            height: 20 / 14,
                          ),
                        ),
                        if ((b['preview'] ?? '')
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            (b['preview'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.textSecondary,
                              height: 16 / 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                constraints: const BoxConstraints(
                                    maxWidth: double.infinity),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(999),
                                  color: track.color.withAlpha(
                                      dark ? 0x22 : 0x12),
                                ),
                                child: Text(
                                  badge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: track.color,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.date.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  AppLanguage.tr('Saved on ${widget.date}',
                                      '${widget.date} मा सुरक्षित'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: pal.textDisabled),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: TrashIcon(size: 17, color: pal.textDisabled),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Staggered entrance: fade + slide down (mirrors `FadeInDown`).
class _Entrance extends StatefulWidget {
  final int delayMs;
  final Widget child;
  const _Entrance({required this.delayMs, required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _go = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _go ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _go ? Offset.zero : const Offset(0, -0.1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
