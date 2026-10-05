import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_purchases.dart';
import '../../services/exam_service.dart' hide UserProfile;
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';

String _npDigits(String s) => s.replaceAllMapped(
      RegExp(r'[0-9]'),
      (m) => '०१२३४५६७८९'[int.parse(m[0]!)],
    );

/// Exam Hub tab — mirrors app/(tabs)/exam.tsx same-to-same.
///
/// Stable gradient header (the shared #2563EB → #1D4ED8 → #0B1F5B diagonal,
/// 26px bottom radius — the same object as every other header in the app)
/// holding the title, the province filter row and the section tabs. Only the
/// card list below scrolls. Card states come from [resolveExamCardState];
/// provinces select to WHITE, sections select to AMBER — two rows of pills
/// next to each other never highlight the same way.
class ExamTab extends StatefulWidget {
  const ExamTab({super.key});

  /// Set before navigating to the exam tab to auto-scroll to a model set's
  /// card and briefly highlight it (Point 4 — notification "Click here").
  /// Consumed (cleared) once applied.
  static String? pendingHighlightSetId;

  @override
  State<ExamTab> createState() => _ExamTabState();
}

class _ExamTabState extends State<ExamTab> {
  List<ExamProvince> _provinces = const [];
  List<ExamSection> _sections = const [];
  String _provinceId = allProvinces;
  String? _sectionId;
  List<_CardEntry> _cards = const [];
  bool _loading = true;
  String? _error;
  bool _purchaseNavigating = false;
  Timer? _ticker;
  bool _shellLoaded = false;
  final Map<String, _SectionCache> _sectionCache = {};
  // Point 4: scroll-to-card + highlight for notification deep links.
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  String? _highlightedSetId;

  String get _cacheKey => '${_sectionId ?? ''}|$_provinceId';

