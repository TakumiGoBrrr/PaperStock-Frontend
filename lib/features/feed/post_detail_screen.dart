import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/card_brightness_provider.dart';
import '../../core/api/api_client_provider.dart';
import '../../core/api/api_config.dart';
import '../../core/widgets/nsfw_blur_overlay.dart';
import '../swipe/swipe_controller.dart';
import 'controller/post_detail_controller.dart';
import 'models/comment.dart';
import 'models/post.dart';
import '../profile/controller/profile_controller.dart';
import '../../core/storage/last_reading_store.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    this.fallbackAuthorId = '',
    this.fallbackAuthorName = '',
  });

  final String postId;

  /// Author info passed from the post card, used to build the profile link
  /// when the post can no longer be fetched (deleted / archived).
  final String fallbackAuthorId;
  final String fallbackAuthorName;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  bool _showControls = true;
  Timer? _hideTimer;

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _commentFocus.addListener(_onCommentFocusChange);
  }

  void _onCommentFocusChange() {
    if (_commentFocus.hasFocus) {
      _hideTimer?.cancel();
      setState(() => _showControls = true);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _commentFocus.removeListener(_onCommentFocusChange);
    _commentFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(postDetailControllerProvider(widget.postId));

    ref.listen(postDetailControllerProvider(widget.postId), (prev, next) {
      final prevNonce = prev?.valueOrNull?.uiMessageNonce ?? 0;
      final nextState = next.valueOrNull;
      final nextNonce = nextState?.uiMessageNonce ?? 0;

      if (nextState == null) return;
      if (nextNonce == prevNonce) return;
      final message = nextState.uiMessage;
      if (message == null || message.trim().isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(postDetailControllerProvider(widget.postId).notifier)
            .consumeUiMessage();
      });
    });

    final isSubmitting = ref.watch(
      postDetailControllerProvider(widget.postId)
          .select((value) => value.valueOrNull?.isSubmittingComment ?? false),
    );

    final rateLimitUntil = ref.watch(
      postDetailControllerProvider(widget.postId)
          .select((value) => value.valueOrNull?.commentRateLimitUntil),
    );

    final isRateLimited = rateLimitUntil != null &&
        DateTime.now().isBefore(rateLimitUntil) &&
        (ref.watch(
          postDetailControllerProvider(widget.postId)
              .select((v) => v.valueOrNull?.isCommentRateLimited ?? false),
        ));

    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;
    final readBg = isDark ? cardCharcoalDark : cardCreamLight;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });

        if (_showControls) {
          _startHideTimer();
        } else {
          _hideTimer?.cancel();
        }
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: cardBrightness,
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: isDark ? cardCharcoalText : cardCreamText,
            displayColor: isDark ? cardCharcoalText : cardCreamText,
          ),
          colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: cardBrightness,
            surfaceContainerHighest: isDark ? cardCharcoalMid : cardCreamMid,
            surfaceContainerHigh: isDark ? cardCharcoalDark : cardCreamLight,
            onSurfaceVariant: isDark ? cardCharcoalSubtext : cardCreamSubtext,
          ),
        ),
        child: Scaffold(
          backgroundColor: readBg,
          resizeToAvoidBottomInset: true,
          body: Column(
            children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  SafeArea(
                    bottom: false,
                    child: asyncState.when(
                      loading: () => const _PostDetailSkeleton(),
                      error: (error, stackTrace) {
                        final is404 = error is DioException &&
                            error.response?.statusCode == 404;
                        if (is404) {
                          return _PostUnavailableView(
                            authorId: widget.fallbackAuthorId,
                            authorName: widget.fallbackAuthorName,
                          );
                        }
                        return _CenteredError(
                          message: error.toString(),
                          onRetry: () => ref
                              .read(postDetailControllerProvider(widget.postId)
                                  .notifier)
                              .refresh(),
                        );
                      },
                      data: (state) {
                        final post = state.post;
                        if (post == null) {
                          return const _CenteredEmpty(
                            title: 'Post not found',
                            subtitle:
                                'It may have been deleted or is unavailable.',
                          );
                        }

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          LastReadingStore.save(
                            id: post.id,
                            title: post.title,
                            authorName: post.authorName,
                            authorId: post.authorId,
                            parentId: post.parentId,
                            nextPostId: post.nextPostId,
                          );
                        });

                        return _PostDetailBody(
                          post: post,
                          comments: state.comments,
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      bottom: false,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        opacity: _showControls ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, top: 8),
                            child: Material(
                              color:
                                  Colors.black.withAlpha((0.45 * 255).round()),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => context.pop(),
                                child: const SizedBox(
                                  height: 44,
                                  width: 44,
                                  child: Icon(Icons.arrow_back,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                ],
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                heightFactor: _showControls ? 1.0 : 0.0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  opacity: _showControls ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: SafeArea(
                      top: false,
                      child: _CommentInputBar(
                        controller: _commentController,
                        focusNode: _commentFocus,
                        isRateLimited: isRateLimited,
                        helperText: isRateLimited
                            ? 'You can comment once per hour on this post'
                            : null,
                        onSubmit: () async {
                          final text = _commentController.text;
                          if (text.trim().isEmpty) return;

                          FocusScope.of(context).unfocus();

                          final ok = await ref
                              .read(postDetailControllerProvider(widget.postId)
                                  .notifier)
                              .addComment(text);
                          if (ok) {
                            _commentController.clear();
                          }
                        },
                        isSubmitting: isSubmitting,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _PostDetailBody extends ConsumerWidget {
  const _PostDetailBody({
    required this.post,
    required this.comments,
  });

  final Post post;
  final List<Comment> comments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isDesktop = maxWidth > 1024;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isDesktop ? 700 : double.infinity),
            child: _ScrollContent(
              post: post,
              comments: comments,
            ),
          ),
        );
      },
    );
  }
}

class _ScrollContent extends ConsumerWidget {
  const _ScrollContent({
    required this.post,
    required this.comments,
  });

  final Post post;
  final List<Comment> comments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;

    // ── Warm-charcoal reading palette ────────────────────────────────
    final readText = isDark ? cardCharcoalText : cardCreamText;
    final readSub = isDark ? cardCharcoalSubtext : cardCreamSubtext;
    final readAccent = isDark ? cardCharcoalAccent : cardCreamAccent;
    final readBorder = isDark ? cardCharcoalEdge : cardCreamEdge;

    final commentsError = ref.watch(
      postDetailControllerProvider(post.id)
          .select((v) => v.valueOrNull?.commentsError),
    );
    final isLoadingComments = ref.watch(
      postDetailControllerProvider(post.id)
          .select((v) => v.valueOrNull?.isLoadingComments ?? false),
    );
    final hasMore = ref.watch(
      postDetailControllerProvider(post.id)
          .select((v) => v.valueOrNull?.commentsHasMore ?? false),
    );
    final isLoadingMore = ref.watch(
      postDetailControllerProvider(post.id)
          .select((v) => v.valueOrNull?.isLoadingMoreComments ?? false),
    );
    final loadMoreError = ref.watch(
      postDetailControllerProvider(post.id)
          .select((v) => v.valueOrNull?.loadMoreCommentsError),
    );
    final currentUserId = ref.watch(
      postDetailControllerProvider(post.id)
          .select((v) => v.valueOrNull?.currentUserId),
    );

    final authorName = post.authorName.isNotEmpty ? post.authorName : 'Unknown';
    final canOpenAuthor = post.authorId.trim().isNotEmpty;

    final titleStyle = GoogleFonts.lora(
      textStyle: theme.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.12,
        color: readText,
      ),
    );

    final metaStyle = GoogleFonts.inter(
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: readSub,
        height: 1.3,
      ),
    );

    return _ExitOnEdgeOverscroll(
      onExitTop: () {
        if (!context.mounted) return;
        if (Navigator.of(context).canPop()) {
          context.pop();
        }
      },
      onExitBottom: () {
        if (!context.mounted) return;
        if (Navigator.of(context).canPop()) {
          context.pop();
        }
      },
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 6),
                  Text(post.title, style: titleStyle),
                  if ((post.firstPostId != null &&
                      post.firstPostId!.isNotEmpty &&
                      post.firstPostId != post.id) ||
                      (post.parentId != null &&
                      post.parentId!.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: readAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: readAccent.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_stories_outlined,
                              color: readAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Part of a series',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: readText,
                              ),
                            ),
                          ),
                          if (post.parentId != null &&
                              post.parentId!.isNotEmpty) ...[
                            TextButton(
                              onPressed: () {
                                context.push(
                                  '/post/${post.parentId}',
                                  extra: <String, String>{
                                    'authorId': post.authorId,
                                    'authorName': post.authorName,
                                  },
                                );
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                'Previous Part',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: readAccent,
                                ),
                              ),
                            ),
                          ],
                          if (post.firstPostId != null &&
                              post.firstPostId!.isNotEmpty &&
                              post.firstPostId != post.parentId &&
                              post.firstPostId != post.id) ...[
                            TextButton(
                              onPressed: () {
                                context.push(
                                  '/post/${post.firstPostId}',
                                  extra: <String, String>{
                                    'authorId': post.authorId,
                                    'authorName': post.authorName,
                                  },
                                );
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                'Start from Part 1',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: readAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      InkWell(
                        onTap: canOpenAuthor
                            ? () => context.push('/profile/${post.authorId}')
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Text(authorName, style: metaStyle),
                        ),
                      ),
                      Text(
                        ' • ${post.readTimeMinutes} min read',
                        style: metaStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TagsPills(tags: post.tags),
                  const SizedBox(height: 22),
                  _ActionsRow(postId: post.id),
                  const SizedBox(height: 26),
                  NsfwBlurOverlay(
                    isNsfw: post.isNsfw,
                    child: SelectionContainer.disabled(
                      child: MarkdownBody(
                        data: post.body,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: GoogleFonts.inter(
                            textStyle: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                              color: readSub,
                            ),
                          ),
                          h1: GoogleFonts.lora(
                            textStyle: theme.textTheme.headlineMedium?.copyWith(
                              color: readText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          h2: GoogleFonts.lora(
                            textStyle: theme.textTheme.headlineSmall?.copyWith(
                              color: readText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: readAccent.withValues(alpha: 0.55),
                                width: 3,
                              ),
                            ),
                          ),
                          blockquote: GoogleFonts.inter(
                            textStyle: theme.textTheme.bodyLarge?.copyWith(
                              color: readSub.withValues(alpha: 0.8),
                              fontStyle: FontStyle.italic,
                              height: 1.6,
                            ),
                          ),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: readBorder,
                                width: 0.8,
                              ),
                            ),
                          ),
                          blockSpacing: 18,
                        ),
                      ),
                    ),
                  ),
                  if (post.nextPostId != null && post.nextPostId!.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: readAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: readAccent.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_forward_rounded,
                              color: readAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Continues in next part',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: readText,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              context.push(
                                '/post/${post.nextPostId}',
                                extra: <String, String>{
                                  'authorId': post.authorId,
                                  'authorName': post.authorName,
                                },
                              );
                            },
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: Text(
                              'Read Next Part',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: readAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                  Text(
                    'Comments',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: commentsError != null
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 40),
                      child: Column(
                        children: <Widget>[
                          Text(
                            'Failed to load comments',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            commentsError,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () => ref
                                .read(postDetailControllerProvider(post.id)
                                    .notifier)
                                .reloadComments(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : isLoadingComments && comments.isEmpty
                    ? const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(8, 18, 8, 40),
                          child: Center(
                            child: SizedBox(
                              height: 28,
                              width: 28,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4),
                            ),
                          ),
                        ),
                      )
                    : comments.isEmpty
                        ? const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(8, 10, 8, 40),
                              child: Text(
                                'No comments yet. Be the first to comment.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : SliverList.separated(
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              final canDelete = currentUserId != null &&
                                  currentUserId.isNotEmpty &&
                                  comment.authorId == currentUserId;

                              Future<void> onDelete() async {
                                try {
                                  await ref
                                      .read(
                                          postDetailControllerProvider(post.id)
                                              .notifier)
                                      .deleteComment(commentId: comment.id);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Failed to delete comment. Please try again.'),
                                    ),
                                  );
                                }
                              }

                              final canReport = currentUserId != null &&
                                  currentUserId.isNotEmpty &&
                                  comment.authorId != currentUserId;

                              return _CommentTile(
                                comment: comment,
                                canDelete: canDelete,
                                onDelete: canDelete ? onDelete : null,
                                canReport: canReport,
                                postId: post.id,
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                          ),
          ),
          if (commentsError == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  children: <Widget>[
                    if (loadMoreError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          loadMoreError,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (hasMore)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isLoadingMore
                              ? null
                              : () => ref
                                  .read(postDetailControllerProvider(post.id)
                                      .notifier)
                                  .loadMoreComments(),
                          child: isLoadingMore
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Load more'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}


class _ExitOnEdgeOverscroll extends StatefulWidget {
  const _ExitOnEdgeOverscroll({
    required this.child,
    required this.onExitTop,
    required this.onExitBottom,
  });

  final Widget child;
  final VoidCallback onExitTop;
  final VoidCallback onExitBottom;

  @override
  State<_ExitOnEdgeOverscroll> createState() => _ExitOnEdgeOverscrollState();
}

class _ExitOnEdgeOverscrollState extends State<_ExitOnEdgeOverscroll> {
  static const double _kExitOverscrollThreshold = 34;

  double _topOverscroll = 0;
  double _bottomOverscroll = 0;
  bool _hasExited = false;

  void _exitTopOnce() {
    if (_hasExited) return;
    _hasExited = true;
    widget.onExitTop();
  }

  void _exitBottomOnce() {
    if (_hasExited) return;
    _hasExited = true;
    widget.onExitBottom();
  }

  void _reset() {
    _topOverscroll = 0;
    _bottomOverscroll = 0;
  }

  bool _onNotification(ScrollNotification n) {
    if (_hasExited) return false;

    if (n is ScrollStartNotification || n is ScrollEndNotification) {
      _reset();
      return false;
    }

    if (n is ScrollUpdateNotification && !n.metrics.atEdge) {
      _reset();
      return false;
    }

    if (n is OverscrollNotification) {
      final m = n.metrics;
      final atTop = m.pixels <= m.minScrollExtent;
      final atBottom = m.pixels >= m.maxScrollExtent;

      if (atTop && n.overscroll < 0) {
        _topOverscroll += n.overscroll.abs();
        _bottomOverscroll = 0;
      } else if (atBottom && n.overscroll > 0) {
        _bottomOverscroll += n.overscroll;
        _topOverscroll = 0;
      } else {
        _reset();
      }

      if (_topOverscroll >= _kExitOverscrollThreshold) {
        _exitTopOnce();
      } else if (_bottomOverscroll >= _kExitOverscrollThreshold) {
        _exitBottomOnce();
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.child,
    );
  }
}

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final post = ref.watch(
      postDetailControllerProvider(postId)
          .select((value) => value.valueOrNull?.post),
    );

    final isBookmarked = post?.isBookmarked ?? false;

    final meId = ref.watch(currentUserIdProvider).valueOrNull;
    final isSelfPost = meId != null && post != null && meId == post.authorId;

    Future<void> onBookmark() async {
      try {
        await ref
            .read(postDetailControllerProvider(postId).notifier)
            .toggleBookmark();
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update bookmark. Please try again.'),
          ),
        );
      }
    }

    Future<void> onShare() async {
      final title = (post?.title ?? '').trim();
      final link = '${ApiConfig.baseUrl}/post/$postId';
      final text = title.isEmpty
          ? 'Read this story on PaperStock 👉 $link'
          : 'Read "$title" on PaperStock 👉 $link';
      await Share.share(text, subject: title.isEmpty ? 'PaperStock' : title);
    }

    return Row(
      children: <Widget>[
        if (!isSelfPost) ...[
          _ActionChipButton(
            onPressed: onBookmark,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                key: ValueKey<bool>(isBookmarked),
                color: isBookmarked ? colorScheme.primary : null,
                size: 20,
              ),
            ),
            label: 'Save',
          ),
          const SizedBox(width: 10),
        ],
        _ActionChipButton(
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined, size: 20),
          label: 'Share',
        ),
        if (!isSelfPost && post != null) ...[
          const SizedBox(width: 10),
          _ActionChipButton(
            onPressed: () => _showReportDialog(context, ref, post),
            icon: const Icon(Icons.flag_outlined, size: 20),
            label: 'Report',
          ),
        ],
      ],
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: theme.textTheme.labelLarge,
      ),
    );
  }
}

