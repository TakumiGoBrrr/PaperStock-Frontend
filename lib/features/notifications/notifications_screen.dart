import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../feed/feed_screen.dart' show bottomNavIndexProvider;
import 'controller/notifications_controller.dart';
import 'models/app_notification.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark all notifications as read when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final asyncState = ref.watch(notificationsControllerProvider);

    return asyncState.when(
      loading: () => const _CenteredLoading(),
      error: (error, stackTrace) {
        return _CenteredError(
          message: error.toString(),
          onRetry: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
        );
      },
      data: (state) {
        if (state.items.isEmpty) {
          return const _CenteredEmpty(
            title: 'No notifications',
            subtitle: 'You\'re all caught up.',
          );
        }

        void maybeFetchMore(ScrollMetrics metrics) {
          if (!state.hasMore || state.isLoadingMore) return;
          if (metrics.maxScrollExtent <= 0) return;

          const threshold = 320.0;
          if (metrics.extentAfter > threshold) return;

          ref.read(notificationsControllerProvider.notifier).fetchNext();
        }

        return RefreshIndicator(
          onRefresh: () => ref
              .read(notificationsControllerProvider.notifier)
              .refreshFirstPage(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) {
                maybeFetchMore(notification.metrics);
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (state.isLoadingMore && index == state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 24),
                    child: Center(
                      child: SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  );
                }

                final n = state.items[index];
                final actorName = n.actorDisplayName.isNotEmpty
                    ? n.actorDisplayName
                    : 'Unknown';

                final title = _titleFor(n, actorName);
                final subtitle = _subtitleFor(n);
                final timeAgo = _timeAgo(n.createdAt);

                final isUnread = !n.isRead;

                Future<void> onTap() async {
                  try {
                    await ref
                        .read(notificationsControllerProvider.notifier)
                        .markRead(notificationId: n.id);
                  } catch (_) {
                    // Keep UX minimal: no snackbar needed for mark-as-read.
                  }

                  if (!context.mounted) return;

                  if (n.type == 'follow') {
                    if (n.actorId.isNotEmpty) {
                      context.push('/profile/${n.actorId}');
                    }
                    return;
                  }

                  if (n.type == 'qotd_challenge' || n.type == 'qotd_new') {
                    // Open the "Daily" tab (index 1) inside the feed shell.
                    ref.read(bottomNavIndexProvider.notifier).state = 1;
                    context.go('/feed');
                    return;
                  }

                  if (n.type == 'moderation_rejected' &&
                      n.postId != null &&
                      n.postId!.isNotEmpty) {
                    context.push('/post/${n.postId}');
                    return;
                  }

                  if (n.type == 'moderation_deleted') {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Post Deleted'),
                        content: Text(
                          'Your post "${n.postTitle ?? 'Untitled'}" was deleted by a moderator.\n\nReason: ${n.postModerationNote ?? 'No reason provided.'}',
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              context.push('/community-guidelines');
                            },
                            child: const Text('Review Guidelines'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  if ((n.type == 'like' || n.type == 'comment' || n.type == 'sequel') &&
                      n.postId != null &&
                      n.postId!.isNotEmpty) {
                    context.push('/post/${n.postId}');
                  }
                }

                return _NotificationTile(
                  title: title,
                  subtitle: subtitle,
                  timeAgo: timeAgo,
                  isUnread: isUnread,
                  leadingIcon: _iconFor(n.type),
                  highlightColor: colorScheme.surfaceContainerHighest,
                  onTap: onTap,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.title,
    required this.subtitle,
    required this.timeAgo,
    required this.isUnread,
    required this.leadingIcon,
    required this.highlightColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String timeAgo;
  final bool isUnread;
  final IconData leadingIcon;
  final Color highlightColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bg = isUnread
        ? highlightColor.withAlpha((0.55 * 255).round())
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    child: Icon(leadingIcon, size: 18),
                  ),
                  if (isUnread)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        height: 10,
                        width: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight:
                                  isUnread ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          timeAgo,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(String type) {
  switch (type) {
    case 'follow':
      return Icons.person_add_alt_1_outlined;
    case 'like':
      return Icons.favorite_border;
    case 'comment':
      return Icons.mode_comment_outlined;
    case 'sequel':
      return Icons.auto_stories_outlined;
    case 'moderation_rejected':
      return Icons.gavel_outlined;
    case 'moderation_deleted':
      return Icons.delete_forever_outlined;
    case 'qotd_challenge':
      return Icons.emoji_events_outlined;
    case 'qotd_new':
      return Icons.wb_sunny_outlined;
    default:
      return Icons.notifications_outlined;
  }
}

String _titleFor(AppNotification n, String actorName) {
  switch (n.type) {
    case 'follow':
      return '$actorName followed you';
    case 'like':
      return '$actorName liked your post';
    case 'comment':
      return '$actorName commented on your post';
    case 'sequel':
      return '$actorName published a sequel!';
    case 'moderation_rejected':
      return 'Post Rejected by Moderator';
    case 'moderation_deleted':
      return 'Post Deleted by Moderator';
    case 'qotd_challenge':
      return '$actorName answered today\'s question';
    case 'qotd_new':
      return 'Today\'s question is live';
    default:
      return 'New notification';
  }
}

String _subtitleFor(AppNotification n) {
  // Backend does not currently return comment text or post title.
  if ((n.type == 'moderation_rejected' || n.type == 'moderation_deleted') &&
      (n.postModerationNote ?? '').isNotEmpty) {
    return 'Reason: ${n.postModerationNote}';
  }
  if (n.type == 'moderation_rejected') {
    return 'Tap to view the post.';
  }
  if (n.type == 'moderation_deleted') {
    return 'Tap to view details.';
  }
  if (n.type == 'sequel' && (n.postId ?? '').isNotEmpty) {
    return 'Tap to read the next part.';
  }
  if (n.type == 'comment' && (n.postId ?? '').isNotEmpty) {
    return 'Tap to view the post.';
  }
  if (n.type == 'like' && (n.postId ?? '').isNotEmpty) {
    return 'Tap to view the post.';
  }
  if (n.type == 'qotd_challenge' || n.type == 'qotd_new') {
    if ((n.questionPrompt ?? '').isNotEmpty) {
      return '"${n.questionPrompt}" — tap to answer.';
    }
    return 'Tap to answer today\'s question.';
  }
  if (n.type == 'follow') {
    return 'Tap to view profile.';
  }
  return '';
}

String _timeAgo(DateTime createdAt) {
  final now = DateTime.now();
  final diff = now.difference(createdAt);

  if (diff.inSeconds < 0) return 'now';
  if (diff.inSeconds < 45) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';

  final weeks = (diff.inDays / 7).floor();
  if (weeks < 4) return '${weeks}w';

  final months = (diff.inDays / 30).floor();
  if (months < 12) return '${months}mo';

  final years = (diff.inDays / 365).floor();
  return '${years}y';
}

class _CenteredLoading extends StatelessWidget {
  const _CenteredLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        height: 28,
        width: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}

class _CenteredEmpty extends StatelessWidget {
  const _CenteredEmpty({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredError extends StatelessWidget {
  const _CenteredError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
