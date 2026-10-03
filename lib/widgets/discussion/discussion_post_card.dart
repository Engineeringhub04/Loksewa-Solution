// DiscussionPostCard — feed card, same-to-same with
// src/components/cards/DiscussionPostCard.tsx:
// - top row: 46px avatar, name + admin badge, timestamp · subcourse, menu
// - title row with 4px primary accent bar (title only, max 2 lines)
// - body with tappable auto-links (confirm-before-open), bold-body rule
// - 178px image frame with "tap to zoom" overlay → parent opens viewer
// - link preview row (confirm-before-open)
// - action row (hairline top border): like + comments + Featured + chevron
//
// The image thumbnail is NOT wired to any viewer here — tapping it calls
// [onImageTap] and the parent decides what opens. The overflow menu button
// calls [onMenu] with the button's global bottom-right offset so the parent
// can anchor the DiscussionActionMenu there. Like state is never read here:
// [liked] comes from the parent.
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_language.dart';
import '../../services/discussion_service.dart';
import 'discussion_avatar.dart';
import 'discussion_confirm_dialog.dart';
import 'discussion_heart_like.dart';
import 'discussion_link_text.dart';
import 'discussion_pressed.dart';
import '../../theme/app_theme.dart';

class DiscussionPostCard extends StatelessWidget {
  final DiscussionPost post;
  final bool liked;
  final Future<void> Function(bool) onToggleLike;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final VoidCallback? onImageTap;

  /// Detail header override: full date+time instead of the feed's date-only.
  final String? timestampOverride;

  const DiscussionPostCard({
    super.key,
    required this.post,
    required this.liked,
    required this.onToggleLike,
    required this.onTap,
    required this.onMenu,
    this.onImageTap,
    this.timestampOverride,
  });

  Color _border(BuildContext context) => ExpoPalette.of(context).border;
  Color _navy(BuildContext context) => ExpoPalette.of(context).textPrimary;
  Color _grey(BuildContext context) => ExpoPalette.of(context).textSecondary;
  Color _bodyGrey(BuildContext context) => ExpoPalette.of(context).textSecondary;
  static const _linkBlue = Color(0xFF2563EB);
  static const _likeRed = Color(0xFFE11D48);
  static const _adminBadgeBg = Color(0xFFFFEDD5);
  static const _adminBadgeFg = Color(0xFF9A3412);

  Future<void> _openLink(BuildContext context, String raw) async {
    final ok = await confirmDiscussionAction(
      context: context,
      title: AppLanguage.tr('Open this link?', 'यो लिंक खोल्ने?'),
      message: AppLanguage.tr(
          'This link was posted by another user and will open outside the app.',
          'यो लिंक अर्को प्रयोगकर्ताले राखेको हो र एप बाहिर खुल्नेछ।'),
      confirmLabel: AppLanguage.tr('Open', 'खोल्नुहोस्'),
    );
    if (ok != true || !context.mounted) return;
    final url = normalizeDiscussionUrl(raw);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final imageUrl = (post.imageUrl ?? '').trim();
    final linkUrl = (post.linkUrl ?? '').trim();
    final subcourse = (post.subcourseName ?? '').trim();
    final hasTitle = post.title.trim().isNotEmpty;
    // React bodyWeight: bold unless (isAdmin && title non-empty).
    final bodyBold = !post.isAdmin || !hasTitle;
    // React: secondary body color when (!isAdmin && title non-empty).
    final bodyColor =
        (!post.isAdmin && hasTitle) ? _grey(context) : _bodyGrey(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: ExpoPalette.of(context).surface,
          border: Border.all(color: _border(context)),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _navy(context).withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top row: avatar, name + admin badge, timestamp · subcourse, menu.
            Row(
              children: [
                DiscussionAvatar(
                  photoUrl: post.authorPhoto,
                  name: post.authorName,
                  radius: 23,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _navy(context),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          if (post.isAdmin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: _adminBadgeBg,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 11,
                                    color: _adminBadgeFg,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Admin',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _adminBadgeFg,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            timestampOverride ??
                                formatDiscussionFeedDate(post.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: _grey(context),
                              decoration: TextDecoration.none,
                            ),
                          ),
                          if (!post.isAdmin && subcourse.isNotEmpty)
                            Flexible(
                              child: Text(
                                ' · $subcourse',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _grey(context),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (menuCtx) => DiscussionPressed(
                    onTap: () {
                      final box =
                          menuCtx.findRenderObject() as RenderBox?;
                      final pos = box?.localToGlobal(Offset(
                              box.size.width, box.size.height)) ??
                          Offset.zero;
                      onMenu(pos);
                    },
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        Icons.more_horiz,
                        size: 22,
                        color: _grey(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Title with accent bar.
            if (hasTitle) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    constraints:
                        const BoxConstraints(minHeight: 25),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _navy(context),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // Body with tappable links (confirm-before-open).
            if (post.body.isNotEmpty) ...[
              DiscussionLinkText(
                text: post.body,
                confirmBeforeOpen: true,
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  fontWeight:
                      bodyBold ? FontWeight.bold : FontWeight.normal,
                  color: bodyColor,
                  decoration: TextDecoration.none,
                ),
                linkStyle: const TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  color: _linkBlue,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Image frame with tap-to-zoom overlay.
            if (imageUrl.isNotEmpty) ...[
              DiscussionPressed(
                onTap: onImageTap,
                child: Container(
                  height: 178,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F8),
                    border: Border.all(color: _border(context)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          size: 28,
                          color: _grey(context),
                        ),
                      ),
                      Positioned(
                        left: 9,
                        bottom: 9,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A)
                                .withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.crop_free,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                AppLanguage.tr('Tap to zoom',
                                    'ठूलो हेर्न ट्याप गर्नुहोस्'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Link preview row.
            if (linkUrl.isNotEmpty) ...[
              DiscussionPressed(
                onTap: () => _openLink(context, linkUrl),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.06),
                    border: Border.all(
                        color: primary.withValues(alpha: 0.19)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.link,
                          size: 17,
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLanguage.tr('Link preview',
                                  'लिंक प्रस्तुति'),
                              style: TextStyle(
                                fontSize: 12,
                                color: _grey(context),
                                decoration: TextDecoration.none,
                              ),
                            ),
                            Text(
                              linkUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: primary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 17,
                        color: primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Action row.
            Container(
              padding: const EdgeInsets.only(top: 11),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: _border(context), width: 0.5)),
              ),
              child: Row(
                children: [
                  DiscussionHeartLike(
                    initialLiked: liked,
                    likeCount: post.likeCount,
                    onToggle: onToggleLike,
                    heartSize: 20,
                    activeColor: _likeRed,
                    compact: true,
                  ),
                  const SizedBox(width: 17),
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 19,
                    color: _grey(context),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${post.commentCount}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _grey(context),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Spacer(),
                  if (post.isSeed) ...[
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 13,
                      color: primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLanguage.tr('Featured', 'विशेष'),
                      style: TextStyle(
                        fontSize: 12,
                        color: primary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: _grey(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
