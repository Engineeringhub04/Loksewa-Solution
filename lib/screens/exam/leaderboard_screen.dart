import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/main_leaderboard.dart';
import '../../widgets/disk_cached_image.dart';
import '../../widgets/leaderboard_podium.dart';
import '../../widgets/preloading.dart';

/// Main leaderboard — mirrors app/leaderboard.tsx + components/leaderboard/Podium.tsx.
///
/// The screen is FIXED to its own dark palette (like React) and does NOT follow
/// the app theme: the podium is a designed surface and re-tinting the medals
/// per theme would wreck their contrast. Everything below the podium is glass
/// on the same dark gradient.
///
/// Layout: pinned podium (top 3, display order 2nd/1st/3rd), "your standing"
/// card, then the scrolling ranks inside a rounded darker sheet.
/// The iOS-style [PreloadingWidget] is kept as the loader (per user request).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

// ---------- fixed dark palette (Podium.tsx) ----------
const _bgTop = Color(0xFF12275C);
const _bgBottom = Color(0xFF1D4ED8);
const _text = Color(0xFFFFFFFF);
const _textDim = Color(0xB8FFFFFF); // rgba(255,255,255,0.72)
const _meAccent = Color(0xFF34D399); // PLACE_THEMES[1].ring


/// Cached page-1 snapshot for one subcourse (10-minute TTL).
class _BoardPage {
  final List<MainLeaderboardRow> rows;
  final bool hasMore;
  final MainLeaderboardRow? lastRow;
  final DateTime fetchedAt;
  _BoardPage(this.rows, this.hasMore, this.lastRow, this.fetchedAt);
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<MainLeaderboardRow> _rows = const [];
  bool _loading = true;
  bool _hardRefreshing = false;
  bool _noCourse = false;
  String? _error;
  String _courseSubtitle = '';
  String _uid = '';
  String _subcourseId = '';

  // --- Pagination state -------------------------------------------------
  // Page 1 loads up-front (with every photo precached before the reveal so
  // the first paint is complete); further pages load as the user scrolls.
  // When the composite index is missing we fall back to the legacy
  // full-fetch path and pagination is disabled.
  final ScrollController _scroll = ScrollController();
  static const int _pageSize = mainLeaderboardPageSize;
  bool _paginated = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  MainLeaderboardRow? _lastRow;
  final Set<String> _seenUids = {};
  int? _myRank;
  MainLeaderboardRow? _myRow;

