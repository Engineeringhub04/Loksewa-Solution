import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/exam_service.dart';
import '../../widgets/premium_gate_dialog.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';

/// Subject chapters — exact port of app/subjects/chapters/[subjectId].tsx.
/// Summary gradient card + progress ring + chapter cards with P/R/T tags;
/// tapping a chapter opens the Practice / Read / Theory bottom sheet.
class SubjectChaptersScreen extends StatefulWidget {
  final String subjectId;
  const SubjectChaptersScreen({super.key, required this.subjectId});

  @override
  State<SubjectChaptersScreen> createState() =>
      _SubjectChaptersScreenState();
}

class _SubjectChaptersScreenState extends State<SubjectChaptersScreen>
    with SingleTickerProviderStateMixin {
  late Future<_ChapterPage> _future;
  bool _ne = true; // language toggle: NE default, EN alternate (React)
  Map<String, dynamic>? _premiumChapter;
  Map<String, dynamic>? _sheetChapter;

  /// Cached page data so the mode sheet / premium gate overlays can render
  /// full-screen (above the header) outside the FutureBuilder.
  _ChapterPage? _page;

  /// Entry/exit animation for the Practice/Read/Theory bottom sheet:
  /// slides up from the bottom + fades in, ~280ms easeOutCubic.
  late final AnimationController _sheetController;
  late final Animation<double> _sheetFade;
  late final Animation<Offset> _sheetSlide;

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
  Future<_ChapterPage> _trackPage(Future<_ChapterPage> future) {
    future.then((d) {
      if (mounted) setState(() => _page = d);
    }, onError: (_) {});
    return future;
  }

  Future<_ChapterPage> _load() async {
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
        isPremium = _hasActivePremium(doc);
      } catch (_) {}
    }
    String subjectName = 'Subject';
    bool subjectPro = false;
    // The subject-name lookup and the chapter+progress fetch are independent —
    // run them concurrently instead of one after another.
    Future<Map<String, dynamic>?> safeDoc(String path) async {
      try {
        return await FirestoreRest.getDocument(path, idToken: token);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      safeDoc('app_subjects_details/${widget.subjectId}'),
      fetchSubjectChaptersWithProgress(
          courseId, subcourseId, widget.subjectId, user?.uid),
    ]);
    final doc = results[0] as Map<String, dynamic>?;
    final chapters = results[1] as List<Map<String, dynamic>>;
    subjectName = (doc?['name'] as String?) ?? subjectName;
    subjectPro = doc?['pro'] == true;
    return _ChapterPage(
      subjectName: subjectName,
      subjectPro: subjectPro,
      courseId: courseId,
      subcourseId: subcourseId,
      chapters: chapters,
      isPremium: isPremium,
    );
  }

  static bool _hasActivePremium(Map<String, dynamic>? userDoc) {
    final pro = userDoc?['pro'];
    if (pro is bool) return pro;
    if (pro is Map) {
      final active = pro['active'];
      if (active is bool) return active;
      final exp = pro['expiresAt'];
      if (exp is String) {
        final dt = DateTime.tryParse(exp);
        if (dt != null) return dt.isAfter(DateTime.now());
      }
    }
    return false;
  }

  String _chapterName(Map<String, dynamic> c) =>
      _ne ? '${c['nameNe'] ?? c['name']}' : '${c['name'] ?? c['nameNe']}';

  String _chapterNameAlt(Map<String, dynamic> c) =>
      _ne ? '${c['name']}' : '${c['nameNe'] ?? c['name']}';

  void _onChapterTap(Map<String, dynamic> c, _ChapterPage d) {
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

  void _goMode(String route, Map<String, dynamic> c, _ChapterPage d) {
    setState(() => _sheetChapter = null);
    final params = {
      'courseId': d.courseId,
      'subcourseId': d.subcourseId,
      'subjectId': widget.subjectId,
      'chapterId': '${c['id']}',
      'unitId': '',
      'subjectName': d.subjectName,
      'chapterName': _chapterName(c),
      'subjectPro': d.subjectPro ? 'true' : 'false',
      'chapterPro': (c['pro'] == true) ? 'true' : 'false',
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    // Refresh progress when coming back — the just-finished practice
    // changes the % shown on this page.
    context.push('$route?$qs').then((_) {
      if (mounted) _reload();
    });
  }

  /// True while the premium gate or the mode bottom-sheet is on screen.
  /// The phone back button closes those instead of leaving the page.
  bool get _overlayOpen => _premiumChapter != null || _sheetChapter != null;

  @override
  Widget build(BuildContext context) {
    // The overlays sit ABOVE the whole page (header included) so the dim
    // barrier covers the full screen — otherwise the header's 26px bottom
    // curve would reveal bright white slivers against the dimmed content
    // in light mode.
    return PopScope(
      canPop: !_overlayOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_sheetChapter != null) {
            _dismissSheet();
          } else if (_premiumChapter != null) {
            setState(() => _premiumChapter = null);
          }
        }
      },
      child: Scaffold(
          body: Stack(
          children: [
            Column(
              children: [
                SubpageHeader(
                  title: 'Chapter',
                  actions: [
                    _LanguagePill(
                      ne: _ne,
                      onToggle: () => setState(() => _ne = !_ne),
                    ),
                  ],
                ),
                Expanded(
                  child: FutureBuilder<_ChapterPage>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const PreloadingWidget(
                          tinted: false,
                          label: 'Loading Chapters...',
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Failed to load chapters.'),
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
                      return RefreshIndicator.adaptive(
                        onRefresh: () async => _reload(),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 4, bottom: 8),
                              child: Text(
                                d.subjectName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            SyllabusEntrance(
                              delayMs: 0,
                              child: ChapterSummaryCard(
                                subjectId: widget.subjectId,
                                subjectName: d.subjectName,
                                chapters: d.chapters,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _listHeader(context, d),
                            const SizedBox(height: 8),
                            if (d.chapters.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                    child: Text(
                                        'No chapters found for this subject.',
                                        style: TextStyle(
                                            color: Colors.grey))),
                              )
                            else
                              ...d.chapters.asMap().entries.map((e) =>
                                  SyllabusEntrance(
                                    delayMs:
                                        (e.key > 8 ? 8 : e.key) * 60,
                                    child: _chapterCard(
                                        context, e.value, d),
                                  )),
                            const SizedBox(height: 32),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_page != null && _premiumChapter != null)
              _gateDialog(context, _page!, _premiumChapter!),
            if (_page != null && _sheetChapter != null)
              _modeSheet(context, _page!, _sheetChapter!),
          ],
        ),
      ),
    );
  }


  Widget _listHeader(BuildContext context, _ChapterPage d) {
    final total = d.chapters.length;
    final avg = total == 0
        ? 0
        : (d.chapters.map(_pct).reduce((a, b) => a + b) / total).round();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Chapter',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text('$avg% Progress',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6))),
      ],
    );
  }

  Widget _chapterCard(
      BuildContext context, Map<String, dynamic> c, _ChapterPage d) {
    final progress = _pct(c);
    final isLocked = c['pro'] == true && !d.isPremium;
    final isPurchased = c['pro'] == true && d.isPremium;
    final order = '${c['order']}'.padLeft(2, '0');
    final cardColor = Theme.of(context).cardColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _onChapterTap(c, d),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.6)),
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
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isLocked
                            ? const Color(0xFFFFF0DE)
                            : isPurchased
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFE7EEFF),
                      ),
                      child: Text(order,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isLocked
                                  ? const Color(0xFFB45309)
                                  : isPurchased
                                      ? const Color(0xFF047857)
                                      : const Color(0xFF0C2D91))),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_chapterName(c),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          Text(_chapterNameAlt(c),
                              style: TextStyle(
                                  fontSize: 10,
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
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isPurchased
                              ? const Color(0xFFD1FAE5)
                              : const Color(0xFFFFF0DE),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isPurchased
                                    ? Icons.check_circle
                                    : Icons.lock,
                                size: 11,
                                color: isPurchased
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFB45309)),
                            const SizedBox(width: 4),
                            Text(
                                isPurchased
                                    ? 'Purchased (Active)'
                                    : 'Premium',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isPurchased
                                        ? const Color(0xFF047857)
                                        : const Color(0xFFB45309))),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const _ModeTag(
                        label: 'P',
                        bg: Color(0xFFE7EEFF),
                        fg: Color(0xFF0C2D91)),
                    const SizedBox(width: 8),
                    const _ModeTag(
                        label: 'R',
                        bg: Color(0xFFE7F7F0),
                        fg: Color(0xFF047857)),
                    const SizedBox(width: 8),
                    const _ModeTag(
                        label: 'T',
                        bg: Color(0xFFFFF0DE),
                        fg: Color(0xFFB45309)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$progress% Progress',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6))),
                          const SizedBox(height: 4),
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
                                  borderRadius:
                                      BorderRadius.circular(3),
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
                    Icon(
                        isLocked
                            ? Icons.lock_outline
                            : Icons.chevron_right,
                        size: 16,
                        color: isLocked
                            ? const Color(0xFFB45309)
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
      ),
    );
  }

  Widget _gateDialog(
      BuildContext context, _ChapterPage d, Map<String, dynamic> c) {
    return PremiumGateDialog(
      itemName: _chapterName(c),
      title: AppLanguage.tr('Premium Chapter', 'प्रिमियम अध्याय'),
      message: AppLanguage.tr(
          'An active subscription is required to access this chapter.',
          'यो अध्याय खोल्न सक्रिय सदस्यता आवश्यक छ।'),
      confirmLabel: AppLanguage.tr(
          'Go To Subscription Plan', 'सदस्यता योजना खोल्नुहोस्'),
      cancelLabel: AppLanguage.tr('Close', 'बन्द गर्नुहोस्'),
      onConfirm: () {
        setState(() => _premiumChapter = null);
        context.push('/subscription');
      },
      onCancel: () => setState(() => _premiumChapter = null),
    );
  }

  Widget _modeSheet(
      BuildContext context, _ChapterPage d, Map<String, dynamic> c) {
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
                    padding: const EdgeInsets.all(22),
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
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_chapterName(c),
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
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
                            color: const Color(0xFF1D4ED8),
                            primary: true,
                            onTap: () =>
                                _goMode('/subjects/practice', c, d),
                          ),
                          const SizedBox(height: 10),
                          _ModeButton(
                            icon: Icons.book_outlined,
                            label: 'Read Mode',
                            color: const Color(0xFF1D4ED8),
                            onTap: () => _goMode('/subjects/read', c, d),
                          ),
                          const SizedBox(height: 10),
                          _ModeButton(
                            icon: Icons.school_outlined,
                            label: 'Theory Mode',
                            color: const Color(0xFF1D4ED8),
                            onTap: () =>
                                _goMode('/subjects/theory', c, d),
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

/// Chapter progress attached by fetchSubjectChaptersWithProgress.
int _pct(Map<String, dynamic> c) =>
    (((c['progress'] as Map?)?['percentage']) as num?)?.toInt() ?? 0;

/// React: completed = progress.completed === true || percentage >= 100.
bool _done(Map<String, dynamic> c) =>
    ((c['progress'] as Map?)?['completed']) == true || _pct(c) >= 100;

/// Blue gradient stats card ("General Awareness / Total Added Topics / 43%")
/// at the top of the chapter page.
///
/// The decorative glow bubbles intentionally bleed past the card edges and
/// are clipped by the outer [ClipRRect] along the 28px rounded border: the
/// inner [Stack] uses [Clip.none] so the bubbles are never cut with a hard
/// straight edge inside the content padding (the old "D" sticker look).
class ChapterSummaryCard extends StatelessWidget {
  final String subjectId;
  final String subjectName;
  final List<Map<String, dynamic>> chapters;

  const ChapterSummaryCard({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.chapters,
  });

  @override
  Widget build(BuildContext context) {
    final total = chapters.length;
    final avg = total == 0
        ? 0
        : (chapters.map(_pct).reduce((a, b) => a + b) / total).round();
    final complete = chapters.where(_done).length;
    final inProgress =
        chapters.where((c) => _pct(c) > 0 && !_done(c)).length;
    final premium = chapters.where((c) => c['pro'] == true).length;
    return ClipRRect(
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
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF5A8CFF).withValues(alpha: 0.22),
                ),
              ),
            ),
            Positioned(
              bottom: -125,
              left: -70,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00002D).withValues(alpha: 0.16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
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
                              subjectName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Added Topics',
                              style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.78),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _ProgressRing(progress: avg),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SummaryStat(
                          icon: Icons.layers,
                          label: 'Total Added Topics',
                          value: total,
                          accent: const Color(0xFFC7D9FF)),
                      _SummaryStat(
                          icon: Icons.check_circle,
                          label: 'Complete',
                          value: complete,
                          accent: const Color(0xFFB8E1FF)),
                      _SummaryStat(
                          icon: Icons.show_chart,
                          label: 'In Progress',
                          value: inProgress,
                          accent: const Color(0xFFC8F2DC)),
                      _SummaryStat(
                          icon: Icons.diamond,
                          label: 'Premium',
                          value: premium,
                          accent: const Color(0xFFFFD2A6)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(19),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(19),
                        onTap: () => context.push(
                            '/practice-analytics',
                            extra: {
                              'subjectSlug': subjectId,
                              'subjectTitle': subjectName,
                            }),
                        child: Container(
                          constraints:
                              const BoxConstraints(minHeight: 36),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.analytics,
                                  size: 15,
                                  color: Color(0xFF0C2D91)),
                              SizedBox(width: 6),
                              Text('View Practice Analytics',
                                  style: TextStyle(
                                      fontSize: 11,
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
    );
  }
}

