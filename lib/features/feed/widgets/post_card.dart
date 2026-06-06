import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/card_brightness_provider.dart';
import '../../../core/storage/opened_posts_store.dart';
import '../models/feed_post.dart';
import '../../profile/controller/profile_controller.dart';

enum _PostMenuAction { archive, unarchive, edit, bin }

class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.isLiked = false,
    this.isBookmarked = false,
    this.onLike,
    this.onBookmark,
    this.onArchive,
    this.onUnarchive,
    this.onBin,
    this.onEdit,
  });

  final FeedPost post;
  final bool isLiked;
  final bool isBookmarked;
  final VoidCallback? onLike;
  final VoidCallback? onBookmark;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onBin;
  final VoidCallback? onEdit;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isCardDark = cardBrightness == Brightness.dark;

    // Match the swipe card palette.
    final cardBg = isCardDark ? cardCharcoalDark : cardCreamLight;
    final cardBorder = isCardDark ? cardCharcoalEdge : cardCreamEdge;
    final cardText = isCardDark ? cardCharcoalText : cardCreamText;
    final cardSub = isCardDark ? cardCharcoalSubtext : cardCreamSubtext;
    final cardAccent = isCardDark ? cardCharcoalAccent : cardCreamAccent;
    final cardMid = isCardDark ? cardCharcoalMid : cardCreamMid;

    final post = widget.post;

    final meId = ref.watch(currentUserIdProvider).valueOrNull;
    final isSelfPost = meId != null && meId == post.authorId;

    final titleStyle = GoogleFonts.lora(
      textStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: cardText,
      ),
    );

    final bodyStyle = GoogleFonts.inter(
      textStyle: theme.textTheme.bodyLarge?.copyWith(
        height: 1.55,
        color: cardSub,
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          scale: _hovered ? 1.01 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cardBorder,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  OpenedPostsStore.markOpened(post.id);
                  context.push(
                    '/post/${post.id}',
                    extra: <String, String>{
                      'authorId': post.authorId,
                      'authorName': post.authorName,
                    },
                  );
                },
                hoverColor: cardAccent.withValues(alpha: 0.06),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (post.isArchived) ...<Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.archive_outlined,
                              size: 12,
                              color: cardSub.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Archived',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cardSub.withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (post.moderationStatus != 'approved') ...<Widget>[
                        InkWell(
                          onTap: post.moderationStatus == 'rejected'
                              ? () => context.push('/community-guidelines')
                              : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                post.moderationStatus == 'pending'
                                    ? Icons.hourglass_empty
                                    : Icons.error_outline,
                                size: 12,
                                color: post.moderationStatus == 'pending'
                                    ? Colors.amber[800]
                                    : (post.canEditAfterRejection
                                        ? Colors.orange[800]
                                        : Colors.red[800]),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                post.moderationStatus == 'pending'
                                    ? 'Pending Moderation'
                                    : (post.canEditAfterRejection
                                        ? 'Rejected'
                                        : 'Rejection with Deletion'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: post.moderationStatus == 'pending'
                                      ? Colors.amber[800]
                                      : (post.canEditAfterRejection
                                          ? Colors.orange[900]
                                          : Colors.red[900]),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              if (post.moderationStatus == 'rejected') ...<Widget>[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: post.canEditAfterRejection
                                      ? Colors.orange[900]
                                      : Colors.red[900],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (post.moderationStatus == 'rejected' &&
                            post.moderationNote != null &&
                            post.moderationNote!.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reason: ${post.moderationNote}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.orange[900],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                if (post.rejectedAt != null) ...[
                                  const SizedBox(height: 6),
                                  _RejectionCountdown(
                                    rejectedAt: post.rejectedAt!,
                                    canEdit: post.canEditAfterRejection,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => context
                                      .push('/community-guidelines'),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.menu_book_outlined,
                                        size: 13,
                                        color: Colors.orange[900],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Review Community Guidelines',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.orange[900],
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                      ],
                      Text(post.title, style: titleStyle),
                      const SizedBox(height: 10),
                      Text(
                        post.bodyPreview,
                        style: bodyStyle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 14),
                      _TagsRow(
                        tags: post.tags,
                        bg: cardMid,
                        textColor: cardAccent,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Row(
                              children: <Widget>[
                                if (isSelfPost) ...[
                                  // Show likes count for user's own posts
                                  Icon(
                                    Icons.favorite,
                                    size: 16,
                                    color: cardAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${post.likesCount} ${post.likesCount == 1 ? 'like' : 'likes'}',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: cardSub,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '• ${post.readTimeMinutes} min read',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: cardSub,
                                    ),
                                  ),
                                ] else ...[
                                  CircleAvatar(
                                    radius: 11,
                                    backgroundColor:
                                        cardAccent.withValues(alpha: 0.16),
                                    child: Icon(
                                      Icons.person_outline,
                                      size: 14,
                                      color: cardAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: _AuthorLink(
                                      authorId: post.authorId,
                                      name: post.authorName,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        color: cardSub,
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      ' • ${post.readTimeMinutes} min read',
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        color: cardSub,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!isSelfPost) ...[
                            IconButton(
                              onPressed: widget.onLike,
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) {
                                  return ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  );
                                },
                                child: Icon(
                                  widget.isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  key: ValueKey<bool>(widget.isLiked),
                                ),
                              ),
                              color: widget.isLiked
                                  ? colorScheme.primary
                                  : cardSub.withValues(alpha: 0.85),
                              tooltip: 'Like',
                            ),
                            IconButton(
                              onPressed: widget.onBookmark,
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) {
                                  return ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  );
                                },
                                child: Icon(
                                  widget.isBookmarked
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  key: ValueKey<bool>(widget.isBookmarked),
                                ),
                              ),
                              color: widget.isBookmarked
                                  ? colorScheme.primary
                                  : cardSub.withValues(alpha: 0.85),
                              tooltip: 'Bookmark',
                            ),
                          ],
                          if (widget.onArchive != null ||
                              widget.onUnarchive != null ||
                              widget.onBin != null ||
                              widget.onEdit != null)
                            Builder(builder: (context) {
                              final isRejected = post.moderationStatus == 'rejected';
                              bool canDelete = true;
                              if (isRejected) {
                                final rejectedAt = post.rejectedAt;
                                if (rejectedAt != null) {
                                  final diff = DateTime.now().difference(rejectedAt);
                                  if (diff.inDays > 7) {
                                    canDelete = false;
                                  }
                                }
                              }

                              final showArchive = widget.onArchive != null && !isRejected;
                              final showUnarchive = widget.onUnarchive != null && !isRejected;
                              final showBin = widget.onBin != null && canDelete;
                              // Hide edit for non-editable rejections (rejection with deletion)
                              final showEdit = widget.onEdit != null && 
                                  !(isRejected && !post.canEditAfterRejection);

                              if (!showArchive && !showUnarchive && !showBin && !showEdit) {
                                return const SizedBox.shrink();
                              }

                              return PopupMenuButton<_PostMenuAction>(
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 20,
                                  color: cardSub.withValues(alpha: 0.75),
                                ),
                                tooltip: 'More options',
                                onSelected: (action) {
                                  if (action == _PostMenuAction.archive) {
                                    widget.onArchive?.call();
                                  } else if (action ==
                                      _PostMenuAction.unarchive) {
                                    widget.onUnarchive?.call();
                                  } else if (action == _PostMenuAction.edit) {
                                    widget.onEdit?.call();
                                  } else if (action == _PostMenuAction.bin) {
                                    widget.onBin?.call();
                                  }
                                },
                                itemBuilder: (context) =>
                                    <PopupMenuEntry<_PostMenuAction>>[
                                  if (showArchive)
                                    const PopupMenuItem<_PostMenuAction>(
                                      value: _PostMenuAction.archive,
                                      child: Row(
                                        children: <Widget>[
                                          Icon(Icons.archive_outlined, size: 18),
                                          SizedBox(width: 10),
                                          Text('Archive'),
                                        ],
                                      ),
                                    ),
                                  if (showUnarchive)
                                    const PopupMenuItem<_PostMenuAction>(
                                      value: _PostMenuAction.unarchive,
                                      child: Row(
                                        children: <Widget>[
                                          Icon(Icons.unarchive_outlined,
                                              size: 18),
                                          SizedBox(width: 10),
                                          Text('Unarchive'),
                                        ],
                                      ),
                                    ),
                                  if (showEdit)
                                    const PopupMenuItem<_PostMenuAction>(
                                      value: _PostMenuAction.edit,
                                      child: Row(
                                        children: <Widget>[
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 10),
                                          Text('Edit'),
                                        ],
                                      ),
                                    ),
                                  if (showBin)
                                    PopupMenuItem<_PostMenuAction>(
                                      value: _PostMenuAction.bin,
                                      child: Row(
                                        children: <Widget>[
                                          Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: isCardDark 
                                                ? Colors.red[400] 
                                                : colorScheme.error,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Move to Bin',
                                            style: TextStyle(
                                              color: isCardDark 
                                                  ? Colors.red[400] 
                                                  : colorScheme.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthorLink extends StatefulWidget {
  const _AuthorLink({
    required this.authorId,
    required this.name,
    required this.style,
  });

  final String authorId;
  final String name;
  final TextStyle? style;

  @override
  State<_AuthorLink> createState() => _AuthorLinkState();
}

class _AuthorLinkState extends State<_AuthorLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.authorId.trim().isNotEmpty;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (!enabled) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!enabled) return;
        setState(() => _hovered = false);
      },
      child: InkWell(
        onTap:
            enabled ? () => context.push('/profile/${widget.authorId}') : null,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _hovered ? 0.78 : 1.0,
          child: Text(
            widget.name,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  const _TagsRow({
    required this.tags,
    required this.bg,
    required this.textColor,
  });

  final List<String> tags;
  final Color bg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .take(4)
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                tag,
                style: GoogleFonts.inter(
                  textStyle: theme.textTheme.labelMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _RejectionCountdown extends StatefulWidget {
  const _RejectionCountdown({
    required this.rejectedAt,
    required this.canEdit,
  });

  final DateTime rejectedAt;
  final bool canEdit;

  @override
  State<_RejectionCountdown> createState() => _RejectionCountdownState();
}

class _RejectionCountdownState extends State<_RejectionCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Update countdown every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Calculate deletion time based on whether user can edit
    // 7 days for editable, 30 minutes for non-editable
    final deletionTime = widget.canEdit 
        ? widget.rejectedAt.add(const Duration(days: 7))
        : widget.rejectedAt.add(const Duration(minutes: 30));
    final now = DateTime.now();
    final remaining = deletionTime.difference(now);

    // If already expired
    if (remaining.isNegative) {
      return Row(
        children: [
          Icon(Icons.warning_amber, size: 14, color: Colors.red[800]),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'This post will be deleted soon',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.red[900],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    // Format the countdown
    String countdownText;
    if (remaining.inDays > 0) {
      final hours = remaining.inHours % 24;
      countdownText = '${remaining.inDays}d ${hours}h until deletion';
    } else if (remaining.inHours > 0) {
      final minutes = remaining.inMinutes % 60;
      countdownText = '${remaining.inHours}h ${minutes}m until deletion';
    } else {
      countdownText = '${remaining.inMinutes}m until deletion';
    }

    final color = widget.canEdit ? Colors.orange[900] : Colors.red[900];
    final bgColor = widget.canEdit 
        ? Colors.orange.withValues(alpha: 0.12)
        : Colors.red.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.canEdit ? Icons.edit_outlined : Icons.timer_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              countdownText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          if (widget.canEdit) ...[
            const SizedBox(width: 4),
            Text(
              '(editable)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color?.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

