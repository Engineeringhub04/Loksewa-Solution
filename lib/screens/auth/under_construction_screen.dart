import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Fallback destination for feature buttons that don't have a real page yet —
/// mirrors app/under-construction.tsx. Pass ?page=Feature Name to customize
/// the title. The progress percent is a stable FNV-1a hash of the page name
/// (20–70% in 5-point steps), exactly like the original.
class UnderConstructionScreen extends StatelessWidget {
  const UnderConstructionScreen({super.key});

  static int progressForPage(String page) {
    var hash = 0x811c9dc5;
    final key = page.trim().toLowerCase();
    for (var i = 0; i < key.length; i++) {
      hash ^= key.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 20 + (hash % 11) * 5;
  }

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final pageName = params['page'] ?? 'This Feature';
    final percent = progressForPage(pageName);

    return Scaffold(
      appBar: AppBar(title: Text(pageName)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.navy,
                          Color(0xFF2D5BFF)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.construction,
                        size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.handyman,
                            size: 12, color: AppColors.accent),
                        SizedBox(width: 5),
                        Text(
                          'IN PROGRESS',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    pageName,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Under construction',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "We're building this feature right now. It will be available in an upcoming update.",
                    style: TextStyle(
                        color: Colors.grey, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          const AlwaysStoppedAnimation(
                              AppColors.navy),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$percent% complete',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  const Divider(height: 30),
                  const Text(
                    'Thanks for your patience.',
                    style:
                        TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Go Back'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