class _TagsPills extends ConsumerWidget {
  const _TagsPills({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;

    final bg = isDark ? cardCharcoalMid : cardCreamMid;
    final text = isDark ? cardCharcoalAccent : cardCreamAccent;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .take(8)
          .map(
            (tag) => Chip(
              label: Text(tag),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              side: BorderSide.none,
              shape: const StadiumBorder(),
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: text,
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: bg,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
    this.canReport = false,
    this.postId = '',
  });

  final Comment comment;
  final bool canDelete;
  final VoidCallback? onDelete;
  final bool canReport;
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;

    final readText = isDark ? cardCharcoalText : cardCreamText;
    final readSub = isDark ? cardCharcoalSubtext : cardCreamSubtext;
    final readAccent = isDark ? cardCharcoalAccent : cardCreamAccent;
    final avatarBg = isDark ? cardCharcoalMid : cardCreamMid;

    final authorName =
        comment.authorName.isNotEmpty ? comment.authorName : 'Unknown';

    final created = comment.createdAt;
    final createdText = created.millisecondsSinceEpoch == 0
        ? ''
        : '${created.year.toString().padLeft(4, '0')}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}';

    final canTapAuthor = comment.authorId.isNotEmpty;
    void tapAuthor() {
      if (canTapAuthor) context.push('/profile/${comment.authorId}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            onTap: canTapAuthor ? tapAuthor : null,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: avatarBg,
              child: Icon(
                Icons.person_outline,
                size: 20,
                color: readSub,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: GestureDetector(
                        onTap: canTapAuthor ? tapAuthor : null,
                        child: Text(
                          authorName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: canTapAuthor ? readAccent : readText,
                          ),
                        ),
                      ),
                    ),
                    if (createdText.isNotEmpty)
                      Text(
                        createdText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: readSub,
                        ),
                      ),
                    if (canDelete)
                      IconButton(
                        onPressed: onDelete,
                        icon: Icon(Icons.delete_outline, color: readSub),
                        tooltip: 'Delete comment',
                        visualDensity: VisualDensity.compact,
                      ),
                    if (canReport)
                      IconButton(
                        onPressed: () => _showReportCommentDialog(
                          context,
                          ref,
                          comment: comment,
                          postId: postId,
                        ),
                        icon: Icon(Icons.flag_outlined, size: 18, color: readSub),
                        tooltip: 'Report comment',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  comment.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    color: readText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentInputBar extends ConsumerWidget {
  const _CommentInputBar({
    required this.controller,
    required this.onSubmit,
    required this.isSubmitting,
    required this.isRateLimited,
    required this.helperText,
    this.focusNode,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool isSubmitting;
  final bool isRateLimited;
  final String? helperText;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;

    final readText = isDark ? cardCharcoalText : cardCreamText;
    final readSub = isDark ? cardCharcoalSubtext : cardCreamSubtext;
    final readAccent = isDark ? cardCharcoalAccent : cardCreamAccent;
    final inputBg = isDark ? cardCharcoalMid : cardCreamMid;

    final canSubmit = !isSubmitting && !isRateLimited;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (helperText != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 6, right: 6),
              child: Text(
                helperText!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => canSubmit ? onSubmit() : null,
                    style: TextStyle(color: readText),
                    decoration: InputDecoration(
                      hintText: 'Add a comment…',
                      hintStyle: TextStyle(color: readSub),
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                width: 48,
                child: IconButton.filled(
                  onPressed: canSubmit ? onSubmit : null,
                  icon: isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    foregroundColor: readAccent,
                    backgroundColor: inputBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostDetailSkeleton extends StatelessWidget {
  const _PostDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final base = colorScheme.surfaceContainerHighest;
    final highlight = colorScheme.surfaceContainerHigh;

    Widget bar({double? width, required double height, double radius = 10}) {
      return Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    Widget commentSkeleton() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bar(width: 140, height: 12, radius: 8),
                const SizedBox(height: 8),
                bar(height: 12, radius: 8),
                const SizedBox(height: 6),
                bar(width: 220, height: 12, radius: 8),
              ],
            ),
          ),
        ],
      );
    }

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: <Widget>[
          bar(width: 260, height: 32, radius: 14),
          const SizedBox(height: 18),
          bar(width: 180, height: 14, radius: 8),
          const SizedBox(height: 22),
          bar(height: 14, radius: 8),
          const SizedBox(height: 10),
          bar(height: 14, radius: 8),
          const SizedBox(height: 10),
          bar(width: 280, height: 14, radius: 8),
          const SizedBox(height: 24),
          bar(width: 120, height: 18, radius: 10),
          const SizedBox(height: 14),
          commentSkeleton(),
          const SizedBox(height: 16),
          commentSkeleton(),
          const SizedBox(height: 16),
          commentSkeleton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Shown when a post returns 404 - likely deleted or archived by the author.
class _PostUnavailableView extends StatelessWidget {
  const _PostUnavailableView({
    required this.authorId,
    required this.authorName,
  });

  final String authorId;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasAuthor = authorId.trim().isNotEmpty;
    final displayName =
        authorName.trim().isNotEmpty ? authorName.trim() : 'the author';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.article_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Post unavailable',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'This post has been deleted or archived by $displayName.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasAuthor) ...<Widget>[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.push('/profile/$authorId'),
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text('View $displayName\'s profile'),
              ),
            ],
          ],
        ),
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

// ─── Post Reporting Dialogs ──────────────────────────────────────────────────

void _showReportDialog(BuildContext context, WidgetRef ref, Post post) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Story',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? cardCharcoalText : cardCreamText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Why are you reporting this story?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                ),
              ),
              const SizedBox(height: 20),
              _ReportOption(
                label: 'Spam',
                onTap: () => _submitReport(context, ref, post, 'spam'),
                isDark: isDark,
              ),
              _ReportOption(
                label: 'Abuse or Harassment',
                onTap: () => _submitReport(context, ref, post, 'abuse'),
                isDark: isDark,
              ),
              _ReportOption(
                label: 'Other',
                onTap: () async {
                  Navigator.pop(context); // close bottom sheet
                  final customReason = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
                        title: Text(
                          'Specify Reason',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.bold,
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                        ),
                        content: TextField(
                          controller: controller,
                          maxLength: 200,
                          autofocus: true,
                          style: GoogleFonts.inter(
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter reason (up to 200 characters)...',
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark ? cardCharcoalText : cardCreamText,
                              ),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'CANCEL',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final text = controller.text.trim();
                              if (text.isNotEmpty) {
                                Navigator.pop(context, text);
                              }
                            },
                            child: Text(
                              'SUBMIT',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalText : cardCreamText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                  if (customReason != null && customReason.isNotEmpty) {
                    if (context.mounted) {
                      _submitReport(context, ref, post, customReason, popContext: false);
                    }
                  }
                },
                isDark: isDark,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReportOption extends StatelessWidget {
  const _ReportOption({
    required this.label,
    required this.onTap,
    required this.isDark,
  });
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? cardCharcoalText : cardCreamText;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? cardCharcoalEdge : cardCreamEdge,
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _submitReport(
  BuildContext context,
  WidgetRef ref,
  Post post,
  String reason, {
  bool popContext = true,
}) async {
  if (popContext) {
    Navigator.pop(context); // close bottom sheet
  }

  final dio = ref.read(apiClientProvider).dio;
  try {
    await dio.post<void>(
      '/api/v1/posts/${post.id}/report',
      data: <String, dynamic>{'reason': reason},
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you. The story has been reported for review.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Pop the details screen to return to the deck
    Navigator.of(context).pop();

    // Swipe away the reported post automatically in the deck
    ref.read(swipeDeckControllerProvider.notifier).swipe(
          storyId: post.id,
          direction: 'left', // swipe left (skip)
        );
  } on DioException catch (e) {
    if (!context.mounted) return;
    final msg = e.response?.data?['detail']?.toString() ?? 'Failed to submit report';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<void> _showReportCommentDialog(
  BuildContext context,
  WidgetRef ref, {
  required Comment comment,
  required String postId,
}) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Comment',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? cardCharcoalText : cardCreamText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Why are you reporting this comment?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                ),
              ),
              const SizedBox(height: 20),
              _ReportOption(
                label: 'Spam',
                onTap: () => _submitCommentReport(
                  ctx, ref,
                  comment: comment, postId: postId, reason: 'spam',
                ),
                isDark: isDark,
              ),
              _ReportOption(
                label: 'Abuse or Harassment',
                onTap: () => _submitCommentReport(
                  ctx, ref,
                  comment: comment, postId: postId, reason: 'abuse',
                ),
                isDark: isDark,
              ),
              _ReportOption(
                label: 'Other',
                onTap: () async {
                  Navigator.pop(ctx);
                  final customReason = await showDialog<String>(
                    context: context,
                    builder: (dialogCtx) {
                      final ctrl = TextEditingController();
                      return AlertDialog(
                        backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
                        title: Text(
                          'Specify Reason',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.bold,
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                        ),
                        content: TextField(
                          controller: ctrl,
                          maxLength: 200,
                          autofocus: true,
                          style: GoogleFonts.inter(
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter reason (up to 200 characters)...',
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark ? cardCharcoalText : cardCreamText,
                              ),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            child: Text(
                              'CANCEL',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final text = ctrl.text.trim();
                              if (text.isNotEmpty) Navigator.pop(dialogCtx, text);
                            },
                            child: Text(
                              'SUBMIT',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalText : cardCreamText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                  if (customReason != null && customReason.isNotEmpty) {
                    if (context.mounted) {
                      _submitCommentReport(
                        context, ref,
                        comment: comment, postId: postId,
                        reason: customReason, popContext: false,
                      );
                    }
                  }
                },
                isDark: isDark,
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _submitCommentReport(
  BuildContext context,
  WidgetRef ref, {
  required Comment comment,
  required String postId,
  required String reason,
  bool popContext = true,
}) async {
  if (popContext && context.mounted) Navigator.pop(context);

  final dio = ref.read(apiClientProvider).dio;
  try {
    await dio.post<void>(
      '/api/v1/posts/$postId/comments/${comment.id}/report',
      data: <String, dynamic>{'reason': reason},
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Comment reported. Thank you for keeping PaperStock safe.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } on DioException catch (e) {
    if (!context.mounted) return;
    final msg = e.response?.data?['detail']?.toString() ?? 'Failed to submit report';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
