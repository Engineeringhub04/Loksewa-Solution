// Renders discussion body text with tappable auto-links.
// Mirrors the Expo body rendering: bare URLs + www. links are detected,
// bare www. gets an https:// scheme before opening (see
// normalizeDiscussionUrl), and taps open the external browser.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/discussion_service.dart';
import '../../widgets/app_toast.dart';
import '../../services/app_language.dart';
import 'discussion_confirm_dialog.dart';

class DiscussionLinkText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;

  /// React parity (DiscussionPostCard): show an "Open this link?" confirm
  /// before leaving the app. Defaults to false so existing callers
  /// (detail screen) keep their direct-open behavior.
  final bool confirmBeforeOpen;

  const DiscussionLinkText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.confirmBeforeOpen = false,
  });

  Future<void> _open(BuildContext context, String raw) async {
    if (confirmBeforeOpen && context.mounted) {
      final ok = await confirmDiscussionAction(
        context: context,
        title: AppLanguage.tr('Open this link?', 'यो लिंक खोल्ने?'),
        message: AppLanguage.tr(
            'This link was posted by another user and will open outside the app.',
            'यो लिंक अर्को प्रयोगकर्ताले राखेको हो र एप बाहिर खुल्नेछ।'),
        confirmLabel: AppLanguage.tr('Open', 'खोल्नुहोस्'),
      );
      if (ok != true || !context.mounted) return;
    }
    final url = normalizeDiscussionUrl(raw);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // Fall through to copy.
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      showToast(context, AppLanguage.tr('Link copied', 'लिङ्क कपी भयो'),
          ToastVariant.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final segs = splitDiscussionLinks(text);
    return RichText(
      text: TextSpan(
        children: segs.map((s) {
          if (!s.isLink) {
            return TextSpan(text: s.text, style: style);
          }
          return TextSpan(
            text: s.text,
            style: linkStyle ??
                style.copyWith(
                  color: primary,
                  decoration: TextDecoration.underline,
                ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open(context, s.text),
          );
        }).toList(),
      ),
    );
  }
}
