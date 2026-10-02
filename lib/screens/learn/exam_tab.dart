import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_purchases.dart';
import '../../services/exam_service.dart' hide UserProfile;
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/preloading.dart';

/// Exam tab — mirrors app/(tabs)/exam.tsx.
///
/// Stable "Loksewa Exams Hub" header, province chips, section tabs (amber
/// active), section description banner, and per-card lifecycle states
/// (hidden/countdown/ready/rejoin/pending/locked) driven by
/// [resolveExamCardState]. The rules sheet uses the shared [AppModalShell]
/// (the app-wide modal rule) and the doc-ID fallback chain from
/// [fetchExamRules]; confirming Start routes straight to the quiz — the quiz
/// never renders behind a modal.
class ExamTab extends StatefulWidget {
  const ExamTab({super.key});

  @override
  State<ExamTab> createState() => _ExamTabState();
}

class _ExamTabState extends State<ExamTab> {
  bool _loading = true;
  String? _error;

  List<ExamProvince> _provinces = const [];
  List<ExamSection> _sections = const [];
  List<ExamSet> _sets = const [];
  Map<String, List<ExamAttempt>> _attemptsBySet = const {};
  Set<String> _approvedSetIds = const {};
  Map<String, String> _pendingBySet = const {}; // examSetId -> purchaseId
  Map<String, String> _submittedPdfBySet = const {}; // examSetId -> answerId

