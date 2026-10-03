// DiscussionPostCard — feed card mirroring the React DiscussionPostCard.
// iPhone-minimal compact: white card, 0xFFE2E8F0 border, radius 14,
// ~12 padding. Admin posts get a 3px primary-colored vertical accent bar
// spanning the card's left edge plus a primary-colored title.
//
// The image thumbnail is NOT wired to any viewer here — tapping it calls
// [onImageTap] and the parent decides what opens. The overflow menu button
// calls [onMenu] with the button's global bottom-right offset so the parent
// can anchor the DiscussionActionMenu there. Like state is never read here:
// [liked] comes from the parent.
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../services/discussion_service.dart';
import 'discussion_avatar.dart';
import 'discussion_heart_like.dart';
import 'discussion_pressed.dart';

class DiscussionPostCard extends StatelessWidget {
  final DiscussionPost post;
  final bool liked;
  final Future<void> Function(bool) onToggleLike;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final VoidCallback? onImageTap;

  const DiscussionPostCard({
    super.key,
    required this.post,
    required this.liked,
    required this.onToggleLike,
    required this.onTap,
    required this.onMenu,
    this.onImageTap,
  });

  static const _border = Color(0xFFE2E8F0);
  static const _navy = Color(0xFF0F172A);
  static const _grey = Color(0xFF64748B);
  static const _bodyGrey = Color(0xFF475569);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final category = discussionCategoryFromValue(post.category);
    final lang = AppLanguage.current.value;
    final imageUrl = (post.imageUrl ?? '').trim();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header + title + body are the card-tap zone (footer buttons and
        // the image live outside it so nested taps never double-fire).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DiscussionAvatar(
                      photoUrl: post.authorPhoto,
                      name: post.authorName,
                      radius: 17,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _navy,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
                if (category != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      discussionCategoryLabel(category, lang),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: primary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                if (post.title.isNotEmpty)
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: post.isAdmin ? primary : _navy,
                      decoration: TextDecoration.none,
                    ),
                  ),
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: _bodyGrey,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (imageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: DiscussionPressed(
              onTap: onImageTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFF1F5F8),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        size: 28,
                        color: _grey,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              DiscussionHeartLike(
                initialLiked: liked,
                likeCount: post.likeCount,
                onToggle: onToggleLike,
                heartSize: 18,
                compact: true,
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: _grey,
              ),
              const SizedBox(width: 4),
              Text(
                '${post.commentCount}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _grey,
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              Text(
                formatDiscussionFeedDate(post.createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: _grey,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 2),
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
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: _grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: post.isAdmin
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: primary),
                    Expanded(child: content),
                  ],
                ),
              ),
            )
          : content,
    );
  }
}
