import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../feed/models/feed_post.dart';
import '../feed/models/post.dart';
import '../feed/repository/feed_repository.dart';
import '../feed/widgets/feed_skeleton_list.dart';
import '../feed/widgets/feed_state_views.dart';
import '../feed/widgets/post_card.dart';

class TagSearchResultsScreen extends ConsumerStatefulWidget {
  const TagSearchResultsScreen({super.key, required this.tags});

  final List<String> tags;

  @override
  ConsumerState<TagSearchResultsScreen> createState() =>
      _TagSearchResultsScreenState();
}

class _TagSearchResultsScreenState
    extends ConsumerState<TagSearchResultsScreen> {
  static const _limit = 20;
  static const _threshold = 800.0;

  final _scrollController = ScrollController();

  List<Post> _items = const <Post>[];
  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _initialLoading = true;
  String? _error;

  final Set<String> _likeInFlight = <String>{};
  final Set<String> _bookmarkInFlight = <String>{};

  Dio get _dio => ref.read(apiClientProvider).dio;

  FeedRepository get _feedRepo =>
      FeedRepository(dio: ref.read(apiClientProvider).dio);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage(cursor: null);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels < _threshold) {
      _fetchNext();
    }
  }

  String get _tagsCsv => widget.tags.join(',');

  Future<void> _loadPage({required String? cursor}) async {
    if (!mounted) return;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search',
        queryParameters: <String, dynamic>{
          'type': 'posts',
          'q': _tagsCsv,
          'limit': _limit,
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};

      final itemsJson =
          (data['items'] is List) ? (data['items'] as List) : const <dynamic>[];
      final newItems = itemsJson
          .whereType<Map<String, dynamic>>()
          .map(Post.fromJson)
          .toList(growable: false);

      final nextCursor = data['next_cursor']?.toString();
      final hasMore = data['has_more'] == true && nextCursor != null;

      if (!mounted) return;
      setState(() {
        if (cursor == null) {
          _items = newItems;
        } else {
          _items = <Post>[..._items, ...newItems];
        }
        _nextCursor = nextCursor;
        _hasMore = hasMore;
        _initialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _isLoadingMore = false;
        _error = e.response?.data?.toString() ?? e.message ?? 'Network error';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _isLoadingMore = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _fetchNext() async {
    if (!_hasMore) return;
    if (_isLoadingMore) return;
    final cursor = _nextCursor;
    if (cursor == null || cursor.isEmpty) return;

    setState(() => _isLoadingMore = true);
    await _loadPage(cursor: cursor);
  }

  Future<void> _refresh() async {
    setState(() {
      _initialLoading = true;
      _error = null;
      _items = const <Post>[];
      _nextCursor = null;
      _hasMore = false;
      _isLoadingMore = false;
    });
    await _loadPage(cursor: null);
  }

  void _replaceById(String postId, Post updated) {
    final idx = _items.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final list = List<Post>.of(_items);
    list[idx] = updated;
    setState(() => _items = list);
  }

  Future<void> _toggleLike(String postId) async {
    if (_likeInFlight.contains(postId)) return;
    final idx = _items.indexWhere((p) => p.id == postId);
    if (idx < 0) return;

    _likeInFlight.add(postId);

    final previous = _items[idx];
    final nextLiked = !previous.isLiked;
    _replaceById(
      postId,
      previous.copyWith(
        isLiked: nextLiked,
        likesCount: math.max(0, previous.likesCount + (nextLiked ? 1 : -1)),
      ),
    );

    try {
      final serverPost = await _feedRepo.toggleLike(postId: postId);
      if (mounted) _replaceById(postId, serverPost);
    } catch (_) {
      if (mounted) _replaceById(postId, previous);
    } finally {
      _likeInFlight.remove(postId);
    }
  }

  Future<void> _toggleBookmark(String postId) async {
    if (_bookmarkInFlight.contains(postId)) return;
    final idx = _items.indexWhere((p) => p.id == postId);
    if (idx < 0) return;

    _bookmarkInFlight.add(postId);

    final previous = _items[idx];
    final nextBookmarked = !previous.isBookmarked;
    _replaceById(postId, previous.copyWith(isBookmarked: nextBookmarked));

    try {
      final repo = _feedRepo;
      if (nextBookmarked) {
        final serverPost = await repo.addBookmark(postId: postId);
        if (mounted) _replaceById(postId, serverPost);
      } else {
        await repo.removeBookmark(postId: postId);
      }
    } catch (_) {
      if (mounted) _replaceById(postId, previous);
    } finally {
      _bookmarkInFlight.remove(postId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tagLabel = widget.tags.map((t) => '#$t').join(', ');

    final appBar = GlassAppBar(
      left: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
        tooltip: 'Back',
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'PaperStock',
            style: GoogleFonts.lora(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            'Tag Search',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ],
      ),
    );

    Widget body;

    if (_initialLoading) {
      body = const FeedSkeletonList();
    } else if (_error != null && _items.isEmpty) {
      body = FeedErrorView(
        message: _error!,
        onRetry: _refresh,
      );
    } else if (_items.isEmpty) {
      body = FeedEmptyView(
        title: 'No posts found',
        subtitle: 'No stories tagged $tagLabel yet.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          controller: _scrollController,
          cacheExtent: 800,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: _items.length + (_isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }

            final post = _items[index];
            return PostCard(
              key: ValueKey<String>(post.id),
              post: _toFeedPost(post),
              isLiked: post.isLiked,
              isBookmarked: post.isBookmarked,
              onLike: () => _toggleLike(post.id),
              onBookmark: () => _toggleBookmark(post.id),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: appBar,
      body: SafeArea(
        bottom: false,
        child: body,
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
