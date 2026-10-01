import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/animated_star_rating.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Feedback — mirrors app/feedback.tsx.
///
/// Premium redesign: gradient hero band, animated star rating with a
/// scale-pop on every tap ([AnimatedStarRating]), and the rating tone
/// (success / warning / danger) reflected in the stars and the label pill.
/// 1–5 star rating (gated: tapping Submit with no rating warns) + optional
/// message. Submission posts to the team's Google Form via
/// [ReportService.submitFeedback] — the same pipeline as React.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  /// Rating labels — English + pure Devanagari pair.
  static const _labels = ['', 'Very poor', 'Poor', 'Okay', 'Good', 'Excellent'];
  static const _labelsNe = [
    '',
    'धेरै नराम्रो',
    'नराम्रो',
    'ठीकै',
    'राम्रो',
    'उत्कृष्ट'
  ];

  int _rating = 0;
  final _message = TextEditingController();
  bool _sending = false;
  bool? _offline;
  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    _checkOnline();
    // Premium preloading shimmer (~1.5s): this page has no database fetch,
    // so without it the content would pop in instantly and look cheap.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _preloading = false);
    });
  }

  Future<void> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(
          () => _offline = results.every((r) => r == ConnectivityResult.none));
    } catch (_) {
      if (mounted) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Tone follows the score: 4–5 green, 3 amber, 1–2 red, none grey.
  Color _tone() {
    if (_rating >= 4) return const Color(0xFF16A34A);
    if (_rating == 3) return const Color(0xFFD97706);
    if (_rating > 0) return const Color(0xFFDC2626);
    return Colors.grey;
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      showToast(
        context,
        AppLanguage.tr(
            'Please choose a star rating first', 'पहिले स्टार रेटिङ छान्नुहोस्'),
        ToastVariant.warning,
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await ReportService.submitFeedback(_rating, _message.text.trim());
      if (!mounted) return;
      showToast(
        context,
        AppLanguage.tr('Thank you for your feedback!',
            'तपाईंको प्रतिक्रियाको लागि धन्यवाद!'),
        ToastVariant.success,
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
        ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _hero(BuildContext context) {
    return SyllabusEntrance(
      delayMs: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB91C1C).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -36,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguage.tr('Feedback', 'प्रतिक्रिया'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLanguage.tr(
                              'Your feedback directly shapes what we build next. Thank you for taking a moment.',
                              'तपाईंको प्रतिक्रियाले नै हामीले के बनाउँछौँ भन्ने निर्धारण गर्छ। समय दिनुभएकोमा धन्यवाद।'),
                          style: const TextStyle(
                              color: Color(0xFFFED7D7),
                              fontSize: 13,
                              height: 1.5),
                        ),
                      ],
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

  Widget _ratingCard(BuildContext context) {
    final tone = _tone();
    return SyllabusEntrance(
      delayMs: 60,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.star_rounded, size: 20, color: tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLanguage.tr(
                          'How would you rate the app?',
                          'एपलाई कति नम्बर दिनुहुन्छ?'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // AnimatedStarRating: tapping a star plays a scale-pop
              // (~1.25x then settles, snappy easeOut). Filled stars take
              // the rating's tone; empty stars stay the neutral default.
              Center(
                child: AnimatedStarRating(
                  value: _rating,
                  onChanged: (v) => setState(() => _rating = v),
                  size: 44,
                  color: _rating > 0 ? tone : const Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(height: 12),
              // Fixed-height slot: the pill replaces a hint so the card
              // never changes size as you tap.
              SizedBox(
                height: 30,
                child: Center(
                  child: _rating > 0
                      ? StatusPill(
                          label: AppLanguage.tr(
                              _labels[_rating], _labelsNe[_rating]),
                          color: tone,
                          icon: Icons.auto_awesome_outlined,
                        )
                      : Text(
                          AppLanguage.tr('Tap a star to rate',
                              'रेट गर्न स्टारमा ट्याप गर्नुहोस्'),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageCard(BuildContext context) {
    return SyllabusEntrance(
      delayMs: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.edit_outlined,
                        size: 20, color: Color(0xFF0EA5E9)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguage.tr(
                              'Tell us more (optional)', 'अझ बताउनुहोस् (वैकल्पिक)'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppLanguage.tr(
                              'What did you like? What should we improve?',
                              'तपाईंलाई के मन पर्यो? हामीले के सुधार्नुपर्छ?'),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                maxLines: 5,
                minLines: 5,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: AppLanguage.tr('Write your feedback…',
                      'आफ्नो प्रतिक्रिया लेख्नुहोस्…'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_rating == 0 || _sending) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(AppLanguage.tr('Submit', 'पेश गर्नुहोस्'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Premium preloading shimmer shown for ~1.5s on first build, before the
  /// page content is revealed.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
    );
  }

  Widget _offlineCard(BuildContext context) {
    return SyllabusEntrance(
      delayMs: 120,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Colors.orange.withValues(alpha: 0.33)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 24, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLanguage.tr(
                        'You are offline. Check your connection and try again.',
                        'तपाईं अफलाइन हुनुहुन्छ। जडान जाँचेर फेरि प्रयास गर्नुहोस्।'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.orange),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLanguage.tr('This requires an internet connection',
                        'यसका लागि इन्टरनेट जडान आवश्यक छ'),
                    style:
                        const TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offline = _offline == true;
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: AppLanguage.tr('Feedback', 'प्रतिक्रिया')),
          Expanded(
            child: _preloading
                ? _preloadingBody()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _hero(context),
                      const SizedBox(height: 14),
                      _ratingCard(context),
                      const SizedBox(height: 14),
                      if (offline) _offlineCard(context) else _messageCard(context),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