  // 10-minute in-memory board cache (page 1), mirroring React's boardCache.
  // Empty results are never cached. Cleared on publish / manual refresh.
  static final Map<String, _BoardPage> _boardCache = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollNearBottom);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScrollNearBottom() {
    if (!_paginated || _loadingMore || !_hasMore || _loading) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  static void invalidateBoardCache(String subcourseId) {
    _boardCache.remove(subcourseId);
  }

  /// [hard] = header refresh button: the body steps aside for the preloader.
  /// [pull] = pull-to-refresh: the list stays put under the native spinner.
  ///
  /// Load sequence (mirrors app/leaderboard.tsx):
  /// 1. ensure my public row exists (brand-new users get the 50pt signup
  ///    bonus doc here — must run BEFORE publish so the bonus survives);
  /// 2. publish-before-read (throttled to once per 5 min) so my own row is
  ///    current before the board is read;
  /// 3. fetch page 1 (15 rows, server-ordered) — or the legacy full fetch
  ///    when the composite index is missing;
  /// 4. precache every visible photo BEFORE the reveal (no blank-then-pop);
  /// 5. compute my exact rank (page index, else a count query) and mirror it
  ///    into users/{uid}.stats.rank.
  Future<void> _load({bool hard = false, bool pull = false}) async {
    if (!pull) {
      setState(() {
        if (hard) {
          _hardRefreshing = true;
        } else {
          _loading = true;
        }
        _error = null;
        _noCourse = false;
      });
    }
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      final profile = uid.isEmpty ? null : await fetchUserProfile(uid);
      final subcourseId = profile?.subcourseId ?? '';
      final courseId = profile?.courseId ?? '';
      if (uid.isEmpty || subcourseId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _noCourse = true;
          _loading = false;
          _hardRefreshing = false;
        });
        return;
      }
      _uid = uid;
      _subcourseId = subcourseId;
      final p = profile!;
      final displayName =
          p.name.trim().isEmpty ? 'Anonymous' : p.name.trim();
      // Header subtitle: subcourseName ?? courseName (best-effort).
      var subtitle = '';
      try {
        if (courseId.isNotEmpty) {
          final c =
              await ExamRest.getDoc('app_courses/$courseId').catchError((_) => null);
          final sc = await ExamRest.getDoc(
                  'app_courses/$courseId/subcourses/$subcourseId')
              .catchError((_) => null);
          final scName =
              ((sc?['name'] ?? sc?['nameNe']) as String?)?.trim() ?? '';
          final cName = ((c?['name'] ?? c?['nameNe']) as String?)?.trim() ?? '';
          subtitle = scName.isNotEmpty ? scName : cName;
        }
      } catch (_) {}

      // 10-minute page-1 cache (never caches empty); skipped on hard/pull.
      _BoardPage? cached;
      if (!hard && !pull) {
        cached = _boardCache[subcourseId];
        if (cached != null &&
            DateTime.now().difference(cached.fetchedAt).inMinutes >= 10) {
          cached = null;
          _boardCache.remove(subcourseId);
        }
      }

      // 1. Ensure my row (creates the 50pt bonus doc for new users).
      var myRow = await ensureMainLeaderboardRow(
        uid: uid,
        courseId: courseId,
        subcourseId: subcourseId,
        name: displayName,
        photoURL: p.photoURL,
        isPro: p.isPro,
      );

      // 2. Publish-before-read (throttled); a fresh publish busts the cache.
      if (shouldPublishMainLeaderboardScore(uid, subcourseId)) {
        final publishedRow = await publishMainLeaderboardScore(
          uid: uid,
          courseId: courseId,
          subcourseId: subcourseId,
          name: displayName,
          photoURL: p.photoURL,
          isPro: p.isPro,
        );
        if (publishedRow != null) {
          myRow = publishedRow;
          invalidateBoardCache(subcourseId);
          cached = null;
        }
      }

      // 3. Page 1.
      List<MainLeaderboardRow> page;
      bool hasMore;
      MainLeaderboardRow? lastRow;
      bool paginated;
      if (cached != null && cached.rows.isNotEmpty) {
        page = cached.rows;
        hasMore = cached.hasMore;
        lastRow = cached.lastRow;
        paginated = true;
      } else {
        try {
          final fetched =
              await fetchMainLeaderboardPage(subcourseId, limit: _pageSize);
          paginated = true;
          // One row per uid; the better duplicate sorts first server-side.
          final seen = <String>{};
          page = fetched.where((r) => seen.add(r.uid)).toList();
          hasMore = page.length == _pageSize;
          lastRow = page.isEmpty ? null : page.last;
          if (page.isNotEmpty) {
            _boardCache[subcourseId] =
                _BoardPage(page, hasMore, lastRow, DateTime.now());
          }
        } on MissingIndexException {
          // Composite index not created yet — legacy full fetch, no pages.
          page = await fetchMainLeaderboard(subcourseId);
          paginated = false;
          hasMore = false;
          lastRow = null;
        }
      }

      // 4. Every visible photo fully loaded before the board reveals.
      await Future.wait(
        page.map((r) => DiskCachedImage.warm(r.photoURL ?? '')),
      ).timeout(const Duration(seconds: 6), onTimeout: () => <void>[]);

      // 5. Exact rank: page index when visible, else a count query (~1 read).
      int? myRank;
      final idx = page.indexWhere((r) => r.uid == uid);
      if (idx >= 0) {
        myRank = idx + 1;
        myRow = page[idx];
      } else if (myRow != null) {
        try {
          myRank = await countMainLeaderboardRank(subcourseId, myRow.points);
        } catch (_) {
          myRank = null;
        }
      }
      if (myRank != null && myRank > 0) {
        await writeUserStatsRank(uid, myRank);
      }

      if (!mounted) return;
      setState(() {
        _rows = page;
        _paginated = paginated;
        _hasMore = hasMore;
        _lastRow = lastRow;
        _seenUids
          ..clear()
          ..addAll(page.map((r) => r.uid));
        _myRank = myRank;
        _myRow = myRow;
        _courseSubtitle = subtitle;
        _loading = false;
        _hardRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t load the leaderboard right now. Please try again.';
        _loading = false;
        _hardRefreshing = false;
      });
    }
  }

  /// Infinite scroll: append the next page (uid-deduped). Stops silently on
  /// any error — the board stays usable with what it has.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastRow == null || _subcourseId.isEmpty) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      final fetched = await fetchMainLeaderboardPage(_subcourseId,
          limit: _pageSize, startAfter: _lastRow);
      final fresh = fetched.where((r) => !_seenUids.contains(r.uid)).toList();
      // Re-sort the seam defensively (server already orders points DESC).
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, ...fresh];
        _seenUids.addAll(fresh.map((r) => r.uid));
        _lastRow = _rows.isEmpty ? null : _rows.last;
        _hasMore = fetched.length == _pageSize;
        _loadingMore = false;
      });
      // My row may have scrolled into view — refresh the exact rank.
      final idx = _rows.indexWhere((r) => r.uid == uid);
      if (idx >= 0 && _myRank != idx + 1 && uid.isNotEmpty) {
        _myRank = idx + 1;
        _myRow = _rows[idx];
        await writeUserStatsRank(uid, _myRank!);
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
    }
  }

  /// "2h 15m" / "45m" / "0m" — mirrors formatStudyTime in leaderboard.tsx.
  String _formatTime(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '0m';
  }

  /// Trims a trailing ".0" — mirrors formatPercent in leaderboard.tsx.
  String _formatPercent(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()}%'
        : '${rounded.toStringAsFixed(1)}%';
  }

  /// Maps a board row to the shared podium entry (same UI as exam ranking).
  PodiumEntry _toPodiumEntry(MainLeaderboardRow row) => PodiumEntry(
        name: row.name,
        photoURL: row.photoURL,
        isPro: row.isPro,
        stat: _formatPercent(row.percent),
        subStat: '${row.points} pts',
      );

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.currentUser?.uid ?? '';
    final myIndex = uid.isEmpty ? -1 : _rows.indexWhere((r) => r.uid == uid);
    final pointsToNext = myIndex > 0
        ? (_rows[myIndex - 1].points - _rows[myIndex].points)
            .clamp(0, 1 << 30)
        : null;
    final showLoader = _loading || _hardRefreshing;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 10),
            _header(),
            Expanded(
              child: showLoader
                  ? const PreloadingWidget(
                      tinted: false,
                      label: 'Loading Leaderboard...',
                    )
                  : _noCourse
                      ? _noCourseBody()
                      : _error != null
                          ? _errorBody()
                          : _boardBody(uid, _myRow, _myRank, pointsToNext),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          _glassIconButton(
            icon: Icons.arrow_back,
            size: 20,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Leaderboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _text),
                ),
                if (_courseSubtitle.isNotEmpty)
                  Text(
                    _courseSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: _textDim),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _glassIconButton(
            icon: Icons.refresh,
            size: 19,
            onPressed: () {
              if (!_hardRefreshing && !_loading) _load(hard: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: const Color(0x29FFFFFF), // rgba(255,255,255,0.16)
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: size, color: _text),
        ),
      ),
    );
  }

  Widget _noCourseBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 48, color: _textDim),
            const SizedBox(height: 12),
            const Text(
              'Choose a course to see the leaderboard',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _text),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _text,
                side: const BorderSide(color: _textDim),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: _text)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: () => _load(), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _boardBody(String uid, MainLeaderboardRow? myRow, int? myRank,
      int? pointsToNext) {
    final rest = _rows.length > 3 ? _rows.sublist(3) : <MainLeaderboardRow>[];
    return Column(
      children: [
        // FIXED podium — pinned above the list so the top three stay visible
        // while the rankings scroll underneath. Shared widget with the
        // exam ranking screen: same UI, only the data differs.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: LeaderboardPodium(
            entries: [
              _rows.length > 1 ? _toPodiumEntry(_rows[1]) : null,
              _rows.isNotEmpty ? _toPodiumEntry(_rows[0]) : null,
              _rows.length > 2 ? _toPodiumEntry(_rows[2]) : null,
            ],
          ),
        ),
        // The rounded darker sheet confines scrolling to this region.
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0x47081436), // rgba(8,20,54,0.28)
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: RefreshIndicator.adaptive(
              onRefresh: () {
                // Pull-to-refresh = explicit ask for fresh numbers: force the
                // next publish through instead of waiting out the throttle.
                if (_uid.isNotEmpty && _subcourseId.isNotEmpty) {
                  resetMainLeaderboardThrottle(_uid, _subcourseId);
                }
                return _load(pull: true);
              },
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, MediaQuery.of(context).padding.bottom + 40),
                children: [
                  _myCard(myRow, myRank, pointsToNext),
                  const SizedBox(height: 14),
                  const Text('Rankings',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _text)),
                  const SizedBox(height: 10),
                  if (rest.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFFFFF),
                        border: Border.all(
                            color: const Color(0x2EFFFFFF)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.emoji_events_outlined,
                              size: 20, color: _textDim),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No one has scored here yet — be the first',
                              style: TextStyle(
                                  fontSize: 13, color: _textDim),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(rest.length, (i) {
                      final row = rest[i];
                      final isMe = row.uid == uid;
                      return _rankRow(row, i + 4, isMe);
                    }),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _textDim),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Your standing card — deliberately richer than the exam version: a green
  /// rail, a circular rank, three stats, and the gap to the next rank.
  /// [myRank] is the exact rank (page index or count query); null = unranked.
  Widget _myCard(
      MainLeaderboardRow? myRow, int? myRank, int? pointsToNext) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x7334D399)), // 0.45 green
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0x4D34D399), // rgba(52,211,153,0.30)
                      Color(0x0D34D399), // rgba(52,211,153,0.05)
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: _meAccent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: myRow == null
                  ? const Row(
                      children: [
                        Icon(Icons.rocket_launch_outlined,
                            size: 22, color: _textDim),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text('Unranked',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _text)),
                              SizedBox(height: 2),
                              Text(
                                'Not ranked yet — your first activity puts you on the board',
                                style: TextStyle(
                                    fontSize: 12, color: _textDim),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _meAccent, width: 2),
                                color: const Color(0x1FFFFFFF),
                              ),
                              alignment: Alignment.center,
                              child: Text('${myRank ?? '–'}',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _text)),
                            ),
                            const SizedBox(width: 10),
                            _avatar(myRow.photoURL, myRow.name, 44),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Your standing',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _textDim)),
                                  _nameWithTick(myRow.name, myRow.isPro,
                                      fontSize: 16, color: _text),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0x1AFFFFFF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              _myStat(
                                  _formatPercent(myRow.percent),
                                  'Percentile',
                                  valueColor: _meAccent),
                              _vDivider(),
                              _myStat('${myRow.points}', 'Points'),
                              _vDivider(),
                              _myStat(
                                  _formatTime(myRow.usageSeconds),
                                  'Study time'),
                            ],
                          ),
                        ),
                        if (pointsToNext != null && myRank != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.trending_up,
                                  size: 14, color: _meAccent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '$pointsToNext pts → #${myRank - 1}',
                                  style: const TextStyle(
                                      fontSize: 12, color: _textDim),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myStat(String value, String label, {Color valueColor = _text}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: valueColor)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: _textDim)),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, color: const Color(0x40FFFFFF));
  }

  Widget _rankRow(MainLeaderboardRow row, int position, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0x2E34D399) // rgba(52,211,153,0.18)
            : const Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isMe ? _meAccent : const Color(0x2EFFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isMe
                  ? const Color(0x4D34D399)
                  : const Color(0x24FFFFFF),
            ),
            alignment: Alignment.center,
            child: Text('$position',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _text)),
          ),
          const SizedBox(width: 10),
          _avatar(row.photoURL, row.name, 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _nameWithTick(
                    isMe ? '${row.name} (You)' : row.name, row.isPro,
                    fontSize: 14, color: _text),
                const SizedBox(height: 2),
                Text(
                  '${row.points} pts · ${_formatTime(row.usageSeconds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: _textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: isMe
                  ? const Color(0x5934D399)
                  : const Color(0x29FFFFFF),
            ),
            child: Text(_formatPercent(row.percent),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _text)),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? photoURL, String name, double size) {
    final inner = size - 12;
    Widget face;
    if (photoURL != null && photoURL.isNotEmpty) {
      face = ClipOval(
        child: DiskCachedImage(
          url: photoURL,
          width: inner,
          height: inner,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsFace(name, inner),
        ),
      );
    } else {
      face = _initialsFace(name, inner);
    }
    return SizedBox(width: size, height: size, child: face);
  }

  Widget _initialsFace(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x24FFFFFF),
      ),
      alignment: Alignment.center,
      child: Text(_initials(name),
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] +
            (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }

  /// Name with the verified tick beside it (Facebook style), like every screen.
  Widget _nameWithTick(String name, bool isPro,
      {double fontSize = 14, Color color = _text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, color: color)),
        ),
        if (isPro)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.verified,
                size: 14, color: Color(0xFF3B82F6)),
          ),
      ],
    );
  }
}

