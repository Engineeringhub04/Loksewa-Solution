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

class DiscussionLinkText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;

  const DiscussionLinkText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
  });

  Future<void> _open(BuildContext context, String raw) async {
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
