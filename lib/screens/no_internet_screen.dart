import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/app_language.dart';
import '../theme/app_theme.dart';
import '../widgets/preloading.dart';

/// No-internet blocking screen — shown on cold start when offline and signed out.
class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
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
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: _preloading
              ? _preloadingBody()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 64, color: Colors.white70),
                      const SizedBox(height: 24),
                      Text(
                        AppLanguage.tr(
                            'No Internet Connection', 'इन्टरनेट जडान छैन'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppLanguage.tr(
                            'Please connect to the internet and try again.',
                            'कृपया इन्टरनेटमा जडान भएर फेरि प्रयास गर्नुहोस्।'),
                        style: const TextStyle(
                            color: Color(0xFFD7E3FF), fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.go('/splash'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(AppLanguage.tr('Retry', 'पुन: प्रयास')),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