  String _selectedProvince = 'all';
  String _activeSection = '';
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick(DateTime.now()));
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick(DateTime now) {
    if (!mounted) return;
    // Re-evaluate card states every second (countdown labels stay live).
    setState(() => _now = now);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = ProfileStore.instance.profile;
      final uid = AuthService.currentUser?.uid ?? '';
      final courseId = profile?.courseId;
      final subcourseId = profile?.subcourseId;

      final results = await Future.wait([
        fetchExamProvinces(),
        fetchExamSections(courseId: courseId, subcourseId: subcourseId),
        fetchExamSets(subcourseId: subcourseId),
        uid.isEmpty
            ? Future.value(<ExamAttempt>[])
            : ExamRest.listDocs('users/$uid/exam_attempts')
                .then((d) => d.map(ExamAttempt.fromMap).toList()),
        uid.isEmpty
            ? Future.value(<String>[])
            : fetchMyApprovedExamSetIds(uid),
        uid.isEmpty
            ? Future.value(<ExamPurchaseRecord>[])
            : fetchMyExamPurchases(uid),
        uid.isEmpty
            ? Future.value(<Map<String, dynamic>>[])
            : ExamRest.runQuery(
                'app_exam_answers',
                where: ExamRest.fieldFilter('uid', 'EQUAL', uid),
                limit: 200,
              ),
      ]);

      final sections = results[1] as List<ExamSection>;
      final attempts = results[3] as List<ExamAttempt>;
      final purchases = results[5] as List<ExamPurchaseRecord>;
      final answers = results[6] as List<Map<String, dynamic>>;

      final attemptsBySet = <String, List<ExamAttempt>>{};
      for (final a in attempts) {
        attemptsBySet.putIfAbsent(a.examSetId, () => []).add(a);
      }
      final pendingBySet = <String, String>{};
      for (final p in purchases) {
        if (p.status == 'pending') pendingBySet[p.examSetId] = p.id;
      }
      final submittedPdfBySet = <String, String>{};
      for (final d in answers) {
        final setId = (d['examSetId'] ?? '').toString();
        final submitted = d['submitted'] == true;
        if (setId.isNotEmpty && submitted) {
          submittedPdfBySet[setId] = (d['id'] ?? '').toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _provinces = results[0] as List<ExamProvince>;
        _sections = sections;
        _sets = results[2] as List<ExamSet>;
        _attemptsBySet = attemptsBySet;
        _approvedSetIds = (results[4] as List<String>).toSet();
        _pendingBySet = pendingBySet;
        _submittedPdfBySet = submittedPdfBySet;
        if (_activeSection.isEmpty && sections.isNotEmpty) {
          _activeSection = sections.first.id;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load exams. Pull to retry.', 'परीक्षा लोड हुन सकेन।');
        _loading = false;
      });
    }
  }

  bool _isPurchased(ExamSet set) {
    final profile = ProfileStore.instance.profile;
    if (profile != null && _premiumActive(profile)) return true;
    return _approvedSetIds.contains(set.id);
  }

  bool _premiumActive(UserProfile profile) {
    if (!profile.isPremium) return false;
    final expiry = profile.premiumExpiryDate;
    if (expiry == null || expiry.isEmpty) return true;
    final dt = DateTime.tryParse(expiry);
    return dt == null || dt.isAfter(DateTime.now());
  }

  ExamCardState _cardState(ExamSet set) => resolveExamCardState(
        set: set,
        now: _now,
        hasAttempted: (_attemptsBySet[set.id] ?? const []).isNotEmpty,
        isPurchased: _isPurchased(set),
        hasPendingPurchase: _pendingBySet.containsKey(set.id),
      );

  List<ExamSet> get _visibleSets => _sets.where((s) {
        if (_activeSection.isNotEmpty && s.sectionId != _activeSection) {
          return false;
        }
        if (_selectedProvince != 'all' && s.provinceId != _selectedProvince) {
          return false;
        }
        return _cardState(s) != ExamCardState.hidden;
      }).toList();

  ExamSection? get _activeSectionObj {
    for (final s in _sections) {
      if (s.id == _activeSection) return s;
    }
    return null;
  }

  // ---------- rules sheet ----------

  Future<void> _openRules(ExamSet set, {required bool startMode}) async {
    final profile = ProfileStore.instance.profile;
    List<ExamRule> rules;
    try {
      rules = await fetchExamRules(
        courseId: profile?.courseId,
        subcourseId: profile?.subcourseId,
        provinceId: set.provinceId,
        sectionId: set.sectionId,
      );
    } catch (_) {
      rules = const [];
    }
    if (!mounted) return;
    await AppModalShell.show(
      context: context,
      builder: (dialogContext) => AppModalShell(
        onClose: () => Navigator.of(dialogContext).pop(),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.rule_outlined,
              color: Color(0xFFB45309), size: 28),
        ),
        tagLabel: AppLanguage.tr('Exam Rules', 'परीक्षा नियम'),
        title: Text(
          set.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        body: rules.isEmpty
            ? Text(AppLanguage.tr(
                'No special rules for this exam. Good luck!',
                'यस परीक्षाका लागि विशेष नियम छैनन्। शुभकामना!'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rules.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(right: 10, top: 1),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rules[i].title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                if (rules[i].description.isNotEmpty)
                                  Text(rules[i].description,
                                      style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (startMode) {
                  // Rules confirmed — go straight to the quiz (React: the
                  // quiz never renders behind a modal).
                  context.push('/exam/${set.id}/quiz');
                }
              },
              child: Text(
                  startMode
                      ? AppLanguage.tr('Start Exam', 'परीक्षा सुरु गर्नुहोस्')
                      : AppLanguage.tr('Got it', 'बुझें'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- primary-press routing (mirrors React onPrimaryPress) ----------

  void _onPrimaryPress(ExamSet set) {
    final state = _cardState(set);
    switch (state) {
      case ExamCardState.locked:
        // Pro set, not purchased -> buy flow.
        context.push('/exam-purchase/${set.id}');
        return;
      case ExamCardState.pending:
        // Purchase awaiting review -> pending purchase detail.
        final purchaseId = _pendingBySet[set.id];
        if (purchaseId != null) {
          context.push('/subscription/exam-purchase/$purchaseId');
        }
        return;
      case ExamCardState.countdown:
        return; // disabled button — nothing to do.
      case ExamCardState.rejoin:
        context.push('/exam/${set.id}');
        return;
      case ExamCardState.ready:
        break;
      case ExamCardState.hidden:
        return;
    }
    if (set.contentType == 'pdf') {
      final answerId = _submittedPdfBySet[set.id];
      if (answerId != null && answerId.isNotEmpty) {
        context.push('/exam-answer/$answerId');
      } else {
        final uri = set.pdfUrl ?? '';
        context.push(
          '/pdf/${Uri.encodeComponent(set.id)}'
          '?uri=${Uri.encodeComponent(uri)}'
          '&title=${Uri.encodeComponent(set.title)}',
        );
      }
      return;
    }
    // MCQ: rules sheet in start mode; confirming goes straight to the quiz.
    _openRules(set, startMode: true);
  }

  String _countdownLabel(ExamSet set) {
    final start = set.startTime;
    if (start == null) return '';
    final diff = start.difference(_now);
    if (diff.isNegative) return '';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  String _startLabel(ExamSet set) {
    final start = set.startTime;
    if (start == null) return AppLanguage.tr('Always open', 'सधैं खुला');
    // Kathmandu wall-clock for display.
    final k = start.toUtc().add(const Duration(hours: 5, minutes: 45));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final ampm = k.hour >= 12 ? 'PM' : 'AM';
    var hh = k.hour % 12;
    if (hh == 0) hh = 12;
    final min = k.minute.toString().padLeft(2, '0');
    return '${months[k.month - 1]} ${k.day}, $hh:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _header(),
          Expanded(
            child: _loading
                ? const PreloadingWidget(
                    tinted: false,
                    label: 'Loading Exams...',
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
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
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _provinceChips(),
                            _sectionTabs(),
                            _sectionBanner(),
                            ..._visibleSets.map(_examCard),
                            if (_visibleSets.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: Text(AppLanguage.tr(
                                      'No exams here yet.',
                                      'यहाँ अहिले परीक्षा छैनन्।')),
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ---------- header ----------

  Widget _header() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLanguage.tr('Loksewa Exams Hub', 'लोकसेवा परीक्षा केन्द्र'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLanguage.tr(
                'Live tests, model sets & answer desk',
                'लाइभ परीक्षा, मोडल सेट र उत्तर डेस्क'),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---------- province chips ----------

  Widget _provinceChips() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _provinceChip('all', AppLanguage.tr('All Board', 'सबै बोर्ड')),
          for (final p in _provinces) _provinceChip(p.id, p.name),
        ],
      ),
    );
  }

  Widget _provinceChip(String id, String label) {
    final active = _selectedProvince == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check, size: 16),
              ),
            Text(label),
          ],
        ),
        selected: active,
        onSelected: (_) => setState(() => _selectedProvince = id),
        selectedColor: Colors.white,
        backgroundColor: Colors.grey.shade200,
        labelStyle: TextStyle(
          color: active ? const Color(0xFF1E3A8A) : Colors.black87,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
              color: active ? const Color(0xFF1E3A8A) : Colors.transparent),
        ),
      ),
    );
  }

  // ---------- section tabs ----------

  Widget _sectionTabs() {
    if (_sections.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final s in _sections)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s.name),
                selected: _activeSection == s.id,
                onSelected: (_) => setState(() => _activeSection = s.id),
                selectedColor: const Color(0xFFF59E0B),
                backgroundColor: Colors.grey.shade200,
                labelStyle: TextStyle(
                  color: _activeSection == s.id
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: _activeSection == s.id
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionBanner() {
    final section = _activeSectionObj;
    if (section == null || section.description.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(section.description,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF92400E))),
          ),
        ],
      ),
    );
  }

  // ---------- exam card ----------

  Widget _examCard(ExamSet set) {
    final state = _cardState(set);
    final attempts = _attemptsBySet[set.id] ?? const [];
    final submittedPdf = _submittedPdfBySet[set.id];
    final isPdf = set.contentType == 'pdf';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(set.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (set.isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('PRO',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isPdf) _metaChip(Icons.help_outline,
                    '${set.totalQuestions} ${AppLanguage.tr('Qs', 'प्रश्न')}'),
                _metaChip(Icons.timer_outlined, '${set.durationMinutes} min'),
                _metaChip(Icons.flag_outlined,
                    '${AppLanguage.tr('Pass', 'उत्तीर्ण')} ${set.passPercent}%'),
                _metaChip(
                    Icons.schedule_outlined, _startLabel(set)),
                if (attempts.isNotEmpty)
                  _metaChip(Icons.history,
                      '${attempts.length} ${AppLanguage.tr('attempts', 'प्रयास')}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _primaryButton(set, state, submittedPdf)),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: AppLanguage.tr('Rules', 'नियम'),
                  onPressed: () => _openRules(set, startMode: false),
                  icon: const Icon(Icons.info_outline),
                ),
                IconButton(
                  tooltip: AppLanguage.tr('Ranking', 'र्याङ्किङ'),
                  onPressed: () =>
                      context.push('/exam/${set.id}/ranking'),
                  icon: const Icon(Icons.leaderboard_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
      );

  Widget _primaryButton(
      ExamSet set, ExamCardState state, String? submittedPdf) {
    final isPdf = set.contentType == 'pdf';
    switch (state) {
      case ExamCardState.countdown:
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(
              '${AppLanguage.tr('Starts in', 'सुरु हुन')} ${_countdownLabel(set)}'),
        );
      case ExamCardState.pending:
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB45309),
            side: const BorderSide(color: Color(0xFFF59E0B)),
          ),
          onPressed: () => _onPrimaryPress(set),
          icon: const Icon(Icons.hourglass_empty, size: 18),
          label: Text(AppLanguage.tr('Purchase Pending', 'खरिद विचाराधीन')),
        );
      case ExamCardState.locked:
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _onPrimaryPress(set),
          icon: const Icon(Icons.lock_outline, size: 18),
          label: Text(AppLanguage.tr('Unlock PRO', 'प्रो अनलक')),
        );
      case ExamCardState.rejoin:
        return OutlinedButton.icon(
          onPressed: () => _onPrimaryPress(set),
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(isPdf
              ? AppLanguage.tr('Re-Open', 'पुनः खोल्नुहोस्')
              : AppLanguage.tr('Re-Join', 'पुनः जोडिनुहोस्')),
        );
      case ExamCardState.ready:
      case ExamCardState.hidden:
        break;
    }
    // ready
    if (isPdf) {
      final submitted = submittedPdf != null && submittedPdf.isNotEmpty;
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              submitted ? Colors.green : const Color(0xFFF59E0B),
          foregroundColor: Colors.white,
        ),
        onPressed: () => _onPrimaryPress(set),
        icon: Icon(submitted ? Icons.check_circle_outline : Icons.picture_as_pdf,
            size: 18),
        label: Text(submitted
            ? AppLanguage.tr('Submitted — View', 'बुझाइसकियो — हेर्नुहोस्')
            : AppLanguage.tr('Open PDF', 'PDF खोल्नुहोस्')),
      );
    }
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFF59E0B),
        foregroundColor: Colors.white,
      ),
      onPressed: () => _onPrimaryPress(set),
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text(AppLanguage.tr('Start Exam', 'परीक्षा सुरु गर्नुहोस्')),
    );
  }
}
