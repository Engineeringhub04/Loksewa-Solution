// DiscussionCommentCard — mirrors the React CommentCard. Compact white
// card (radius 12, 0xFFE2E8F0 border): 28px avatar + 12px semibold name +
// 10px grey comment date (editedAt is NEVER displayed), 13px body, action
// row with a small heart (1.24 pop / 110ms up / 150ms down), and the
// overflow menu (which reports the button's global anchor offset via
// [onMenu] for the DiscussionActionMenu).
//
// Replies indent 40px from the left with a small vertical connector line.
//
// The "View replies"/"Hide replies" toggle, the Reply button, and the
// inline reply composer are NOT rendered here — the detail screen places
// them below each card.
//
// No emojis; every Text carries `decoration: TextDecoration.none`.
import 'package:flutter/material.dart';

import '../../services/discussion_service.dart';
import '../../theme/app_theme.dart';
import 'discussion_avatar.dart';
import 'discussion_heart_like.dart';
import 'discussion_link_text.dart';
import 'discussion_pressed.dart';

class DiscussionCommentCard extends StatelessWidget {
  final DiscussionComment comment;
  final bool isReply;
  final bool liked;
  final Future<void> Function(bool) onToggleLike;
  final ValueChanged<Offset> onMenu;

  const DiscussionCommentCard({
    super.key,
    required this.comment,
    required this.isReply,
    required this.liked,
    required this.onToggleLike,
    required this.onMenu,
  });

  Color _border(BuildContext context) => ExpoPalette.of(context).border;
  Color _navy(BuildContext context) => ExpoPalette.of(context).textPrimary;
  Color _grey(BuildContext context) => ExpoPalette.of(context).textSecondary;
  Color _bodyGrey(BuildContext context) => ExpoPalette.of(context).textSecondary;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DiscussionAvatar(
                photoUrl: comment.authorPhoto,
                name: comment.authorName,
                radius: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                // React parity: horizontal author row — name (flex 1, 1 line)
                // + timestamp (caption) + menu, all center-aligned.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _navy(context),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatDiscussionCommentDate(comment.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: _grey(context),
                        decoration: TextDecoration.none,
                      ),
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
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_vert,
                      size: 16,
                      color: _grey(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DiscussionLinkText(
            text: comment.body,
            confirmBeforeOpen: true,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: _bodyGrey(context),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              DiscussionHeartLike(
                initialLiked: liked,
                likeCount: comment.likeCount,
                onToggle: onToggleLike,
                heartSize: 17,
                compact: true,
                popScale: 1.24,
                popUpMs: 110,
                popDownMs: 150,
              ),
            ],
          ),
        ],
      ),
    );

    if (!isReply) return card;

    // Reply indentation: 40px left margin + a small vertical connector line
    // in the gutter.
    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -22,
            top: 6,
            bottom: 6,
            child: Container(
              width: 2,
              color: _border(context),
            ),
          ),
          card,
        ],
      ),
    );
  }
}
