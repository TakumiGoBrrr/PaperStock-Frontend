import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/storage/opened_posts_store.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/widgets/notification_bell_button.dart';
import '../feed/controller/feed_controller.dart';
import '../feed/models/feed_post.dart';
import '../feed/models/post.dart';
import '../feed/repository/post_detail_repository.dart';
import '../feed/widgets/post_card.dart';

enum _HistoryRemoveAction {
  hidePermanently,
  removeFromHistoryOnly,
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final Map<String, Future<Post?>> _futureById = <String, Future<Post?>>{};

  // Mutable interaction state - initialised once the post future resolves.
  final Map<String, bool> _isLikedById = <String, bool>{};
  final Map<String, bool> _isBookmarkedById = <String, bool>{};
  final Set<String> _likeInFlight = <String>{};
  final Set<String> _bookmarkInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(OpenedPostsStore.ensureLoaded());
  }

  // ── Like / Bookmark helpers ───────────────────────────────────────────────────

  Future<void> _toggleLike(String postId) async {
    if (_likeInFlight.contains(postId)) return;
    _likeInFlight.add(postId);

    final prev = _isLikedById[postId] ?? false;
    setState(() => _isLikedById[postId] = !prev);

    try {
      final repo = ref.read(feedRepositoryProvider);
      final updated = await repo.toggleLike(postId: postId);
      if (!mounted) return;
      setState(() => _isLikedById[postId] = updated.isLiked);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLikedById[postId] = prev);
    } finally {
      _likeInFlight.remove(postId);
    }
  }

  Future<void> _toggleBookmark(String postId) async {
    if (_bookmarkInFlight.contains(postId)) return;
    _bookmarkInFlight.add(postId);

    final prev = _isBookmarkedById[postId] ?? false;
    final adding = !prev;
    setState(() => _isBookmarkedById[postId] = adding);

    try {
      final repo = ref.read(feedRepositoryProvider);
      if (adding) {
        final updated = await repo.addBookmark(postId: postId);
        if (!mounted) return;
        setState(() => _isBookmarkedById[postId] = updated.isBookmarked);
      } else {
        await repo.removeBookmark(postId: postId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBookmarkedById[postId] = prev);
    } finally {
      _bookmarkInFlight.remove(postId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final repo = PostDetailRepository(dio: ref.watch(apiClientProvider).dio);

    Widget emptyView() {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        children: const <Widget>[
          SizedBox(height: 40),
          Center(child: Text('No history yet.')),
        ],
      );
    }

    Widget loadingCard() {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: GlassAppBar(
        title: Text(
          'PaperStock',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        left: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        right: const NotificationBellButton(),
      ),
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder(
          valueListenable: OpenedPostsStore.openedIds,
          builder: (context, openedIds, _) {
            final ids = openedIds.toList(growable: false).reversed.toList();

            if (ids.isEmpty) return emptyView();

            Future<void> promptRemove(String id) async {
              final action = await showModalBottomSheet<_HistoryRemoveAction>(
                context: context,
                showDragHandle: true,
                builder: (context) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          title: const Text('Hide permanently'),
                          subtitle: const Text('Won\'t show in feed again.'),
                          onTap: () => Navigator.of(context)
                              .pop(_HistoryRemoveAction.hidePermanently),
                        ),
                        ListTile(
                          title: const Text('Remove from history'),
                          subtitle: const Text('May reappear in feed.'),
                          onTap: () => Navigator.of(context)
                              .pop(_HistoryRemoveAction.removeFromHistoryOnly),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              );

              if (action == null) return;

              if (action == _HistoryRemoveAction.hidePermanently) {
                await OpenedPostsStore.hidePermanently(id);
              } else {
                await OpenedPostsStore.removeFromHistoryOnly(id);
              }

              if (!mounted) return;
              setState(() {
                _futureById.remove(id);
              });
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: ids.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final id = ids[index];
                final future = _futureById.putIfAbsent(id, () {
                  final f = repo.getPostDetail(postId: id);
                  f.then((post) {
                    if (post != null && mounted) {
                      setState(() {
                        _isLikedById.putIfAbsent(post.id, () => post.isLiked);
                        _isBookmarkedById.putIfAbsent(
                            post.id, () => post.isBookmarked);
                      });
                    }
                  }).catchError((_) {});
                  return f;
                });

                return FutureBuilder<Post?>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return loadingCard();
                    }

                    if (snapshot.hasError) {
                      final err = snapshot.error;
                      if (err is PostUnavailableException &&
                          err.authorId.isNotEmpty) {
                        return Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      'Post removed by author',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    GestureDetector(
                                      onTap: () => context
                                          .push('/profile/${err.authorId}'),
                                      child: Text(
                                        err.authorName.isNotEmpty
                                            ? err.authorName
                                            : 'View author profile',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.primary,
                                          decoration:
                                              TextDecoration.underline,
                                          decorationColor:
                                              colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => promptRemove(id),
                                icon: const Icon(Icons.close),
                                tooltip: 'Remove',
                              ),
                            ],
                          ),
                        );
                      }
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Failed to load post',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() => _futureById.remove(id));
                              },
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Retry',
                            ),
                            IconButton(
                              onPressed: () => promptRemove(id),
                              icon: const Icon(Icons.close),
                              tooltip: 'Remove',
                            ),
                          ],
                        ),
                      );
                    }

                    final post = snapshot.data;
                    if (post == null) {
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Post unavailable',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              onPressed: () => promptRemove(id),
                              icon: const Icon(Icons.close),
                              tooltip: 'Remove',
                            ),
                          ],
                        ),
                      );
                    }

                    return Stack(
                      children: <Widget>[
                        PostCard(
                          key: ValueKey<String>(post.id),
                          post: _toFeedPost(post),
                          isLiked: _isLikedById[post.id] ?? post.isLiked,
                          isBookmarked:
                              _isBookmarkedById[post.id] ?? post.isBookmarked,
                          onLike: () => _toggleLike(post.id),
                          onBookmark: () => _toggleBookmark(post.id),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: colorScheme.surface
                                .withAlpha((0.78 * 255).round()),
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => promptRemove(post.id),
                              child: const SizedBox(
                                height: 40,
                                width: 40,
                                child: Icon(Icons.close),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

FeedPost _toFeedPost(Post post) {
  final authorName =
      post.authorName.isNotEmpty ? post.authorName : 'Unknown';

  return FeedPost(
    id: post.id,
    title: post.title,
    bodyPreview: post.body,
    tags: post.tags,
    authorId: post.authorId,
    authorName: authorName,
    readTimeMinutes: post.readTimeMinutes,
    likesCount: post.likesCount,
    isNsfw: post.isNsfw,
    moderationStatus: post.moderationStatus,
    moderationNote: post.moderationNote,
    rejectedAt: post.rejectedAt,
    canEditAfterRejection: post.canEditAfterRejection,
  );
}
