import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Feedback — mirrors app/feedback.tsx.
/// 1–5 star rating (gated: tapping Submit with no rating warns) + optional
/// message. Submission posts to the team's Google Form via
/// [ReportService.submitFeedback] — the same pipeline as React.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  /// Rating labels stay English — React hardcodes RATING_LABELS.
  static const _labels = ['', 'Very poor', 'Poor', 'Okay', 'Good', 'Excellent'];

  int _rating = 0;
  final _message = TextEditingController();
  bool _sending = false;
  bool? _offline;

  @override
  void initState() {
    super.initState();
    _checkOnline();
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

  @override
  Widget build(BuildContext context) {
    final offline = _offline == true;
    final tone = _tone();
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Feedback', 'प्रतिक्रिया')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SyllabusEntrance(
                  delayMs: 0,
                  child: Card(
                    color: const Color(0xFFB91C1C),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white
                                      .withValues(alpha: 0x1F / 0xFF),
                                ),
                                child: const Icon(Icons.favorite_outline,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLanguage.tr('Feedback', 'प्रतिक्रिया'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your feedback directly shapes what we build next. Thank you for taking a moment.',
                            style: TextStyle(
                                color: Color(0xFFFED7D7), height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SyllabusEntrance(
                  delayMs: 60,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tone.withValues(
                                      alpha: 0x14 / 0xFF),
                                ),
                                child: Icon(Icons.star_outline,
                                    size: 18, color: tone),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppLanguage.tr(
                                      'How would you rate the app?',
                                      'एपलाई कति नम्बर दिनुहुन्छ?'),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (i) {
                              final value = i + 1;
                              return IconButton(
                                onPressed: () =>
                                    setState(() => _rating = value),
                                tooltip: '$value star${value > 1 ? 's' : ''}',
                                icon: Icon(
                                  value <= _rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 36,
                                  color: value <= _rating
                                      ? tone
                                      : Colors.grey.shade400,
                                ),
                              );
                            }),
                          ),
                          // Fixed-height slot: the pill replaces a hint so
                          // the card never changes size as you tap.
                          SizedBox(
                            height: 30,
                            child: Center(
                              child: _rating > 0
                                  ? StatusPill(
                                      label: _labels[_rating],
                                      color: tone,
                                      icon: Icons.auto_awesome_outlined,
                                    )
                                  : const Text(
                                      'Tap a star to rate',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 13),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (offline)
                  SyllabusEntrance(
                    delayMs: 120,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0x14 / 0xFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange
                                .withValues(alpha: 0x55 / 0xFF)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.cloud_off_outlined,
                              size: 22, color: Colors.orange),
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
                                  AppLanguage.tr(
                                      'This requires an internet connection',
                                      'यसका लागि इन्टरनेट जडान आवश्यक छ'),
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SyllabusEntrance(
                    delayMs: 120,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF0EA5E9)
                                        .withValues(alpha: 0x14 / 0xFF),
                                  ),
                                  child: const Icon(Icons.edit_outlined,
                                      size: 18,
                                      color: Color(0xFF0EA5E9)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLanguage.tr(
                                            'Tell us more (optional)',
                                            'अझ बताउनुहोस् (वैकल्पिक)'),
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        AppLanguage.tr(
                                            'What did you like? What should we improve?',
                                            'तपाईंलाई के मन पर्यो? हामीले के सुधार्नुपर्छ?'),
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _message,
                              maxLines: 5,
                              minLines: 5,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                hintText: AppLanguage.tr(
                                    'Write your feedback…',
                                    'आफ्नो प्रतिक्रिया लेख्नुहोस्…'),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (_rating == 0 || _sending)
                                    ? null
                                    : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.navy,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _sending
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : Text(AppLanguage.tr(
                                        'Submit', 'पेश गर्नुहोस्')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
