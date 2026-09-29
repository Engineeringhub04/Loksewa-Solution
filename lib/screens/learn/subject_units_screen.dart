import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';

/// Subject units — exact port of app/subjects/units/[subjectId].tsx.
/// Units are grouped into selectable tracks ("All" + one chip per unit, with a
/// direct-chapters track first when present); the 'all' view shows expandable
/// unit cards, a selected track shows flat chapter cards.
class SubjectUnitsScreen extends StatefulWidget {
  final String subjectId;
  const SubjectUnitsScreen({super.key, required this.subjectId});

  @override
  State<SubjectUnitsScreen> createState() => _SubjectUnitsScreenState();
}

class _SubjectUnitsScreenState extends State<SubjectUnitsScreen>
    with SingleTickerProviderStateMixin {
  late Future<_UnitPage> _future;

  /// Cached page for the full-screen overlays (sheet + gate) that live
  /// above the whole page, outside the FutureBuilder.
  _UnitPage? _page;

  String _selectedTrack = 'all';
  String? _expandedUnit;
  Map<String, dynamic>? _premiumChapter;
  Map<String, dynamic>? _sheetChapter;

  /// Entry/exit animation for the Practice/Read/Theory bottom sheet:
  /// slides up from the bottom + fades in, ~280ms easeOutCubic
  /// (same pattern as the chapter page).
  late final AnimationController _sheetController;
  late final Animation<double> _sheetFade;
  late final Animation<Offset> _sheetSlide;

  /// Scroll controller + per-unit keys for the accordion auto-scroll:
  /// expanding a unit scrolls it to the top of the viewport.
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _unitKeys = {};

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    final curved = CurvedAnimation(
      parent: _sheetController,
      curve: Curves.easeOutCubic,
    );
    _sheetFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curved);
    _future = _trackPage(_load());
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _page = null;
      _future = _trackPage(_load());
    });
  }

  /// Wires the loaded page into [_page] for the full-screen overlays.
  /// Errors are swallowed here — the FutureBuilder below renders them.
  Future<_UnitPage> _trackPage(Future<_UnitPage> future) {
    future.then((d) {
      if (mounted) setState(() => _page = d);
    }, onError: (_) {});
    return future;
  }

  Future<_UnitPage> _load() async {
    final user = AuthService.currentUser;
    final token = await AuthService.getValidIdToken();
    var courseId = 'civil-engineering';
    var subcourseId = 'civil-assistant-sub-engineer';
    bool isPremium = false;
    if (user != null) {
      try {
        final doc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
        courseId = (doc?['courseId'] as String?) ?? courseId;
        subcourseId = (doc?['subcourseId'] as String?) ?? subcourseId;
        // Canonical premium check (mirrors React's hasActivePremium):
        // isPremium + premiumExpiryDate / isPro / premiumUntil /
        // subscriptionStatus, not the local `pro` field heuristic.
        isPremium =
            UserProfile.fromMap(user.uid, doc ?? {}).hasActivePremium;
      } catch (_) {}
    }
    String subjectName = widget.subjectId;
    bool subjectPro = false;
    // The subject-name lookup, the units+chapters fetch and the direct-chapter
    // fetch are independent — run all three concurrently instead of one after
    // another.
    Future<Map<String, dynamic>?> safeDoc(String path) async {
      try {
        return await FirestoreRest.getDocument(path, idToken: token);
      } catch (_) {
        return null;
      }
    }

    Future<List<Map<String, dynamic>>> safeDirectChapters() async {
      try {
        return await fetchSubjectChaptersWithProgress(
            courseId, subcourseId, widget.subjectId, user?.uid);
      } catch (_) {
        // Technical Subject normally has no direct chapters — tolerated.
        return <Map<String, dynamic>>[];
      }
    }

    final results = await Future.wait([
      safeDoc('app_subjects_details/${widget.subjectId}'),
      fetchSubjectUnitsWithChapters(
          courseId, subcourseId, widget.subjectId, user?.uid),
      safeDirectChapters(),
    ]);
    final doc = results[0] as Map<String, dynamic>?;
    final units = results[1] as List<Map<String, dynamic>>;
    final directChapters = results[2] as List<Map<String, dynamic>>;
    subjectName = (doc?['name'] as String?) ?? subjectName;
    subjectPro = doc?['pro'] == true;
    final tracks = <_Track>[];
    if (directChapters.isNotEmpty) {
      tracks.add(_Track(
          id: 'direct-chapters',
          label: subjectName,
          unit: null,
          chapters: directChapters,
          direct: true));
    }
    for (final u in units) {
      tracks.add(_Track(
        id: '${u['id']}',
        label:
            "${u['order']}. ${u['name'] ?? u['nameNe']}", // global lang = en
        unit: u,
        chapters: (u['chapters'] as List? ?? []).cast<Map<String, dynamic>>(),
        direct: false,
      ));
    }
    return _UnitPage(
      subjectName: subjectName,
      subjectPro: subjectPro,
      courseId: courseId,
      subcourseId: subcourseId,
      tracks: tracks,
      isPremium: isPremium,
    );
  }

  // Units screen uses the global app language (en default in React):
  // title = name || nameNe, subtitle = nameNe || name.
  String _chapterTitle(Map<String, dynamic> c) =>
      '${c['name'] ?? c['nameNe']}';

  String _chapterAlt(Map<String, dynamic> c) =>
      '${c['nameNe'] ?? c['name']}';

  static int _pct(Map<String, dynamic> c) =>
      (((c['progress'] as Map?)?['percentage']) as num?)?.toInt() ?? 0;

  void _onChapterTap(Map<String, dynamic> c, _UnitPage d) {
    final locked = c['pro'] == true && !d.isPremium;
    if (locked) {
      setState(() => _premiumChapter = c);
      return;
    }
    setState(() => _sheetChapter = c);
    _sheetController.forward(from: 0);
  }

  /// Slides/fades the mode sheet back down, then removes it from the tree.
  void _dismissSheet() {
    final c = _sheetChapter;
    if (c == null) return;
    _sheetController.reverse().then((_) {
      if (!mounted) return;
      // Don't close a sheet that was re-opened while this one animated out.
      if (identical(_sheetChapter, c)) setState(() => _sheetChapter = null);
    });
  }

  void _goMode(String route, Map<String, dynamic> c, _UnitPage d) {
    setState(() => _sheetChapter = null);
    final params = {
      'courseId': d.courseId,
      'subcourseId': d.subcourseId,
      'subjectId': widget.subjectId,
      'chapterId': '${c['id']}',
      'unitId': '${c['unitId'] ?? ''}',
      'subjectName': d.subjectName,
      'chapterName': _chapterTitle(c),
      'subjectPro': d.subjectPro ? 'true' : 'false',
      'chapterPro': (c['pro'] == true) ? 'true' : 'false',
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.push('$route?$qs');
  }

  List<Map<String, dynamic>> _allChapters(_UnitPage d) =>
      d.tracks.expand((t) => t.chapters).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              const SubpageHeader(title: 'Units'),
              Expanded(
                child: FutureBuilder<_UnitPage>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const PreloadingWidget(
                        tinted: false,
                        label: 'Loading Units...',
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Failed to load units.'),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _reload,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    final d = snap.data!;
                    final all = _allChapters(d);
                    if (all.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text(
                                      'No units or chapters found for this subject.',
                                      style: TextStyle(color: Colors.grey))),
                            ),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async => _reload(),
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 4, bottom: 8),
                                    child: Text(
                                      d.subjectName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  _summaryCard(context, d, all),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ChipsHeaderDelegate(
                              child: _trackChips(context, d, all),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: _listHeader(context, d, all),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 48),
                              child: _selectedTrack == 'all'
                                  ? Column(
                                      children: d.tracks
                                          .map((t) =>
                                              _unitCard(context, t, d))
                                          .toList(),
                                    )
                                  : Column(
                                      children: _selectedTrackChapters(d)
                                          .asMap()
                                          .entries
                                          .map((e) => _StaggeredReveal(
                                                index: e.key,
                                                animationKey: _selectedTrack,
                                                child: _chapterCard(
                                                    context, e.value, d),
                                              ))
                                          .toList(),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Full-screen overlays above everything (including the header),
          // so the dim barrier never leaves white slivers at the
          // header's curved corners — same as the chapter page.
          if (_page != null && _premiumChapter != null)
            _gateDialog(context, _premiumChapter!),
          if (_page != null && _sheetChapter != null)
            _modeSheet(context, _page!, _sheetChapter!),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _selectedTrackChapters(_UnitPage d) {
    if (_selectedTrack == 'all') return _allChapters(d);
    final t = d.tracks.where((t) => t.id == _selectedTrack);
    return t.isEmpty ? [] : t.first.chapters;
  }

  void _selectTrack(String id) {
    setState(() {
      _selectedTrack = id;
      _expandedUnit = null;
    });
  }

  void _toggleUnit(String id) {
    final expanding = _expandedUnit != id;
    setState(() {
      _expandedUnit = expanding ? id : null;
    });
    if (expanding) {
      // Scroll after this frame's layout settles (collapse + expand both
      // land in the same setState), so the opened unit's header lands at
      // the top of the viewport.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToUnit(id));
    }
  }

  /// Smooth-scrolls the expanded unit card so its header sits just below
  /// the pinned 56px track-chip bar. Works for any unit.
  void _scrollToUnit(String id) {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx = _unitKeys[id]?.currentContext;
    if (ctx == null) return;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final viewport = RenderAbstractViewport.of(renderObject);
    final reveal = viewport.getOffsetToReveal(renderObject, 0.0);
    final position = _scrollController.position;
    final target = (reveal.offset - 64).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - _scrollController.offset).abs() > 1) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------------------------------------------------------- summary card
  Widget _summaryCard(
      BuildContext context, _UnitPage d, List<Map<String, dynamic>> all) {
    final total = all.length;
    final avg = total == 0
        ? 0
        : (all.map(_pct).reduce((a, b) => a + b) / total).round();
    final complete =
        all.where((c) => (c['progress'] as Map?)?['completed'] == true).length;
    final inProgress = all
        .where((c) =>
            _pct(c) > 0 && (c['progress'] as Map?)?['completed'] != true)
        .length;
    final premium = all.where((c) => c['pro'] == true).length;
    // The glow bubbles intentionally bleed past the card edges and are
    // clipped by the outer ClipRRect along the 28px rounded border: the
    // inner Stack uses Clip.none so the bubbles are never cut with a hard
    // straight edge inside the content padding (the old "D" sticker look).
    // The shadow lives on the wrapper OUTSIDE the clip so it isn't cut away.
    return Container(
      constraints: const BoxConstraints(minHeight: 242),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x470C2D91), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF153DB8), Color(0xFF0C2D91)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -100,
                right: -40,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        const Color(0xFF5A8CFF).withValues(alpha: 0.22),
                  ),
                ),
              ),
              Positioned(
                bottom: -125,
                left: -70,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        const Color(0xFF00002D).withValues(alpha: 0.16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.subjectName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total Topics',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ProgressRing(progress: avg),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SummaryStat(
                      icon: Icons.layers,
                      label: 'Total Topics',
                      value: total,
                      accent: const Color(0xFFC7D9FF)),
                  _SummaryStat(
                      icon: Icons.check_circle_outline,
                      label: 'Complete',
                      value: complete,
                      accent: const Color(0xFFB8E1FF)),
                  _SummaryStat(
                      icon: Icons.show_chart,
                      label: 'In Progress',
                      value: inProgress,
                      accent: const Color(0xFFC8F2DC)),
                  _SummaryStat(
                      icon: Icons.diamond_outlined,
                      label: 'Premium',
                      value: premium,
                      accent: const Color(0xFFFFD2A6)),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => showToast(
                        context,
                        'This feature will be available in the next update.',
                        ToastVariant.info),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 9),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.analytics,
                              size: 17, color: Color(0xFF0C2D91)),
                          SizedBox(width: 8),
                          Text('View Practice Analytics',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0C2D91))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
  ),
);
  }

  // ---------------------------------------------------------- track chips
  Widget _trackChips(
      BuildContext context, _UnitPage d, List<Map<String, dynamic>> all) {
    final chips = <Widget>[
      _trackChip(context, 'all', 'All', all.length),
      ...d.tracks
          .map((t) => _trackChip(context, t.id, t.label, t.chapters.length)),
    ];
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context).dividerColor, width: 1)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: chips),
      ),
    );
  }

  Widget _trackChip(
      BuildContext context, String id, String label, int count) {
    final active = _selectedTrack == id;
    final scheme = Theme.of(context).colorScheme;
    final palette = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? palette.primary : scheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _selectTrack(id),
          child: Container(
            constraints:
                const BoxConstraints(minHeight: 40, maxWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active
                      ? palette.primary
                      : Theme.of(context).dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: active
                              ? Colors.white
                              : scheme.onSurface.withValues(alpha: 0.6)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 7),
                Text('$count',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: active
                            ? const Color(0xFFFFD2A6)
                            : scheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- list header
  Widget _listHeader(
      BuildContext context, _UnitPage d, List<Map<String, dynamic>> all) {
    final total = all.length;
    final avg = total == 0
        ? 0
        : (all.map(_pct).reduce((a, b) => a + b) / total).round();
    final title = _selectedTrack == 'all'
        ? 'Units'
        : d.tracks
            .firstWhere((t) => t.id == _selectedTrack,
                orElse: () => d.tracks.first)
            .label;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$avg% Progress',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
                maxLines: 1,
                textAlign: TextAlign.right),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- unit card
  Widget _unitCard(BuildContext context, _Track t, _UnitPage d) {
    final isExpanded = _expandedUnit == t.id;
    final palette = ExpoPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isUnitPurchased = t.unit?['pro'] == true && d.isPremium;
    final headerBg = t.direct
        ? Theme.of(context).cardColor
        : dark
            ? palette.primary.withValues(alpha: 0.09)
            : const Color(0xFFF2F6FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: _unitKeys.putIfAbsent(t.id, () => GlobalKey()),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x140C2D91), blurRadius: 9, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Material(
              color: headerBg,
              child: InkWell(
                onTap: () => _toggleUnit(t.id),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 84),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: dark
                              ? palette.primary.withValues(alpha: 0.16)
                              : const Color(0xFFDCE7FF),
                        ),
                        child: Icon(
                            t.direct
                                ? Icons.photo_album_outlined
                                : Icons.layers_outlined,
                            size: 20,
                            color: palette.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.label,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('${t.chapters.length} chapters',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                      if (t.unit?['pro'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isUnitPurchased
                                ? (dark
                                    ? palette.success.withValues(alpha: 0.19)
                                    : const Color(0xFFD1FAE5))
                                : (dark
                                    ? palette.warning.withValues(alpha: 0.19)
                                    : const Color(0xFFFFF0DE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  isUnitPurchased
                                      ? Icons.check_circle
                                      : Icons.lock,
                                  size: 12,
                                  color: isUnitPurchased
                                      ? palette.success
                                      : palette.warning),
                              const SizedBox(width: 4),
                              Text(
                                  isUnitPurchased
                                      ? 'Purchased (Active)'
                                      : 'Premium',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isUnitPurchased
                                          ? palette.success
                                          : palette.warning)),
                            ],
                          ),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)),
                    ],
                  ),
                ),
              ),
            ),
            if (isExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(11, 12, 11, 11),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                      top: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1)),
                ),
                child: Column(
                  children: t.chapters
                      .asMap()
                      .entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _StaggeredReveal(
                              index: e.key,
                              animationKey: '${t.id}-$isExpanded',
                              child: _chapterCard(context, e.value, d),
                            ),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- chapter card
  Widget _chapterCard(
      BuildContext context, Map<String, dynamic> c, _UnitPage d) {
    final progress = _pct(c);
    final isLocked = c['pro'] == true && !d.isPremium;
    final isPurchased = c['pro'] == true && d.isPremium;
    final palette = ExpoPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final softPrimary = dark
        ? palette.primary.withValues(alpha: 0.16)
        : const Color(0xFFE7EEFF);
    final softSuccess = dark
        ? palette.success.withValues(alpha: 0.16)
        : const Color(0xFFE7F7F0);
    final softWarning = dark
        ? palette.warning.withValues(alpha: 0.19)
        : const Color(0xFFFFF0DE);
    final order = '${c['order']}'.padLeft(2, '0');
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _onChapterTap(c, d),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color:
                    Theme.of(context).dividerColor.withValues(alpha: 0.6)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0D0F172A),
                  blurRadius: 8,
                  offset: Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isLocked
                          ? softWarning
                          : isPurchased
                              ? softSuccess
                              : softPrimary,
                    ),
                    child: Text(order,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isLocked
                                ? palette.warning
                                : isPurchased
                                    ? palette.success
                                    : palette.primary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_chapterTitle(c),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        Text(_chapterAlt(c),
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (c['pro'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isPurchased ? softSuccess : softWarning,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              isPurchased
                                  ? Icons.check_circle
                                  : Icons.lock,
                              size: 12,
                              color: isPurchased
                                  ? palette.success
                                  : palette.warning),
                          const SizedBox(width: 4),
                          Text(
                              isPurchased ? 'Purchased (Active)' : 'Premium',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPurchased
                                      ? palette.success
                                      : palette.warning)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _ModeTag(
                      label: 'P', bg: softPrimary, fg: palette.primary),
                  const SizedBox(width: 5),
                  _ModeTag(
                      label: 'R', bg: softSuccess, fg: palette.success),
                  const SizedBox(width: 5),
                  _ModeTag(
                      label: 'T', bg: softWarning, fg: palette.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$progress% Progress',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6))),
                        const SizedBox(height: 5),
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: progress >= 100
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(isLocked ? Icons.lock_outline : Icons.chevron_right,
                      size: 18,
                      color: isLocked
                          ? palette.warning
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- premium gate
  Widget _gateDialog(BuildContext context, Map<String, dynamic> c) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 40, color: Color(0xFF9A3412)),
              const SizedBox(height: 12),
              const Text('Premium Chapter',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'An active subscription is required to access this chapter.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(_chapterTitle(c),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white),
                  onPressed: () {
                    setState(() => _premiumChapter = null);
                    context.push('/subscription');
                  },
                  child: const Text('Go To Subscription Plan'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: () => setState(() => _premiumChapter = null),
                  child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- bottom sheet
  // Same entry/exit animation as the chapter page: 280ms slide-up + fade,
  // full-screen dim barrier above everything.
  Widget _modeSheet(
      BuildContext context, _UnitPage d, Map<String, dynamic> c) {
    // 0x6B == 107, so fading the alpha 0 -> 0.42 reproduces the old constant
    // barrier Color(0x6B0F172A) at full entry.
    return AnimatedBuilder(
      animation: _sheetController,
      builder: (context, _) => GestureDetector(
        onTap: _dismissSheet,
        child: Container(
          color: const Color(0xFF0F172A)
              .withValues(alpha: 0.42 * _sheetFade.value),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionalTranslation(
              translation: _sheetSlide.value,
              child: Opacity(
                opacity: _sheetFade.value,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(_chapterTitle(c),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Free',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6))),
                    const SizedBox(height: 18),
                    _ModeButton(
                      icon: Icons.play_circle_outline,
                      label: 'Practice Mode',
                      primary: true,
                      onTap: () => _goMode('/subjects/practice', c, d),
                    ),
                    const SizedBox(height: 9),
                    _ModeButton(
                      icon: Icons.book_outlined,
                      label: 'Read Mode',
                      onTap: () => _goMode('/subjects/read', c, d),
                    ),
                    const SizedBox(height: 9),
                    _ModeButton(
                      icon: Icons.school_outlined,
                      label: 'Theory Mode',
                      onTap: () => _goMode('/subjects/theory', c, d),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
  ),
);
  }
}

// ---------------------------------------------------------------------------
// Sticky track-chip header
// ---------------------------------------------------------------------------
class _ChipsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ChipsHeaderDelegate({required this.child});

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  double get maxExtent => 56;

  @override
  double get minExtent => 56;

  @override
  bool shouldRebuild(covariant _ChipsHeaderDelegate oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Staggered reveal (opacity + translateY 12->0, 260/300ms, delay index*55)
// ---------------------------------------------------------------------------
class _StaggeredReveal extends StatefulWidget {
  final int index;
  final String animationKey;
  final Widget child;
  const _StaggeredReveal(
      {required this.index, required this.animationKey, required this.child});

  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant _StaggeredReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationKey != widget.animationKey) {
      _c.reset();
      _run();
    }
  }

  void _run() {
    Future.delayed(Duration(milliseconds: widget.index * 55), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position: Tween<Offset>(
                begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------
class _ProgressRing extends StatelessWidget {
  final int progress;
  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 78,
      child: CustomPaint(
        painter: _RingPainter(progress / 100, const Color(0xFFFFD2A6)),
        child: Center(
          child: Text('$progress%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  _RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawCircle(size.center(Offset.zero), 35, paint);
    paint.color = color;
    canvas.drawArc(
        Rect.fromCircle(center: size.center(Offset.zero), radius: 35),
        -3.14159265 / 2,
        2 * 3.14159265 * value.clamp(0.0, 1.0),
        false,
        paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color accent;

  const _SummaryStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: accent,
          ),
          child: Icon(icon, size: 15, color: const Color(0xFF0C2D91)),
        ),
        const SizedBox(height: 4),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 10),
            textAlign: TextAlign.center),
      ],
    );
  }
}

class _ModeTag extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _ModeTag(
      {required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: bg,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _ModeButton(
      {required this.icon,
      required this.label,
      this.primary = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: primary ? Colors.white : palette.primary),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: primary ? Colors.white : palette.primary)),
      ],
    );
    if (primary) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onTap,
          child: content,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        child: content,
      ),
    );
  }
}

class _Track {
  final String id;
  final String label;
  final Map<String, dynamic>? unit;
  final List<Map<String, dynamic>> chapters;
  final bool direct;

  const _Track(
      {required this.id,
      required this.label,
      required this.unit,
      required this.chapters,
      required this.direct});
}

class _UnitPage {
  final String subjectName;
  final bool subjectPro;
  final String courseId;
  final String subcourseId;
  final List<_Track> tracks;
  final bool isPremium;

  const _UnitPage({
    required this.subjectName,
    required this.subjectPro,
    required this.courseId,
    required this.subcourseId,
    required this.tracks,
    required this.isPremium,
  });
}
