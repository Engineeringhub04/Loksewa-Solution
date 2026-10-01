import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/subpage_header.dart';

/// Help Center — mirrors app/settings/help-center.tsx.
/// Hero card, live search (questions + answers), topic chips that hide while
/// searching, one-open-at-a-time FAQ accordion, quick actions and
/// display-only contact rows.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpTopic {
  final String key;
  final IconData icon;
  final Color color;
  final String nameEn;
  final String nameNe;
  const _HelpTopic({
    required this.key,
    required this.icon,
    required this.color,
    required this.nameEn,
    required this.nameNe,
  });
}

class _Faq {
  final String id;
  final String topicKey;
  final Color color;
  final String qEn;
  final String qNe;
  final String aEn;
  final String aNe;
  const _Faq({
    required this.id,
    required this.topicKey,
    required this.color,
    required this.qEn,
    required this.qNe,
    required this.aEn,
    required this.aNe,
  });
}

/// Fades its child in on mount (mirrors React's FadeIn entering on the
/// open FAQ answer). Finite 180ms animation — safe for tests.
class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _c, child: widget.child);
  }
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  // Topic hues are fixed in both themes (like the analytics legend).
  static const _topics = [
    _HelpTopic(
        key: 'start',
        icon: Icons.rocket_launch_outlined,
        color: Color(0xFF6366F1),
        nameEn: 'Getting started',
        nameNe: 'सुरुवात'),
    _HelpTopic(
        key: 'study',
        icon: Icons.book_outlined,
        color: Color(0xFF10B981),
        nameEn: 'Study & practice',
        nameNe: 'अध्ययन र अभ्यास'),
    _HelpTopic(
        key: 'exams',
        icon: Icons.timer_outlined,
        color: Color(0xFFF59E0B),
        nameEn: 'Exams',
        nameNe: 'परीक्षा'),
    _HelpTopic(
        key: 'daily',
        icon: Icons.calendar_month_outlined,
        color: Color(0xFF0EA5E9),
        nameEn: 'Daily Test',
        nameNe: 'दैनिक परीक्षा'),
    _HelpTopic(
        key: 'current',
        icon: Icons.newspaper_outlined,
        color: Color(0xFF14B8A6),
        nameEn: 'Current affairs',
        nameNe: 'समसामयिक'),
    _HelpTopic(
        key: 'progress',
        icon: Icons.bar_chart_outlined,
        color: Color(0xFFA855F7),
        nameEn: 'Progress & points',
        nameNe: 'प्रगति र अंक'),
    _HelpTopic(
        key: 'account',
        icon: Icons.account_circle_outlined,
        color: Color(0xFFEC4899),
        nameEn: 'Account',
        nameNe: 'खाता'),
    _HelpTopic(
        key: 'app',
        icon: Icons.settings_outlined,
        color: Color(0xFF64748B),
        nameEn: 'App & settings',
        nameNe: 'एप र सेटिङ'),
  ];

  static const _faqs = [
    // start
    _Faq(
        id: 'start.1',
        topicKey: 'start',
        color: Color(0xFF6366F1),
        qEn: 'How do I choose my course?',
        qNe: 'मेरो कोर्स कसरी छान्ने?',
        aEn:
            'On your first login the app asks for a course and a sub-course. You can change it any time from Profile → Edit Profile.',
        aNe:
            'पहिलो पटक लगइन गर्दा एपले कोर्स र सब-कोर्स सोध्छ। पछि जुनसुकै बेला प्रोफाइल → प्रोफाइल सम्पादनबाट फेर्न सकिन्छ।'),
    _Faq(
        id: 'start.2',
        topicKey: 'start',
        color: Color(0xFF6366F1),
        qEn: 'Is the app free to use?',
        qNe: 'एप नि:शुल्क हो?',
        aEn:
            'Most practice material is free. A few exam sets and premium notes need a purchase, and that is always marked on the card before you open it.',
        aNe:
            'धेरैजसो अभ्यास सामग्री नि:शुल्क छ। केही परीक्षा सेट र प्रिमियम नोट किन्नुपर्छ, र त्यो खोल्नुअघि नै कार्डमा देखिन्छ।'),
    _Faq(
        id: 'start.3',
        topicKey: 'start',
        color: Color(0xFF6366F1),
        qEn: 'Do I need internet all the time?',
        qNe: 'सधैं इन्टरनेट चाहिन्छ?',
        aEn:
            'Internet is needed to load new content and to save your progress. Pages you already opened stay readable from cache for a short while.',
        aNe:
            'नयाँ सामग्री ल्याउन र प्रगति सुरक्षित गर्न इन्टरनेट चाहिन्छ। पहिले खोलिसकेका पृष्ठ केही समय क्यासबाट पढ्न मिल्छ।'),
    // study
    _Faq(
        id: 'study.1',
        topicKey: 'study',
        color: Color(0xFF10B981),
        qEn: 'Where do I practise a subject?',
        qNe: 'विषयको अभ्यास कहाँबाट गर्ने?',
        aEn:
            'Open Subjects, pick a subject, then a chapter and a unit, and choose Read or Practice.',
        aNe:
            'विषयहरू खोल्नुहोस्, विषय छान्नुहोस्, त्यसपछि अध्याय र युनिट छानेर पठन वा अभ्यास रोज्नुहोस्।'),
    _Faq(
        id: 'study.2',
        topicKey: 'study',
        color: Color(0xFF10B981),
        qEn: 'Can I save a question for later?',
        qNe: 'प्रश्न पछिका लागि सुरक्षित गर्न मिल्छ?',
        aEn:
            'Yes. Tap the bookmark icon on any question or article. Everything you save is in Profile → Bookmarks.',
        aNe:
            'मिल्छ। कुनै पनि प्रश्न वा लेखमा बुकमार्क आइकन थिच्नुहोस्। सुरक्षित गरेका सबै प्रोफाइल → बुकमार्कमा हुन्छन्।'),
    _Faq(
        id: 'study.3',
        topicKey: 'study',
        color: Color(0xFF10B981),
        qEn: 'Why does it say my bookmark slots are full?',
        qNe: 'बुकमार्क स्लट भरियो भन्छ, किन?',
        aEn:
            'Each sub-course allows 15 bookmarks. Remove one from the Bookmarks page to free a slot.',
        aNe:
            'हरेक सब-कोर्समा १५ वटा बुकमार्क राख्न मिल्छ। स्लट खाली गर्न बुकमार्क पृष्ठबाट पुरानो एउटा हटाउनुहोस्।'),
    // exams
    _Faq(
        id: 'exams.1',
        topicKey: 'exams',
        color: Color(0xFFF59E0B),
        qEn: 'When can I start an exam set?',
        qNe: 'परीक्षा सेट कहिले सुरु गर्न सकिन्छ?',
        aEn:
            'A scheduled set unlocks at its start time. The countdown on the card shows exactly when that is.',
        aNe:
            'तालिका भएको सेट आफ्नो सुरु समयमा खुल्छ। कार्डमा देखिने काउन्टडाउनले ठ्याक्कै कति बाँकी छ भन्ने देखाउँछ।'),
    _Faq(
        id: 'exams.2',
        topicKey: 'exams',
        color: Color(0xFFF59E0B),
        qEn: 'What happens if I leave an exam midway?',
        qNe: 'परीक्षा बीचमै छोडे के हुन्छ?',
        aEn:
            'The timer keeps running. Come back before it ends and your answers are still there.',
        aNe:
            'समय चलिरहन्छ। समय सकिनुअघि फर्किए तपाईंका उत्तर जस्ताको तस्तै हुन्छन्।'),
    _Faq(
        id: 'exams.3',
        topicKey: 'exams',
        color: Color(0xFFF59E0B),
        qEn: 'Where do I see my rank?',
        qNe: 'मेरो र्‍याङ्क कहाँ हेर्ने?',
        aEn:
            'Once results are published, open the Ranking tab on that exam, or the Leaderboard tab for the overall standing.',
        aNe:
            'नतिजा प्रकाशित भएपछि त्यही परीक्षाको र्‍याङ्किङ ट्याब, वा समग्रका लागि लिडरबोर्ड ट्याब खोल्नुहोस्।'),
    // daily
    _Faq(
        id: 'daily.1',
        topicKey: 'daily',
        color: Color(0xFF0EA5E9),
        qEn: 'How often can I take the Daily Test?',
        qNe: 'दैनिक परीक्षा कति पटक दिन मिल्छ?',
        aEn:
            'Once a day. A fresh set arrives each morning and the previous one closes.',
        aNe:
            'दिनको एक पटक। हरेक बिहान नयाँ सेट आउँछ र अघिल्लो बन्द हुन्छ।'),
    _Faq(
        id: 'daily.2',
        topicKey: 'daily',
        color: Color(0xFF0EA5E9),
        qEn: 'Do Daily Test points count?',
        qNe: 'दैनिक परीक्षाका अंक गनिन्छन्?',
        aEn:
            'Yes. They feed your points, your streak and Analytics exactly like any other activity.',
        aNe:
            'गनिन्छन्। अरू गतिविधि जस्तै यसले पनि तपाईंको अंक, स्ट्रिक र एनालिटिक्समा जोडिन्छ।'),
    _Faq(
        id: 'daily.3',
        topicKey: 'daily',
        color: Color(0xFF0EA5E9),
        qEn: 'I missed yesterday — can I still take it?',
        qNe: 'हिजोको छुट्यो — अब दिन मिल्छ?',
        aEn:
            'Past Daily Tests cannot be reopened. Missing one only breaks your streak; the points you already earned stay.',
        aNe:
            'बितेको दैनिक परीक्षा फेरि खुल्दैन। छुटाउँदा स्ट्रिक मात्र टुट्छ, कमाइसकेका अंक रहन्छन्।'),
    // current
    _Faq(
        id: 'current.1',
        topicKey: 'current',
        color: Color(0xFF14B8A6),
        qEn: 'Where does the GK material come from?',
        qNe: 'सामान्य ज्ञानको सामग्री कहाँबाट आउँछ?',
        aEn:
            'Our team prepares and publishes it. New notes appear under GK & Current Affairs.',
        aNe:
            'हाम्रो टोलीले तयार गरेर प्रकाशित गर्छ। नयाँ नोट सामान्य ज्ञान र समसामयिकमा देखिन्छन्।'),
    _Faq(
        id: 'current.2',
        topicKey: 'current',
        color: Color(0xFF14B8A6),
        qEn: 'How often is it updated?',
        qNe: 'कति पटक अपडेट हुन्छ?',
        aEn:
            'New material is added regularly, and the app sends you a notification when it lands.',
        aNe:
            'नियमित रूपमा नयाँ सामग्री थपिन्छ, र आउनेबित्तिकै एपले सूचना पठाउँछ।'),
    _Faq(
        id: 'current.3',
        topicKey: 'current',
        color: Color(0xFF14B8A6),
        qEn: 'Can I read older material?',
        qNe: 'पुरानो सामग्री पढ्न मिल्छ?',
        aEn:
            'Yes. The list keeps earlier entries — scroll down or use the topic filter to find them.',
        aNe:
            'मिल्छ। सूचीमा अघिल्ला सामग्री रहन्छन् — तल स्क्रोल गर्नुहोस् वा विषय फिल्टर प्रयोग गर्नुहोस्।'),
    // progress
    _Faq(
        id: 'progress.1',
        topicKey: 'progress',
        color: Color(0xFFA855F7),
        qEn: 'How is my profile percentage calculated?',
        qNe: 'प्रोफाइलको प्रतिशत कसरी निस्कन्छ?',
        aEn:
            'It is coverage: how much of all available content you have completed. It is not your accuracy — accuracy is shown as a separate number.',
        aNe:
            'यो कभरेज हो: उपलब्ध सम्पूर्ण सामग्रीमध्ये तपाईंले कति पूरा गर्नुभयो। यो शुद्धता होइन — शुद्धता छुट्टै अंकमा देखिन्छ।'),
    _Faq(
        id: 'progress.2',
        topicKey: 'progress',
        color: Color(0xFFA855F7),
        qEn: 'Why did my percentage go down?',
        qNe: 'मेरो प्रतिशत किन घट्यो?',
        aEn:
            'When new content is added the total grows, so the same work covers a smaller share. It climbs back as you keep studying.',
        aNe:
            'नयाँ सामग्री थपिँदा कुल बढ्छ, त्यसैले उही कामले सानो हिस्सा ओगट्छ। अध्ययन जारी राख्दा फेरि बढ्छ।'),
    _Faq(
        id: 'progress.3',
        topicKey: 'progress',
        color: Color(0xFFA855F7),
        qEn: 'How often does Analytics refresh?',
        qNe: 'एनालिटिक्स कति बेला अपडेट हुन्छ?',
        aEn:
            "A snapshot is stored once a day, so today's activity can take a few hours to appear in the trend charts.",
        aNe:
            'दिनको एक पटक स्न्यापशट राखिन्छ, त्यसैले आजको गतिविधि ट्रेन्ड चार्टमा देखिन केही घण्टा लाग्न सक्छ।'),
    // account
    _Faq(
        id: 'account.1',
        topicKey: 'account',
        color: Color(0xFFEC4899),
        qEn: 'Can I use one account on two phones?',
        qNe: 'एउटै खाता दुई फोनमा चलाउन मिल्छ?',
        aEn:
            'No. An account works on one device at a time. Logging in somewhere else signs the older device out.',
        aNe:
            'मिल्दैन। एक खाता एक पटकमा एउटै डिभाइसमा चल्छ। अन्तै लगइन गर्दा पुरानो डिभाइस लगआउट हुन्छ।'),
    _Faq(
        id: 'account.2',
        topicKey: 'account',
        color: Color(0xFFEC4899),
        qEn: 'How do I change my name or photo?',
        qNe: 'नाम वा फोटो कसरी फेर्ने?',
        aEn: 'Go to Profile → Edit Profile, update the field and save.',
        aNe: 'प्रोफाइल → प्रोफाइल सम्पादनमा गएर फिल्ड अपडेट गरी सेभ गर्नुहोस्।'),
    _Faq(
        id: 'account.3',
        topicKey: 'account',
        color: Color(0xFFEC4899),
        qEn: 'How do I delete my account?',
        qNe: 'खाता कसरी मेटाउने?',
        aEn:
            'Write to us from Help Center → Contact us and we will remove it for you.',
        aNe:
            'हेल्प सेन्टर → सम्पर्कबाट हामीलाई लेख्नुहोस्, हामी मेटाइदिन्छौं।'),
    // app
    _Faq(
        id: 'app.1',
        topicKey: 'app',
        color: Color(0xFF64748B),
        qEn: 'How do I switch language or theme?',
        qNe: 'भाषा वा थिम कसरी फेर्ने?',
        aEn:
            'Both live in Settings — the language toggle, and Light, Dark or System theme.',
        aNe:
            'दुवै सेटिङमा छन् — भाषा टगल, र लाइट, डार्क वा सिस्टम थिम।'),
    _Faq(
        id: 'app.2',
        topicKey: 'app',
        color: Color(0xFF64748B),
        qEn: 'I am not getting notifications.',
        qNe: 'मलाई सूचना आइरहेको छैन।',
        aEn:
            'Allow notifications for the app in your phone settings, then open the app once so it can register this device.',
        aNe:
            'फोनको सेटिङमा एपलाई सूचनाको अनुमति दिनुहोस्, त्यसपछि एक पटक एप खोल्नुहोस् ताकि यो डिभाइस दर्ता होस्।'),
    _Faq(
        id: 'app.3',
        topicKey: 'app',
        color: Color(0xFF64748B),
        qEn: 'How do I report a problem?',
        qNe: 'समस्या कसरी रिपोर्ट गर्ने?',
        aEn:
            'Help Center → Report a problem, or tap the report icon on the screen where the problem happened.',
        aNe:
            'हेल्प सेन्टर → समस्या रिपोर्ट गर्नुहोस्, वा जुन स्क्रिनमा समस्या भयो त्यहीँको रिपोर्ट आइकन थिच्नुहोस्।'),
  ];

  final TextEditingController _search = TextEditingController();
  String? _topic;
  String? _openId;
  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  String get _query => _search.text.trim().toLowerCase();

  List<_Faq> get _items {
    final q = _query;
    if (q.isNotEmpty) {
      // A live query outranks the chip: it matches questions AND answers.
      return _faqs
          .where((f) =>
              AppLanguage.tr(f.qEn, f.qNe).toLowerCase().contains(q) ||
              AppLanguage.tr(f.aEn, f.aNe).toLowerCase().contains(q))
          .toList();
    }
    if (_topic != null) {
      return _faqs.where((f) => f.topicKey == _topic).toList();
    }
    return _faqs;
  }

  void _selectTopic(String? key) {
    setState(() {
      _topic = key;
      // Selecting a chip clears the open FAQ (one-open-at-a-time).
      _openId = null;
    });
  }

  /// 1s preloading shimmer shown on first build before the page content.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final query = _query;
    final items = _items;

    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Help Center', 'सहायता केन्द्र')),
          Expanded(
            child: _preloading
                ? _preloadingBody()
                : ListView(
              padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
              children: [
                // ===== Hero =====
                SyllabusEntrance(
                  delayMs: 0,
                  child: Container(
                    padding: const EdgeInsets.all(ExpoSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.primary
                          .withValues(alpha: 0x14 / 0xFF),
                      borderRadius: BorderRadius.circular(ExpoRadius.lg),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            borderRadius: BorderRadius.circular(19),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.help,
                              size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguage.tr(
                                    'Help Center', 'सहायता केन्द्र'),
                                style: const TextStyle(
                                  fontSize: ExpoType.bodyLarge,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLanguage.tr(
                                  'Answers to the questions we hear most.',
                                  'हामीले बेला-बेला सुन्ने प्रश्नका जवाफहरू।',
                                ),
                                style: TextStyle(
                                  fontSize: ExpoType.caption,
                                  color: palette.textSecondary,
                                  height: 17 / 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Search =====
                SyllabusEntrance(
                  delayMs: 60,
                  child: TextField(
                    controller: _search,
                    style: TextStyle(
                        fontSize: ExpoType.body,
                        color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: AppLanguage.tr(
                          'Search FAQs', 'प्रश्नहरू खोज्नुहोस्'),
                      hintStyle:
                          TextStyle(color: palette.textDisabled),
                      prefixIcon: Icon(Icons.search,
                          size: 20, color: palette.textSecondary),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .deleteButtonTooltip,
                              icon: Icon(Icons.close,
                                  size: 18,
                                  color: palette.textSecondary),
                              onPressed: _search.clear,
                            ),
                      filled: true,
                      fillColor: palette.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: palette.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Topic chips (hidden while searching) =====
                // Syllabus-style per-item cascade: the AnimatedSwitcher only
                // swaps chips vs. the hidden placeholder; each chip entrance
                // replays when the chip row remounts (query cleared).
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: query.isNotEmpty
                      ? const SizedBox.shrink(
                          key: ValueKey('chips-hidden'))
                      : SingleChildScrollView(
                          key: const ValueKey('chips'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              SyllabusEntrance(
                                delayMs: 120,
                                child: _chip(
                                  palette: palette,
                                  label: AppLanguage.tr(
                                      'All topics', 'सबै विषय'),
                                  color: palette.primary,
                                  active: _topic == null,
                                  onTap: () => _selectTopic(null),
                                ),
                              ),
                              ..._topics.asMap().entries.map((e) {
                                final t = e.value;
                                return Padding(
                                  padding: const EdgeInsets.only(
                                      left: 8),
                                  child: SyllabusEntrance(
                                    delayMs:
                                        120 + min(e.key + 1, 8) * 60,
                                    child: _chip(
                                      palette: palette,
                                      icon: t.icon,
                                      label: AppLanguage.tr(
                                          t.nameEn, t.nameNe),
                                      color: t.color,
                                      active: _topic == t.key,
                                      onTap: () => _selectTopic(
                                          _topic == t.key
                                              ? null
                                              : t.key),
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                // ===== FAQ =====
                items.isEmpty
                    ? SyllabusEntrance(
                        delayMs: 180,
                        child: Container(
                          padding: const EdgeInsets.all(
                              ExpoSpacing.lg),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(
                                ExpoRadius.lg),
                            border:
                                Border.all(color: palette.border),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.search,
                                  size: 26,
                                  color: palette.textDisabled),
                              const SizedBox(height: 6),
                              Text(
                                AppLanguage.tr(
                                    'No FAQ available yet',
                                    'अझ FAQ उपलब्ध छैन'),
                                style: const TextStyle(
                                    fontSize: ExpoType.bodySmall,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLanguage.tr(
                                  'We are writing the answers — check back soon.',
                                  'जवाफ लेखिँदैछ — फेरि हेर्नुहोस्।',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: ExpoType.caption,
                                  color: palette.textSecondary,
                                  height: 17 / 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(
                              ExpoRadius.lg),
                          border:
                              Border.all(color: palette.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0;
                                i < items.length;
                                i++) ...[
                              if (i > 0)
                                Divider(
                                    height: 1,
                                    indent: 16,
                                    color: palette.divider),
                              // ValueKey keeps already-visible rows from
                              // replaying when the search query reshapes
                              // the list.
                              SyllabusEntrance(
                                key: ValueKey(items[i].id),
                                delayMs: 180 + min(i, 8) * 60,
                                child: _faqRow(items[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                const SizedBox(height: 16),

                // ===== Still stuck =====
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SyllabusEntrance(
                      delayMs: 240,
                      child: Text(
                        AppLanguage.tr(
                            'Still stuck?', 'अझ अप्ठ्यारो भयो?'),
                        style: const TextStyle(
                          fontSize: ExpoType.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius:
                            BorderRadius.circular(ExpoRadius.lg),
                        border: Border.all(color: palette.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          SyllabusEntrance(
                            delayMs: 240,
                            child: _actionRow(
                              palette: palette,
                              icon: Icons.warning_amber_outlined,
                              color: const Color(0xFFEF4444),
                              title: AppLanguage.tr('Report a Problem',
                                  'समस्या रिपोर्ट गर्नुहोस्'),
                              desc: AppLanguage.tr(
                                'Describe what went wrong — it reaches the team.',
                                'के गडबड भयो लेख्नुहोस् — टोलीसम्म पुग्छ।',
                              ),
                              onTap: () => context
                                  .push('/settings/report-problem'),
                            ),
                          ),
                          Divider(
                              height: 1,
                              indent: 16,
                              color: palette.divider),
                          SyllabusEntrance(
                            delayMs: 300,
                            child: _actionRow(
                              palette: palette,
                              icon: Icons.chat_bubble_outline,
                              color: const Color(0xFF0EA5E9),
                              title: AppLanguage.tr(
                                  'Contact Us', 'सम्पर्क गर्नुहोस्'),
                              desc: AppLanguage.tr(
                                'Email or call us directly.',
                                'सिधै इमेल वा फोन गर्नुहोस्।',
                              ),
                              onTap: () =>
                                  context.push('/contact-us'),
                            ),
                          ),
                          Divider(
                              height: 1,
                              indent: 16,
                              color: palette.divider),
                          SyllabusEntrance(
                            delayMs: 360,
                            child: _actionRow(
                              palette: palette,
                              icon: Icons.star_outline,
                              color: const Color(0xFFF59E0B),
                              title: AppLanguage.tr(
                                  'Feedback', 'प्रतिक्रिया'),
                              desc: AppLanguage.tr(
                                'Tell us what you like or what to improve.',
                                'मन परेको र सुधार्नुपर्ने कुरा भन्नुहोस्।',
                              ),
                              onTap: () =>
                                  context.push('/feedback'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ===== Reach us directly =====
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SyllabusEntrance(
                      delayMs: 300,
                      child: Text(
                        AppLanguage.tr(
                            'Still stuck? Reach us directly',
                            'अझ अप्ठ्यारो भयो? सिधै सम्पर्क गर्नुहोस्'),
                        style: const TextStyle(
                          fontSize: ExpoType.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius:
                            BorderRadius.circular(ExpoRadius.lg),
                        border: Border.all(color: palette.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          SyllabusEntrance(
                            delayMs: 300,
                            child: _contactRow(
                              palette: palette,
                              icon: Icons.mail_outline,
                              label: AppLanguage.tr(
                                  'Email us', 'इमेल गर्नुहोस्'),
                              value: 'contact@kbr.com.np',
                            ),
                          ),
                          Divider(
                              height: 1,
                              indent: 16,
                              color: palette.divider),
                          SyllabusEntrance(
                            delayMs: 360,
                            child: _contactRow(
                              palette: palette,
                              icon: Icons.call_outlined,
                              label: AppLanguage.tr(
                                  'Call us', 'फोन गर्नुहोस्'),
                              value: '+977-9810768297',
                            ),
                          ),
                          Divider(
                              height: 1,
                              indent: 16,
                              color: palette.divider),
                          SyllabusEntrance(
                            delayMs: 420,
                            child: _contactRow(
                              palette: palette,
                              icon: Icons.language,
                              label: AppLanguage.tr(
                                  'Visit our website',
                                  'हाम्रो वेबसाइट हेर्नुहोस्'),
                              value: 'kbr.com.np',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ===== Footnote =====
                SyllabusEntrance(
                  delayMs: 360,
                  child: Text(
                    AppLanguage.tr(
                      'Most reports get a response within 1-2 working days.',
                      'धेरैजसो रिपोर्टको जवाफ १-२ कार्यदिनभित्र आउँछ।',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: ExpoType.caption,
                      color: palette.textSecondary,
                      height: 17 / 11,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Topic filter pill — fills with its own hue when active.
  Widget _chip({
    required ExpoPalette palette,
    IconData? icon,
    required String label,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ExpoRadius.pill),
          color: active ? color : palette.surface,
          border: Border.all(color: active ? color : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13, color: active ? Colors.white : color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: ExpoType.caption,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One FAQ question. Only one row is open at a time; the open answer
  /// fades in, indented past the icon box.
  Widget _faqRow(_Faq item) {
    final open = _openId == item.id;
    return Column(
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _openId = open ? null : item.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(ExpoSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: item.color
                        .withValues(alpha: 0x1F / 0xFF),
                    borderRadius:
                        BorderRadius.circular(ExpoRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.help,
                      size: 13, color: item.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLanguage.tr(item.qEn, item.qNe),
                    style: const TextStyle(
                      fontSize: ExpoType.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: ExpoPalette.of(context).textSecondary,
                ),
              ],
            ),
          ),
        ),
        // The open answer fades in (mirrors React's FadeIn entering).
        // Conditional like React: only the open row keeps its answer mounted.
        if (open)
          _FadeIn(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
              child: Text(
                AppLanguage.tr(item.aEn, item.aNe),
                style: TextStyle(
                  fontSize: ExpoType.caption,
                  color: ExpoPalette.of(context).textSecondary,
                  height: 17 / 11,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionRow({
    required ExpoPalette palette,
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(ExpoSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0x1F / 0xFF),
                borderRadius:
                    BorderRadius.circular(ExpoRadius.md),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: ExpoType.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ExpoType.caption,
                      color: palette.textSecondary,
                      height: 17 / 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 17, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Display-only row — no url_launcher in this project, so it is not tappable.
  Widget _contactRow({
    required ExpoPalette palette,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.primary
                  .withValues(alpha: 0x17 / 0xFF),
              borderRadius: BorderRadius.circular(ExpoRadius.md),
            ),
            alignment: Alignment.center,
            child:
                Icon(icon, size: 19, color: palette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: ExpoType.caption,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: ExpoType.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_new,
              size: 17, color: palette.textSecondary),
        ],
      ),
    );
  }
}
