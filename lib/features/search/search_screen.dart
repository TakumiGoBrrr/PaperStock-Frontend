import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/theme/app_theme.dart';
import '../feed/controller/feed_controller.dart';
import '../feed/models/feed_post.dart';
import '../feed/widgets/post_card.dart';
import '../profile/controller/profile_controller.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

class _PostResult {
  const _PostResult({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.bodyPreview,
    required this.tags,
    required this.readTimeMinutes,
    required this.isLiked,
    required this.isBookmarked,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String bodyPreview;
  final List<String> tags;
  final int readTimeMinutes;
  final bool isLiked;
  final bool isBookmarked;

  _PostResult copyWith({bool? isLiked, bool? isBookmarked}) {
    return _PostResult(
      id: id,
      authorId: authorId,
      authorName: authorName,
      title: title,
      bodyPreview: bodyPreview,
      tags: tags,
      readTimeMinutes: readTimeMinutes,
      isLiked: isLiked ?? this.isLiked,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }

  FeedPost toFeedPost() => FeedPost(
        id: id,
        title: title,
        bodyPreview: bodyPreview,
        tags: tags,
        authorId: authorId,
        authorName: authorName.trim().isEmpty ? 'Unknown' : authorName,
        readTimeMinutes: readTimeMinutes,
      );

  static _PostResult fromJson(Map<String, dynamic> json) {
    final tags = (json['tags'] is List)
        ? (json['tags'] as List)
            .map((t) => t.toString())
            .where((t) => t.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return _PostResult(
      id: (json['id'] as Object?)?.toString() ?? '',
      authorId: (json['author_id'] as Object?)?.toString() ?? '',
      authorName: (json['author_name'] as Object?)?.toString() ?? '',
      title: (json['title'] as Object?)?.toString() ?? '',
      bodyPreview: (json['body'] as Object?)?.toString() ?? '',
      tags: tags,
      readTimeMinutes:
          int.tryParse((json['read_time'] as Object?)?.toString() ?? '0') ?? 0,
      isLiked: json['is_liked'] == true,
      isBookmarked: json['is_bookmarked'] == true,
    );
  }
}

class _UserSearchResult {
  const _UserSearchResult({
    required this.id,
    required this.displayName,
    required this.isFollowing,
  });

  final String id;
  final String displayName;
  final bool isFollowing;

  _UserSearchResult copyWith({
    String? displayName,
    bool? isFollowing,
  }) {
    return _UserSearchResult(
      id: id,
      displayName: displayName ?? this.displayName,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}

// ─── Mode detection ───────────────────────────────────────────────────────────

enum _PostSearchMode { tags, text }

_PostSearchMode _detectMode(String query) =>
    RegExp(r'#\w').hasMatch(query.trim())
        ? _PostSearchMode.tags
        : _PostSearchMode.text;

String _toTagsCsv(String input) {
  final parts = input
      .trim()
      .split(RegExp(r'[\s,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => e.startsWith('#') ? e.substring(1) : e)
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  final unique = <String>[];
  final seen = <String>{};
  for (final p in parts) {
    final lower = p.toLowerCase();
    if (seen.add(lower)) unique.add(lower);
  }
  return unique.join(',');
}

// ─── Screen ───────────────────────────────────────────────────────────────────

enum _SearchType { posts, users }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _debounceDuration = Duration(milliseconds: 350);

  final _controller = TextEditingController();
  final _postScrollController = ScrollController();
  Timer? _debounce;

  _SearchType _type = _SearchType.posts;
  _PostSearchMode? _activePostMode;

  // Post search state
  List<_PostResult> _postResults = const <_PostResult>[];
  String? _postNextCursor;
  bool _postHasMore = false;

  // User search state
  List<_UserSearchResult> _userResults = const <_UserSearchResult>[];

  // Shared
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  List<String> _trendingTags = const <String>[];

  final Set<String> _likeInFlight = <String>{};
  final Set<String> _bookmarkInFlight = <String>{};
  final Set<String> _userFollowInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _postScrollController.addListener(_onPostScroll);
    unawaited(_loadTrendingTags());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onQueryChanged)
      ..dispose();
    _postScrollController
      ..removeListener(_onPostScroll)
      ..dispose();
    super.dispose();
  }

  // ── Event listeners ──────────────────────────────────────────────────────────

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      if (_type == _SearchType.posts) {
        unawaited(_runPostSearch(_controller.text));
      } else {
        unawaited(_runUserSearch(_controller.text));
      }
    });
  }

  void _onPostScroll() {
    if (!_postScrollController.hasClients) return;
    final pos = _postScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 &&
        _postHasMore &&
        !_isLoadingMore) {
      unawaited(_loadMorePosts());
    }
  }

  Dio get _dio => ref.read(apiClientProvider).dio;

  // ── Data fetching ─────────────────────────────────────────────────────────────

  Future<void> _loadTrendingTags() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search/trending-tags',
      );
      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is List) ? (body['data'] as List) : const [];
      final tags = data
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _trendingTags = tags);
    } catch (_) {}
  }

  Future<void> _runPostSearch(String rawQuery, {bool append = false}) async {
    final q = rawQuery.trim();

    if (q.isEmpty) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
        _postResults = const <_PostResult>[];
        _postNextCursor = null;
        _postHasMore = false;
        _activePostMode = null;
      });
      return;
    }

    final mode = _detectMode(q);

    if (!append) {
      setState(() {
        _isLoading = true;
        _error = null;
        _activePostMode = mode;
      });
    }

    final queryParam = mode == _PostSearchMode.tags ? _toTagsCsv(q) : q;
    if (queryParam.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search',
        queryParameters: <String, dynamic>{
          'type': 'posts',
          'mode': mode == _PostSearchMode.tags ? 'tags' : 'text',
          'q': queryParam,
          if (append && _postNextCursor != null) 'cursor': _postNextCursor,
        },
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};
      final itemsJson = (data['items'] is List)
          ? (data['items'] as List)
          : const <dynamic>[];

      final items = itemsJson
          .whereType<Map<String, dynamic>>()
          .map(_PostResult.fromJson)
          .where((p) => p.id.trim().isNotEmpty)
          .toList(growable: false);

      final nextCursor = (data['next_cursor'] as Object?)?.toString();
      final hasMore = data['has_more'] == true;

      if (!mounted) return;
      setState(() {
        if (append) {
          _postResults = <_PostResult>[..._postResults, ...items];
          _isLoadingMore = false;
        } else {
          _postResults = items;
          _isLoading = false;
        }
        _postNextCursor = nextCursor;
        _postHasMore = hasMore;
        _error = null;
        _activePostMode = mode;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = (e.response?.data is Map
                ? (e.response!.data as Map)['detail']?.toString()
                : null) ??
            e.message;
        if (!append) _postResults = const <_PostResult>[];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = e.toString();
        if (!append) _postResults = const <_PostResult>[];
      });
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_postHasMore) return;
    setState(() => _isLoadingMore = true);
    await _runPostSearch(_controller.text, append: true);
  }

  Future<void> _runUserSearch(String rawQuery) async {
    final q = rawQuery.trim();

    if (q.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = null;
        _userResults = const <_UserSearchResult>[];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search',
        queryParameters: <String, dynamic>{'type': 'users', 'q': q},
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};
      final itemsJson = (data['items'] is List)
          ? (data['items'] as List)
          : const <dynamic>[];

      final items = itemsJson
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final id = (e['id'] as Object?)?.toString() ?? '';
            final name = (e['display_name'] as Object?)?.toString() ?? '';
            final isFollowing = e['is_following'] == true;
            return _UserSearchResult(
              id: id,
              displayName: name.trim().isEmpty ? 'Unknown' : name.trim(),
              isFollowing: isFollowing,
            );
          })
          .where((u) => u.id.trim().isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _userResults = items;
        _isLoading = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _userResults = const <_UserSearchResult>[];
        _error = e.response?.data?.toString() ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _userResults = const <_UserSearchResult>[];
        _error = e.toString();
      });
    }
  }

  // ── Interactions ──────────────────────────────────────────────────────────────

  Future<void> _toggleLike(String postId) async {
    if (_likeInFlight.contains(postId)) return;
    _likeInFlight.add(postId);

    final idx = _postResults.indexWhere((p) => p.id == postId);
    if (idx < 0) {
      _likeInFlight.remove(postId);
      return;
    }

    final prev = _postResults[idx];
    _updatePost(idx, prev.copyWith(isLiked: !prev.isLiked));

    try {
      final repo = ref.read(feedRepositoryProvider);
      final updated = await repo.toggleLike(postId: postId);
      if (!mounted) return;
      final i = _postResults.indexWhere((p) => p.id == postId);
      if (i >= 0) _updatePost(i, _postResults[i].copyWith(isLiked: updated.isLiked));
    } catch (_) {
      if (!mounted) return;
      final i = _postResults.indexWhere((p) => p.id == postId);
      if (i >= 0) _updatePost(i, prev);
    } finally {
      _likeInFlight.remove(postId);
    }
  }

  Future<void> _toggleBookmark(String postId) async {
    if (_bookmarkInFlight.contains(postId)) return;
    _bookmarkInFlight.add(postId);

    final idx = _postResults.indexWhere((p) => p.id == postId);
    if (idx < 0) {
      _bookmarkInFlight.remove(postId);
      return;
    }

    final prev = _postResults[idx];
    final adding = !prev.isBookmarked;
    _updatePost(idx, prev.copyWith(isBookmarked: adding));

    try {
      final repo = ref.read(feedRepositoryProvider);
      if (adding) {
        final updated = await repo.addBookmark(postId: postId);
        if (!mounted) return;
        final i = _postResults.indexWhere((p) => p.id == postId);
        if (i >= 0) {
          _updatePost(i, _postResults[i].copyWith(isBookmarked: updated.isBookmarked));
        }
      } else {
        await repo.removeBookmark(postId: postId);
      }
    } catch (_) {
      if (!mounted) return;
      final i = _postResults.indexWhere((p) => p.id == postId);
      if (i >= 0) _updatePost(i, prev);
    } finally {
      _bookmarkInFlight.remove(postId);
    }
  }

  void _updatePost(int idx, _PostResult updated) {
    setState(() {
      final list = List<_PostResult>.from(_postResults);
      list[idx] = updated;
      _postResults = list;
    });
  }

  Future<void> _toggleFollow(_UserSearchResult user) async {
    final id = user.id.trim();
    if (id.isEmpty || _userFollowInFlight.contains(id)) return;

    final repo = ref.read(profileRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    final before = user.isFollowing;
    final nextFollowing = !before;

    setState(() {
      _userFollowInFlight.add(id);
      _userResults = _userResults
          .map((u) => u.id == id ? u.copyWith(isFollowing: nextFollowing) : u)
          .toList(growable: false);
    });

    try {
      final isFollowing = nextFollowing
          ? await repo.follow(userId: id)
          : await repo.unfollow(userId: id);

      if (!mounted) return;
      setState(() {
        _userResults = _userResults
            .map((u) => u.id == id ? u.copyWith(isFollowing: isFollowing) : u)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _userResults = _userResults
            .map((u) => u.id == id ? u.copyWith(isFollowing: before) : u)
            .toList(growable: false);
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to update follow. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _userFollowInFlight.remove(id));
    }
  }

  void _setType(_SearchType next) {
    if (_type == next) return;
    _debounce?.cancel();
    setState(() {
      _type = next;
      _error = null;
      _isLoading = false;
    });

    final q = _controller.text.trim();
    if (q.isEmpty) return;
    if (next == _SearchType.posts) {
      unawaited(_runPostSearch(_controller.text));
    } else {
      unawaited(_runUserSearch(_controller.text));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final query = _controller.text.trim();
    final meId = ref.watch(currentUserIdProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (_type == _SearchType.posts) {
                _debounce?.cancel();
                unawaited(_runPostSearch(_controller.text));
              }
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _type == _SearchType.posts
                  ? 'Search posts  (#tag or keyword…)'
                  : 'Search users',
              filled: true,
              fillColor:
                  isDark ? softBlack : colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _postResults = const <_PostResult>[];
                          _userResults = const <_UserSearchResult>[];
                          _error = null;
                          _activePostMode = null;
                          _postNextCursor = null;
                          _postHasMore = false;
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<_SearchType>(
            segments: const <ButtonSegment<_SearchType>>[
              ButtonSegment<_SearchType>(
                value: _SearchType.posts,
                label: Text('Posts'),
              ),
              ButtonSegment<_SearchType>(
                value: _SearchType.users,
                label: Text('Users'),
              ),
            ],
            selected: <_SearchType>{_type},
            onSelectionChanged: (selection) => _setType(selection.first),
          ),
        ),
        Expanded(
          child: _type == _SearchType.users
              ? _buildUsersView(theme, colorScheme, query, meId)
              : _buildPostsView(theme, colorScheme, isDark, query),
        ),
      ],
    );
  }

  // ── Posts pane ────────────────────────────────────────────────────────────────

  Widget _buildPostsView(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
    String query,
  ) {
    if (query.isEmpty) {
      return _buildTrendingView(theme, colorScheme, isDark);
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_postResults.isEmpty) {
      return Center(
        child: Text(
          'No posts found',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_activePostMode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: <Widget>[
                _ModeChip(
                  label: _activePostMode == _PostSearchMode.tags
                      ? '# Tag search'
                      : '⌕ Keyword search',
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _postScrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: _postResults.length + (_postHasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _postResults.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _isLoadingMore
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              }

              final post = _postResults[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PostCard(
                  post: post.toFeedPost(),
                  isLiked: post.isLiked,
                  isBookmarked: post.isBookmarked,
                  onLike: () => _toggleLike(post.id),
                  onBookmark: () => _toggleBookmark(post.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingView(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    if (_trendingTags.isEmpty) {
      return Center(
        child: Text(
          'Search posts by #tag or keyword',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.trending_up_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Trending topics',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trendingTags.take(12).map((tag) {
              final raw = tag.trim();
              final value =
                  raw.startsWith('#') ? raw.substring(1) : raw;
              final display = value.isEmpty ? '#' : '#$value';

              return ActionChip(
                label: Text(display),
                onPressed: () {
                  _controller.text = '#$value';
                  _controller.selection = TextSelection.collapsed(
                    offset: _controller.text.length,
                  );
                },
                backgroundColor: isDark
                    ? softBlack
                    : colorScheme.surfaceContainerHighest,
                side: isDark
                    ? const BorderSide(color: borderBlack)
                    : BorderSide(color: colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                labelStyle: GoogleFonts.inter(
                  textStyle: theme.textTheme.labelMedium?.copyWith(
                    color: isDark ? Colors.white70 : colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  // ── Users pane ────────────────────────────────────────────────────────────────

  Widget _buildUsersView(
    ThemeData theme,
    ColorScheme colorScheme,
    String query,
    String? meId,
  ) {
    if (query.isEmpty) {
      return Center(
        child: Text(
          'Search users',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_userResults.isEmpty) {
      return Center(
        child: Text(
          'No results',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _runUserSearch(_controller.text),
      child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _userResults.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final user = _userResults[index];
        final isMe = meId != null && meId == user.id;
        final inFlight = _userFollowInFlight.contains(user.id);

        final avatar = CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_outline,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        );

        final buttonLabel = user.isFollowing ? 'Following' : 'Follow';
        final button = isMe
            ? const SizedBox.shrink()
            : (user.isFollowing
                ? OutlinedButton(
                    onPressed: inFlight ? null : () => _toggleFollow(user),
                    child: Text(buttonLabel),
                  )
                : FilledButton(
                    onPressed: inFlight ? null : () => _toggleFollow(user),
                    child: Text(buttonLabel),
                  ));

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push('/profile/${user.id}'),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: <Widget>[
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user.displayName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  button,
                ],
              ),
            ),
          ),
        );
      },
    ),
    );
  }
}

// ─── Mode chip ────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.colorScheme,
  });

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.primary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