class _LanguagePill extends StatelessWidget {
  final bool ne;
  final VoidCallback onToggle;
  const _LanguagePill({required this.ne, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggle,
        child: Container(
          constraints: const BoxConstraints(minWidth: 64),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.language,
                  size: 18, color: Colors.white),
              const SizedBox(width: 4),
              // React shows the language it switches TO: ne -> "EN", en -> "नेपाली"
              Text(ne ? 'EN' : 'नेपाली',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
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
      width: 23,
      height: 23,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: bg,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool primary;
  final VoidCallback onTap;

  const _ModeButton(
      {required this.icon,
      required this.label,
      required this.color,
      this.primary = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: primary ? Colors.white : color),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: primary ? Colors.white : color)),
      ],
    );
    if (primary) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
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
          foregroundColor: color,
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

class _ProgressRing extends StatelessWidget {
  final int progress;
  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 70,
      child: CustomPaint(
        painter: _RingPainter(progress / 100, const Color(0xFFFFD2A6)),
        child: Center(
          child: Text('$progress%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawCircle(size.center(Offset.zero), 31, paint);
    paint.color = color;
    canvas.drawArc(
        Rect.fromCircle(center: size.center(Offset.zero), radius: 31),
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
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: accent,
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF0C2D91)),
        ),
        const SizedBox(height: 4),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
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

class _ChapterPage {
  final String subjectName;
  final bool subjectPro;
  final String courseId;
  final String subcourseId;
  final List<Map<String, dynamic>> chapters;
  final bool isPremium;

  const _ChapterPage({
    required this.subjectName,
    required this.subjectPro,
    required this.courseId,
    required this.subcourseId,
    required this.chapters,
    required this.isPremium,
  });
}
