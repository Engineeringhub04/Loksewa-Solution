// Standalone exam-set purchase landing.
// Mirrors app/exam-purchase/[id].tsx: fetches one exam set, shows a
// primary-tinted hero (document icon for pdf sets, help icon otherwise),
// a details card, a primary price card, and a Continue-to-Payment button
// that routes to the checkout screen with the exam id.
//
// This is the STANDALONE flow (exam tab -> buy a single exam set), distinct
// from app/subscription/exam-purchase/[id] (the purchase-REQUEST detail
// after checkout: status, edit window, receipt).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

class ExamPurchaseScreen extends StatefulWidget {
  final String id;
  const ExamPurchaseScreen({super.key, required this.id});

  @override
  State<ExamPurchaseScreen> createState() => _ExamPurchaseScreenState();
}

class _ExamPurchaseScreenState extends State<ExamPurchaseScreen> {
  late Future<Map<String, dynamic>?> _future;

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_exam_sets/${widget.id}',
        idToken: token);
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      body: Column(
        children: [
          FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              final set = snap.data;
              // React: title is the loading string until the exam settles.
              final title = snap.connectionState == ConnectionState.waiting
                  ? _t('Loading Subscription...', 'सदस्यता लोड हुँदैछ...')
                  : (set?['title']?.toString().isNotEmpty ?? false)
                      ? set!['title'].toString()
                      : _t('Exam Purchase', 'परीक्षा खरिद');
              return SubpageHeader(title: title);
            },
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return PreloadingWidget(
                    tinted: false,
                    label: _t('Loading Subscription...',
                        'सदस्यता लोड हुँदैछ...'),
                    hint: _t('Fetching your purchase history',
                        'खरिद इतिहास ल्याउँदै'),
                  );
                }
                if (snap.hasError || snap.data == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _t('Could not load this exam set.',
                                'यो परीक्षा सेट लोड गर्न सकिएन।'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () =>
                                setState(() => _future = _load()),
                            child: Text(
                                _t('Retry', 'पुनः प्रयास गर्नुहोस्')),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final set = snap.data!;
                final isPdf = (set['contentType']?.toString() ?? '')
                        .toLowerCase() ==
                    'pdf';
                final title = set['title']?.toString() ?? 'Exam Set';
                final price = _money(set['price']);
                final currency = set['currency']?.toString() ?? 'NPR';

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero: primary-tinted, icon by content type.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: palette.primary
                              .withValues(alpha: 0x12 / 0xFF),
                          border: Border.all(
                            color: palette.primary
                                .withValues(alpha: 0x35 / 0xFF),
                          ),
                          borderRadius:
                              BorderRadius.circular(ExpoRadius.lg),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.primary
                                    .withValues(alpha: 0x20 / 0xFF),
                                borderRadius: BorderRadius.circular(
                                    ExpoRadius.md),
                              ),
                              child: Icon(
                                isPdf
                                    ? Icons.description_outlined
                                    : Icons.help_outline,
                                size: 28,
                                color: palette.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: ExpoType.h3,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _t('Premium exam access',
                                        'प्रिमियम परीक्षा पहुँच'),
                                    style: TextStyle(
                                      fontSize: ExpoType.bodySmall,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Details card.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          border: Border.all(
                              color: palette.border, width: 0.5),
                          borderRadius:
                              BorderRadius.circular(ExpoRadius.lg),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _t('Exam Details', 'परीक्षा विवरण'),
                              style: const TextStyle(
                                fontSize: ExpoType.bodyLarge,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            _detailRow(
                                palette,
                                _t('Content type', 'सामग्रीको प्रकार'),
                                isPdf ? 'Theory Desk' : 'MCQ'),
                            _detailRow(
                                palette,
                                _t('Questions', 'प्रश्नहरू'),
                                '${set['totalQuestions'] ?? '—'}'),
                            _detailRow(
                                palette,
                                _t('Duration', 'समयावधि'),
                                set['durationMinutes'] != null
                                    ? "${set['durationMinutes']} ${_t('minutes', 'मिनेट')}"
                                    : '—'),
                            _detailRow(
                                palette,
                                _t('Difficulty', 'कठिनाइ'),
                                set['difficulty']?.toString() ?? '—'),
                            _detailRow(
                                palette,
                                _t('Pass percentage', 'उत्तीर्ण प्रतिशत'),
                                set['passPercent'] != null
                                    ? '${set['passPercent']}%'
                                    : '—',
                                last: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Price card: solid primary, white text.
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: palette.primary,
                          borderRadius:
                              BorderRadius.circular(ExpoRadius.lg),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('Purchase price', 'खरिद मूल्य'),
                              style: TextStyle(
                                fontSize: ExpoType.bodySmall,
                                color: Colors.white
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Rs. $price $currency',
                              style: const TextStyle(
                                fontSize: 28.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                          ),
                          // React replaces onto /subscription/checkout with
                          // the exam id; the Flutter checkout route is
                          // '/checkout' (query param carries the id).
                          onPressed: () => context.pushReplacement(
                              '/checkout?examId=${widget.id}'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _t('Continue to Payment',
                                    'भुक्तानीमा जानुहोस्'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward,
                                  size: 18),
                            ],
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
    );
  }

  Widget _detailRow(
      ExpoPalette palette, String label, String value,
      {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                    color: palette.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: ExpoType.bodySmall,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: ExpoType.bodySmall,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