  @override
  void initState() {
    super.initState();
    _load();
    // Re-resolve hidden -> countdown -> live -> ended every second from the
    // cache, without re-fetching.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final cache = _sectionCache[_cacheKey];
      if (cache == null) return;
      setState(() => _cards = _resolveCards(cache, DateTime.now()));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _subcourseId {
    final store = ProfileStore.instance;
    return store.courseInfo?.subcourseId ?? store.profile?.subcourseId;
  }

  String get _subcourseLabel {
    final store = ProfileStore.instance;
    return store.courseInfo?.subcourseName ??
        store.courseInfo?.courseName ??
        '';
  }

  bool _premiumActive(UserProfile? profile) {
    if (profile == null || !profile.isPremium) return false;
    final expiry = profile.premiumExpiryDate;
    if (expiry == null || expiry.isEmpty) return true;
    final parsed = DateTime.tryParse(expiry);
    if (parsed == null) return false;
    return parsed.isAfter(DateTime.now());
  }

  /// Full refresh — app start and pull-to-refresh only.
  Future<void> _load() async {
    // Fresh rules on full refresh — the session cache is rebuilt below.
    clearExamRulesCache();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadShell();
      await _loadSection(forceRefresh: true);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load exams. Pull to retry.',
            'परीक्षा लोड हुन सकेन। पुनः प्रयास गर्न तल तान्नुहोस्।');
        _loading = false;
      });
    }
  }

  /// Provinces + sections + profile — section/province independent.
  Future<void> _loadShell() async {
    final store = ProfileStore.instance;
    final uid = AuthService.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await store.load(uid);
    }
    final profile = store.profile;
    final courseId = store.courseInfo?.courseId ?? profile?.courseId;
    final subcourseId = _subcourseId;

    final results = await Future.wait([
      fetchExamProvinces(),
      fetchExamSections(courseId: courseId, subcourseId: subcourseId),
    ]);
    final provinces = results[0] as List<ExamProvince>;
    final sections = results[1] as List<ExamSection>;

    String? sectionId = _sectionId;
    if (sections.isNotEmpty &&
        (sectionId == null || !sections.any((s) => s.id == sectionId))) {
      sectionId = sections.first.id;
    }
    if (!mounted) return;
    setState(() {
      _provinces = provinces;
      _sections = sections;
      _sectionId = sectionId;
    });
    _shellLoaded = true;
  }

  List<_CardEntry> _resolveCards(_SectionCache cache, DateTime now) {
    return cache.sets.map((set) {
      final attempted = (cache.attemptsBySet[set.id]?.length ?? 0) > 0;
      final state = resolveExamCardState(
        set: set,
        now: now,
        hasAttempted: attempted,
        isPurchased:
            cache.premium || cache.approvedIds.contains(set.id),
        hasPendingPurchase: cache.pendingIds.contains(set.id),
      );
      return _CardEntry(
        set: set,
        state: state,
        isPurchased:
            cache.premium || cache.approvedIds.contains(set.id),
        hasAttempted: attempted,
        answer:
            set.contentType == 'pdf' ? cache.answers[set.id] : null,
        pendingPurchase: cache.pendingBySet[set.id],
      );
    }).where((e) => e.state != ExamCardState.hidden).toList();
  }

  /// Section data — cached per (sectionId, provinceId). A cached section
  /// shows instantly with no spinner; only pull-to-refresh / app start
  /// forces a network refresh.
  Future<void> _loadSection({bool forceRefresh = false}) async {
    final key = _cacheKey;
    final cached = _sectionCache[key];
    if (!forceRefresh && cached != null) {
      if (!mounted) return;
      setState(() {
        _cards = _resolveCards(cached, DateTime.now());
        _purchaseNavigating = false;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = ProfileStore.instance;
      final uid = AuthService.currentUser?.uid;
      final profile = store.profile;
      final subcourseId = _subcourseId;
      final sectionId = _sectionId;

      final results = await Future.wait([
        uid == null
            ? Future.value(<ExamAttempt>[])
            : fetchAllExamAttempts(uid),
        uid == null
            ? Future.value(<String, ExamAnswer>{})
            : fetchMyExamAnswersBySet(uid),
        uid == null
            ? Future.value(<ExamPurchaseRecord>[])
            : fetchMyExamPurchases(uid),
      ]);
      final attempts = results[0] as List<ExamAttempt>;
      final answers = results[1] as Map<String, ExamAnswer>;
      final purchases = results[2] as List<ExamPurchaseRecord>;

      final attemptsBySet = <String, List<ExamAttempt>>{};
      for (final a in attempts) {
        attemptsBySet.putIfAbsent(a.examSetId, () => []).add(a);
      }
      final approvedIds = purchases
          .where((p) => p.status == 'active')
          .map((p) => p.examSetId)
          .toSet();
      final pendingIds = purchases
          .where((p) => p.status == 'pending')
          .map((p) => p.examSetId)
          .toSet();
      final pendingBySet = <String, ExamPurchaseRecord>{};
      for (final p in purchases) {
        if (p.status == 'pending') pendingBySet[p.examSetId] = p;
      }

      List<ExamSet> sets = const [];
      if (subcourseId != null &&
          subcourseId.isNotEmpty &&
          sectionId != null) {
        sets = await fetchExamSets(
          subcourseId: subcourseId,
          sectionId: sectionId,
          provinceId: _provinceId,
        );
      }
      final cache = _SectionCache(
        sets: sets,
        attemptsBySet: attemptsBySet,
        approvedIds: approvedIds,
        pendingIds: pendingIds,
        answers: answers,
        pendingBySet: pendingBySet,
        premium: _premiumActive(profile),
      );
      _sectionCache[key] = cache;
      // Warm the rules session-cache for the visible sets' province combos
      // (capped): the first Rules popup then opens instantly, zero reads.
      final provincesToWarm = <String>{};
      for (final s in sets) {
        if (provincesToWarm.length >= 3) break;
        final p = s.provinceId;
        if (p.isNotEmpty) provincesToWarm.add(p);
      }
      for (final p in provincesToWarm) {
        prefetchExamRules(
          subcourseId: subcourseId,
          provinceId: p,
          sectionId: sectionId,
        );
      }
      // The user may have switched section/province mid-fetch — only apply
      // if this result still belongs to the visible tab.
      if (!mounted || _cacheKey != key) return;
      setState(() {
        _cards = _resolveCards(cache, DateTime.now());
        _purchaseNavigating = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || _cacheKey != key) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load exams. Pull to retry.',
            'परीक्षा लोड हुन सकेन। पुनः प्रयास गर्न तल तान्नुहोस्।');
        _loading = false;
      });
    }
  }

  ExamSection? get _activeSection {
    for (final s in _sections) {
      if (s.id == _sectionId) return s;
    }
    return null;
  }

  Future<void> _openRules(ExamSet set, _RulesMode mode) async {
    final confirmed = await AppModalShell.show<bool>(
      context: context,
      builder: (ctx) => _RulesDialogContent(set: set, mode: mode),
    );
    if (!mounted) return;
    if (mode == _RulesMode.start && confirmed == true) {
      context.push(
          '/exam/${set.id}/quiz?title=${Uri.encodeComponent(set.title)}');
    }
  }

  void _onPrimaryPress(_CardEntry entry) {
    final set = entry.set;
    if (entry.state == ExamCardState.locked) {
      setState(() => _purchaseNavigating = true);
      context.push('/exam-purchase/${set.id}');
      return;
    }
    if (entry.state == ExamCardState.pending) {
      final purchase = entry.pendingPurchase;
      if (purchase != null) {
        setState(() => _purchaseNavigating = true);
        context.push('/subscription/exam-purchase/${purchase.id}');
      } else {
        setState(() => _purchaseNavigating = false);
      }
      return;
    }
    if (set.contentType == 'pdf') {
      final answer = entry.answer;
      if (answer != null) {
        context.push('/exam-answer/${answer.id}');
        return;
      }
      final pdfUrl = set.pdfUrl;
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        final nepali = AppLanguage.isNepali;
        final section = _activeSection;
        context.push(
          '/pdf/${set.id}?uri=${Uri.encodeComponent(pdfUrl)}'
          '&title=${Uri.encodeComponent(set.title)}'
          '&examSetId=${set.id}'
          '&allowUpload=${section?.kind == 'theory' ? '1' : '0'}'
          '&sectionName=${Uri.encodeComponent(section?.displayName(nepali) ?? '')}',
        );
      } else {
        // Paper not uploaded yet.
      }
      return;
    }
    if (entry.state == ExamCardState.rejoin) {
      context.push('/exam/${set.id}');
    } else {
      _openRules(set, _RulesMode.start);
    }
  }

  /// Point 4: scrolls the card list to [ExamTab.pendingHighlightSetId]'s
  /// card and flashes a highlight ring on it. Consumes the pending id, so
  /// this runs once. Silently no-ops when the set isn't in the current
  /// section/province filter.
  void _applyHighlight() {
    final target = ExamTab.pendingHighlightSetId;
    ExamTab.pendingHighlightSetId = null;
    if (target == null || target.isEmpty) return;
    if (!mounted) return;
    final key = _cardKeys[target];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
      alignment: 0.25,
    );
    setState(() => _highlightedSetId = target);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _highlightedSetId == target) {
        setState(() => _highlightedSetId = null);
      }
    });
  }

  String _countdownLabel(DateTime? start, DateTime now) {
    if (start == null) return '--:--';
    var s = start.difference(now).inSeconds;
    if (s < 0) s = 0;
    final m = s ~/ 60;
    final sec = s % 60;
    final label =
        '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return AppLanguage.isNepali ? _npDigits(label) : label;
  }

  @override
  Widget build(BuildContext context) {
    // Point 4: consume a pending highlight request (notification "Click
    // here"). Runs once the cards are laid out; the ticker's per-second
    // rebuilds re-check harmlessly until the pending id is consumed.
    if (ExamTab.pendingHighlightSetId != null &&
        _cards.isNotEmpty &&
        !_loading &&
        _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyHighlight());
    }
    final palette = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
          if (_purchaseNavigating)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: PreloadingWidget(
                    tinted: true,
                    label: AppLanguage.tr('Loading…', 'लोड हुँदै…'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Stable header — the shared diagonal gradient, 26px bottom radius,
  /// full-bleed under the status bar. Title row, province chips, section tabs.
  Widget _buildHeader() {
    const gradientColors = [
      Color(0xFF2563EB),
      Color(0xFF1D4ED8),
      Color(0xFF0B1F5B),
    ];
    final nepali = AppLanguage.isNepali;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1D4ED8),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
        ),
        child: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              // Title row.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school,
                          size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Loksewa Exams Hub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Province filter.
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _provinces.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (c, i) {
                    final id = i == 0 ? allProvinces : _provinces[i - 1].id;
                    final label = i == 0
                        ? AppLanguage.tr('All Board', 'सबै बोर्ड')
                        : _provinces[i - 1].displayName(nepali);
                    return _provinceChip(id, label);
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Section tabs.
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _sections.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (c, i) => _sectionTab(_sections[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  /// Provinces select to WHITE; sections select to AMBER — each filter level
  /// gets its own colour so the two pill rows never read as one control.
  Widget _provinceChip(String id, String label) {
    final active = id == _provinceId;
    return GestureDetector(
      onTap: () {
        if (_provinceId == id) return;
        setState(() => _provinceId = id);
        _loadSection();
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.check,
                    size: 14, color: Color(0xFF1D4ED8)),
              ),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFF1D4ED8)
                    : Colors.white,
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTab(ExamSection section) {
    final active = section.id == _sectionId;
    final nepali = AppLanguage.isNepali;
    return GestureDetector(
      onTap: () {
        if (_sectionId == section.id) return;
        setState(() => _sectionId = section.id);
        _loadSection();
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFBBF24)
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? const Color(0xFFFBBF24)
                : Colors.white.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            section.displayName(nepali),
            style: TextStyle(
              color: active
                  ? const Color(0xFF78350F)
                  : Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final palette = ExpoPalette.of(context);
    final subcourseId = _subcourseId;
    if (_loading) {
      return PreloadingWidget(
        tinted: false,
        label: AppLanguage.tr('Loading Exams…', 'परीक्षा लोड हुँदै…'),
      );
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(child: Text(_error!)),
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton(
                onPressed: _load,
                child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास')),
              ),
            ),
          ],
        ),
      );
    }
    if (subcourseId == null || subcourseId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined,
                  size: 48, color: palette.textDisabled),
              const SizedBox(height: 16),
              Text(
                AppLanguage.tr('Set up your course first',
                    'पहिले आफ्नो कोर्स सेट गर्नुहोस्'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguage.tr(
                    'Exam sets are matched to your enrolled course and subcourse.',
                    'परीक्षा सेटहरू तपाईंको कोर्स र सबकोर्ससँग मिलाइन्छ।'),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.push('/course-setup?mode=update'),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(AppLanguage.tr(
                    'Set up course', 'कोर्स सेट गर्नुहोस्')),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_activeSection != null) _sectionBanner(_activeSection!),
          if (_activeSection != null) const SizedBox(height: 12),
          if (_cards.isEmpty)
            _emptyState(palette)
          else
            // Staggered syllabus entrance on the model cards.
            ..._cards.asMap().entries.map((me) {
              final i = me.key;
              final e = me.value;
              // Point 4: glowing ring while this card is the highlight
              // target of a notification deep link.
              final highlighted = e.set.id == _highlightedSetId;
              return Padding(
                key: _cardKeys.putIfAbsent(e.set.id, () => GlobalKey()),
                padding: const EdgeInsets.only(bottom: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: highlighted
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF2563EB),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.35),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        )
                      : null,
                  child: SyllabusEntrance(
                    delayMs: (i.clamp(0, 8)) * 60,
                    child: _ExamCard(
                      entry: e,
                      accentColor: Color(
                          _activeSection?.colorValue ?? 0xFF2563EB),
                      subcourseLabel: _subcourseLabel,
                      countdownLabel:
                          _countdownLabel(e.set.startTime, DateTime.now()),
                      onRulesPress: () => _openRules(e.set, _RulesMode.info),
                      onPrimaryPress: () => _onPrimaryPress(e),
                      onRankingPress: () =>
                          context.push('/exam/${e.set.id}/ranking'),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Section description banner — megaphone + section name + description,
  /// tinted with the section's own accent colour.
  Widget _sectionBanner(ExamSection section) {
    final accent = Color(section.colorValue);
    final nepali = AppLanguage.isNepali;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.displayName(nepali),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (section.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              section.description,
              style: TextStyle(
                fontSize: 13,
                height: 19 / 13,
                color: ExpoPalette.of(context).textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(ExpoPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 48, color: palette.textDisabled),
          const SizedBox(height: 16),
          Text(
            AppLanguage.tr('No exams open right now',
                'अहिले कुनै परीक्षा खुला छैन'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.tr(
                'Exam cards appear 10 minutes before their start time. Pull down to refresh, or check another board.',
                'परीक्षा सुरु हुनुभन्दा १० मिनेटअघि कार्डहरू देखिन्छन्। रिफ्रेश गर्न तल तान्नुहोस् वा अर्को बोर्ड हेर्नुहोस्।'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CardEntry {
  final ExamSet set;
  final ExamCardState state;
  final bool isPurchased;
  final bool hasAttempted;
  final ExamAnswer? answer;
  final ExamPurchaseRecord? pendingPurchase;

  const _CardEntry({
    required this.set,
    required this.state,
    required this.isPurchased,
    required this.hasAttempted,
    this.answer,
    this.pendingPurchase,
  });
}

enum _RulesMode { info, start }

/// Cached per (sectionId, provinceId): the raw sets plus everything needed to
/// resolve card states. Card STATES are re-resolved with a fresh `now` on
/// every tick (countdown -> live -> ended transitions) without re-fetching.
class _SectionCache {
  final List<ExamSet> sets;
  final Map<String, List<ExamAttempt>> attemptsBySet;
  final Set<String> approvedIds;
  final Set<String> pendingIds;
  final Map<String, ExamAnswer> answers;
  final Map<String, ExamPurchaseRecord> pendingBySet;
  final bool premium;

  const _SectionCache({
    required this.sets,
    required this.attemptsBySet,
    required this.approvedIds,
    required this.pendingIds,
    required this.answers,
    required this.pendingBySet,
    required this.premium,
  });
}

/// One exam card — mirrors ExamCard.tsx: title row with icon box, meta chips,
/// difficulty/access tags, then the Rules / Ranking / primary action row.
class _ExamCard extends StatelessWidget {
  final _CardEntry entry;
  final Color accentColor;
  final String subcourseLabel;
  final String countdownLabel;
  final VoidCallback onRulesPress;
  final VoidCallback onPrimaryPress;
  final VoidCallback onRankingPress;

  const _ExamCard({
    required this.entry,
    required this.accentColor,
    required this.subcourseLabel,
    required this.countdownLabel,
    required this.onRulesPress,
    required this.onPrimaryPress,
    required this.onRankingPress,
  });

  static const _green = Color(0xFF16A34A);
  static const _amber = Color(0xFFD97706);
  static const _red = Color(0xFFDC2626);

  Color _difficultyColor(String d) {
    switch (d) {
      case 'medium':
        return _amber;
      case 'hard':
        return _red;
      default:
        return _green;
    }
  }

  String _difficultyLabel(String d) {
    switch (d) {
      case 'medium':
        return AppLanguage.tr('Medium', 'मध्यम');
      case 'hard':
        return AppLanguage.tr('Hard', 'गाह्रो');
      default:
        return AppLanguage.tr('Easy', 'सजिलो');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final set = entry.set;
    final state = entry.state;
    final isPdf = set.contentType == 'pdf';
    final isSubmitted = isPdf && entry.answer != null;
    final answerStatus = entry.answer?.status;

    // ---- primary button ----
    late final String primaryLabel;
    late final IconData primaryIcon;
    late final bool primaryDisabled;
    if (isSubmitted) {
      primaryLabel = AppLanguage.tr('View Details', 'विवरण हेर्नुहोस्');
      primaryIcon = Icons.lock_outline;
      primaryDisabled = false;
    } else {
      switch (state) {
        case ExamCardState.countdown:
          primaryLabel = countdownLabel;
          primaryIcon = Icons.access_time;
          primaryDisabled = true;
          break;
        case ExamCardState.rejoin:
          primaryLabel = AppLanguage.tr('Re-Join', 'पुनः जोइन');
          primaryIcon = Icons.refresh;
          primaryDisabled = false;
          break;
        case ExamCardState.live:
          // Live window: same action as ready/rejoin — the red blinking
          // timer lives in its own chip above.
          if (entry.hasAttempted) {
            primaryLabel = AppLanguage.tr('Re-Join', 'पुनः जोइन');
            primaryIcon = Icons.refresh;
          } else if (isPdf) {
            primaryLabel =
                AppLanguage.tr('View Question', 'प्रश्न हेर्नुहोस्');
            primaryIcon = Icons.description;
          } else {
            primaryLabel = AppLanguage.tr('Start', 'सुरु गर्नुहोस्');
            primaryIcon = Icons.play_arrow;
          }
          primaryDisabled = false;
          break;
        case ExamCardState.pending:
          primaryLabel = AppLanguage.tr('Pending', 'पेन्डिङ');
          primaryIcon = Icons.access_time;
          primaryDisabled = false;
          break;
        case ExamCardState.locked:
          primaryLabel = AppLanguage.tr('To Purchase', 'खरिद गर्नुहोस्');
          primaryIcon = Icons.lock_outline;
          primaryDisabled = false;
          break;
        case ExamCardState.ready:
        case ExamCardState.hidden:
          if (isPdf) {
            primaryLabel =
                AppLanguage.tr('View Question', 'प्रश्न हेर्नुहोस्');
            primaryIcon = Icons.description;
          } else {
            primaryLabel = AppLanguage.tr('Start', 'सुरु गर्नुहोस्');
            primaryIcon = Icons.play_arrow;
          }
          primaryDisabled = false;
          break;
      }
    }
    final Color primaryColor = primaryDisabled
        ? palette.textDisabled
        : isSubmitted ||
                (entry.isPurchased &&
                    (state == ExamCardState.ready ||
                        state == ExamCardState.rejoin ||
                        state == ExamCardState.live)) ||
                (!entry.isPurchased &&
                    entry.hasAttempted &&
                    (state == ExamCardState.rejoin ||
                        state == ExamCardState.live))
            ? _green
            : accentColor;

    final submitted = isSubmitted;
    final now = DateTime.now();
    final windowEnd = liveWindowEnd(set);
    final windowOver =
        windowEnd != null && !now.isBefore(windowEnd);
    return Opacity(
      opacity: submitted ? 0.72 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row.
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPdf ? Icons.description : Icons.help,
                    size: 20,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        set.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subcourseLabel.isNotEmpty)
                        Text(
                          subcourseLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (submitted) _submittedBadge(answerStatus),
              ],
            ),
            const SizedBox(height: 10),
            // Meta chips.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state == ExamCardState.live && windowEnd != null)
                  _LiveChip(end: windowEnd)
                else if (!windowOver)
                  _chip(
                    icon: Icons.calendar_today_outlined,
                    label: _startLabel(set.startTime),
                    color: accentColor,
                    bg: accentColor.withValues(alpha: 0.07),
                    borderColor: accentColor.withValues(alpha: 0.2),
                    palette: palette,
                  ),
                if (!isPdf) ...[
                  _chip(
                    icon: Icons.help_outline,
                    label: AppLanguage.isNepali
                        ? _npDigits('${set.totalQuestions} Qs')
                        : '${set.totalQuestions} Qs',
                    palette: palette,
                  ),
                  _chip(
                    icon: Icons.access_time_outlined,
                    label: AppLanguage.isNepali
                        ? _npDigits('${set.durationMinutes}m')
                        : '${set.durationMinutes}m',
                    palette: palette,
                  ),
                  _chip(
                    icon: Icons.emoji_events_outlined,
                    label: AppLanguage.isNepali
                        ? 'पास ${_npDigits('${set.passPercent}%')}'
                        : 'Pass ${set.passPercent}%',
                    palette: palette,
                  ),
                ] else
                  _chip(
                    icon: Icons.attach_file_outlined,
                    label: AppLanguage.tr('PDF paper', 'PDF प्रश्नपत्र'),
                    palette: palette,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Tags.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  icon: Icons.bar_chart_outlined,
                  label: _difficultyLabel(set.difficulty),
                  color: _difficultyColor(set.difficulty),
                  bg: _difficultyColor(set.difficulty)
                      .withValues(alpha: 0.08),
                  borderColor: _difficultyColor(set.difficulty)
                      .withValues(alpha: 0.27),
                  bold: true,
                  palette: palette,
                ),
                if (set.accessType == 'free')
                  _chip(
                    icon: Icons.check_circle,
                    label: AppLanguage.tr('Free', 'निःशुल्क'),
                    color: _green,
                    bg: _green.withValues(alpha: 0.08),
                    borderColor: _green.withValues(alpha: 0.27),
                    bold: true,
                    palette: palette,
                  )
                else
                  _chip(
                    icon: state == ExamCardState.locked
                        ? Icons.lock_outline
                        : state == ExamCardState.pending
                            ? Icons.access_time
                            : Icons.check_circle,
                    label: state == ExamCardState.locked
                        ? AppLanguage.tr(
                            'Not Purchased', 'खरिद गरिएको छैन')
                        : state == ExamCardState.pending
                            ? AppLanguage.tr('Purchase Pending',
                                'खरिद पेन्डिङमा')
                            : AppLanguage.tr(
                                'Purchased', 'खरिद गरिएको'),
                    color: state == ExamCardState.locked
                        ? palette.danger
                        : state == ExamCardState.pending
                            ? palette.warning
                            : _green,
                    bg: (state == ExamCardState.locked
                            ? palette.danger
                            : state == ExamCardState.pending
                                ? palette.warning
                                : _green)
                        .withValues(alpha: 0.08),
                    borderColor: (state == ExamCardState.locked
                            ? palette.danger
                            : state == ExamCardState.pending
                                ? palette.warning
                                : _green)
                        .withValues(alpha: 0.27),
                    bold: true,
                    palette: palette,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Published date — shown once the live window has ended,
            // just above the Rules / Ranking / primary action row.
            if (windowOver && set.startTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined,
                        size: 14, color: palette.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${AppLanguage.tr('Published', 'प्रकाशित')}: ${_fullDateTime(set.startTime!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Actions.
            Row(
              children: [
                _secondaryButton(
                  context,
                  icon: Icons.info_outline,
                  label: AppLanguage.tr('Rules', 'नियमहरू'),
                  onTap: onRulesPress,
                ),
                if (state == ExamCardState.rejoin) ...[
                  const SizedBox(width: 8),
                  _secondaryButton(
                    context,
                    icon: Icons.emoji_events_outlined,
                    label: AppLanguage.tr('Ranking', 'र्याङ्किङ'),
                    iconColor: _amber,
                    onTap: onRankingPress,
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: primaryDisabled ? null : onPrimaryPress,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(primaryIcon,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              primaryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (state == ExamCardState.countdown) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  AppLanguage.tr(
                      'Opens automatically when the timer ends',
                      'टाइमर सकिएपछि स्वतः खुल्नेछ'),
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _startLabel(DateTime? start) {
    if (start == null) {
      return AppLanguage.tr('Open now', 'अहिले खुला छ');
    }
    final h12 = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final mm = start.minute.toString().padLeft(2, '0');
    final ampm = start.hour < 12 ? 'AM' : 'PM';
    final time = '$h12:$mm $ampm';
    return AppLanguage.isNepali
        ? 'सुरु: ${_npDigits(time)}'
        : 'Start: $time';
  }

  /// Full date-time for the post-live "Published: 2026-01-01 7:05 PM" line.
  String _fullDateTime(DateTime d) {
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final time = AppLanguage.isNepali
        ? _npDigits('$h12:$mm $ampm')
        : '$h12:$mm $ampm';
    return '$date $time';
  }

  Widget _submittedBadge(String? status) {
    final reviewed = status == 'reviewed';
    final color = reviewed ? _green : _amber;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reviewed ? Icons.done_all_outlined : Icons.access_time,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            reviewed
                ? AppLanguage.tr('Reviewed', 'समीक्षा भयो')
                : AppLanguage.tr('Pending', 'पेन्डिङ'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required ExpoPalette palette,
    Color? color,
    Color? bg,
    Color? borderColor,
    bool bold = false,
  }) {
    final c = color ?? palette.textSecondary;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: borderColor ?? palette.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final palette = ExpoPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: iconColor ?? palette.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live chip — red pulsing dot + "LIVE" + remaining window time, blinking
/// red while the exam is inside its live window.
class _LiveChip extends StatefulWidget {
  final DateTime end;

  const _LiveChip({required this.end});

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip> {
  Timer? _blink;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _blink = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.end.difference(DateTime.now());
    final total = left.inSeconds.clamp(0, 1 << 30);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final clock = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    const red = Color(0xFFDC2626);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _on ? 1.0 : 0.35,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: red.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              AppLanguage.tr('LIVE', 'लाइभ'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: red,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              AppLanguage.isNepali ? _npDigits(clock) : clock,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: red,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exam rules popup content — mirrors ExamRulesSheet.tsx: shield icon,
/// numbered rules with icon boxes, primary 'Start Quiz' / 'OK'. Pops `true`
/// when the primary action confirms a start, `false`/`null` otherwise.
class _RulesDialogContent extends StatefulWidget {
  final ExamSet set;
  final _RulesMode mode;

  const _RulesDialogContent({required this.set, required this.mode});

  @override
  State<_RulesDialogContent> createState() => _RulesDialogContentState();
}

class _RulesDialogContentState extends State<_RulesDialogContent> {
  List<ExamRule>? _rules;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Session-cached: first open per (subcourse, province, section) fetches
    // (1-4 reads), every later open returns instantly with zero reads.
    // _loadSection also prefetches, so this is usually a cache hit.
    fetchExamRulesCached(
      subcourseId: widget.set.subcourseId,
      provinceId: widget.set.provinceId,
      sectionId: widget.set.sectionId,
    ).then((r) {
      if (mounted) setState(() => _rules = r);
    }).catchError((_) {
      if (mounted) setState(() => _rules = []);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    const accent = Color(0xFF2563EB);
    final rules = _rules;
    return AppModalShell(
      // Compact card: smaller than the daily-limit popup (maxWidth 300,
      // 50% height cap) with tighter text so more rules fit on screen.
      // Full blue gradient — accentMid/accentLight/tagColor must be blue
      // too, they default to logo orange.
      maxWidth: 320,
      contentMaxHeight: MediaQuery.of(context).size.height * 0.5,
      scrollHint: true,
      scrollController: _scrollController,
      autoScroll: true,
      accent: accent,
      accentMid: const Color(0xFF60A5FA),
      accentLight: const Color(0xFFBFDBFE),
      tagColor: accent,
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.shield_outlined,
            color: Color(0xFF2563EB), size: 24),
      ),
      tagLabel: AppLanguage.tr('Exam Rules', 'परीक्षा नियमहरू'),
      title: Text(
        widget.set.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      body: rules == null
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : rules.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined,
                          size: 40, color: palette.textDisabled),
                      const SizedBox(height: 8),
                      Text(
                        AppLanguage.tr(
                            'Rules for this exam have not been published yet.',
                            'यस परीक्षाका नियमहरू अहिलेसम्म प्रकाशित भएका छैनन्।'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary),
                      ),
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < rules.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: i == rules.length - 1 ? 0 : 10),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.09),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.shield_outlined,
                                  size: 15, color: accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        constraints:
                                            const BoxConstraints(
                                                minWidth: 18),
                                        height: 18,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(
                                              alpha: 0.09),
                                          borderRadius:
                                              BorderRadius.circular(
                                                  9),
                                        ),
                                        child: Center(
                                          child: Text(
                                            AppLanguage.isNepali
                                                ? _npDigits('${i + 1}')
                                                : '${i + 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.bold,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          rules[i].title,
                                          style: const TextStyle(
                                            fontWeight:
                                                FontWeight.bold,
                                            fontSize: 12.5,
                                            // Explicit ink color: never dim.
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    rules[i].description,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 17 / 11.5,
                                      // Slate-600: readable, never washed.
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppLanguage.tr('Close', 'बन्द गर्नुहोस्')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: accent.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white,
              ),
              // Gated: not clickable until the rules have actually loaded
              // and shown — no starting blind while the spinner runs.
              onPressed: rules == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: Text(widget.mode == _RulesMode.start
                  ? AppLanguage.tr('Start Quiz', 'क्विज सुरु गर्नुहोस्')
                  : AppLanguage.tr('OK', 'ठीक छ')),
            ),
          ),
        ],
      ),
      onClose: () {},
    );
  }
}
