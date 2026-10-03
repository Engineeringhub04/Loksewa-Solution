// Sign-in prompt shown when a signed-out user taps like / comment / post.
// All popups app-wide use the shared AppModalShell.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

class DiscussionSignInPrompt {
  static Future<void> show(BuildContext context) {
    return AppModalShell.show<void>(
      context: context,
      builder: (_) => _Body(rootContext: context),
    );
  }
}

class _Body extends StatelessWidget {
  final BuildContext rootContext;

  const _Body({required this.rootContext});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLanguage.tr('Sign in required', 'साइन इन आवश्यक छ'),
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none),
        ),
        const SizedBox(height: 8),
        Text(
          AppLanguage.tr('Please sign in to like, comment or post.',
              'लाइक, कमेन्ट वा पोस्ट गर्न कृपया साइन इन गर्नुहोस्।'),
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              decoration: TextDecoration.none),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                    style:
                        const TextStyle(decoration: TextDecoration.none)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.of(context).pop();
                  rootContext.push('/login');
                },
                child: Text(AppLanguage.tr('Sign In', 'साइन इन'),
                    style:
                        const TextStyle(decoration: TextDecoration.none)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
