import 'package:flutter/material.dart';
import '../services/app_language.dart';
import '../theme/app_theme.dart';
import '../widgets/preloading.dart';

/// Maintenance blocking screen — shown when remote config enables it.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
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
                      const Icon(Icons.build, size: 64, color: Colors.white70),
                      const SizedBox(height: 24),
                      Text(
                        AppLanguage.tr(
                            'Under Maintenance', 'मर्मतसम्भार भइरहेको छ'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppLanguage.tr(
                            'Loksewa Solution is being updated. Please check back soon.',
                            'Loksewa Solution अपडेट भइरहेको छ। कृपया केही समयपछि फेरि आउनुहोस्।'),
                        style: const TextStyle(
                            color: Color(0xFFD7E3FF), fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
