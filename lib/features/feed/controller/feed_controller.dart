import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client_provider.dart';
import '../models/post.dart';
import '../repository/feed_repository.dart';

class FeedState {
  const FeedState({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isRefreshing,
  });

  final List<Post> items;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isRefreshing;

  FeedState copyWith({
    List<Post>? items,
    String? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return FeedState(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  static const FeedState empty = FeedState(
    items: <Post>[],
    nextCursor: null,
    hasMore: false,
    isLoadingMore: false,
    isRefreshing: false,
  );
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return FeedRepository(dio: dio);
});

final feedControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<FeedController, FeedState, FeedType>(
  FeedController.new,
);

class FeedController
    extends AutoDisposeFamilyAsyncNotifier<FeedState, FeedType> {
  final Set<String> _likeInFlight = <String>{};
  final Set<String> _bookmarkInFlight = <String>{};

  @override
  Future<FeedState> build(FeedType arg) async {
    final repo = ref.watch(feedRepositoryProvider);
    final page = await repo.getFeed(type: arg, cursor: null);
    return FeedState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      isLoadingMore: false,
      isRefreshing: false,
    );
  }

  void insertAtTop(Post post) {
    final current = state.valueOrNull;
    if (current == null) return;

    if (current.items.any((p) => p.id == post.id)) return;

    state = AsyncData(
      current.copyWith(items: <Post>[post, ...current.items]),
    );
  }

  void removeById(String postId) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.items.where((p) => p.id != postId).toList();
    if (updated.length == current.items.length) return;

    state = AsyncData(current.copyWith(items: updated));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> refreshFirstPage({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }

    if (current.isRefreshing) return;

    // Avoid interleaving pagination results with a refresh.
    if (current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isRefreshing: true));

    try {
      final repo = ref.read(feedRepositoryProvider);
      final page = await repo.getFeed(type: arg, cursor: null, limit: limit);
      state = AsyncData(
        current.copyWith(
          items: page.items,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(isRefreshing: false));
    }
  }

  /// Prepared for cursor-based pagination (not fully wired in UI).
  Future<void> fetchNext({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isRefreshing) return;
    if (!current.hasMore) return;
    final cursor = current.nextCursor;
    if (cursor == null || cursor.isEmpty) return;

    if (current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final repo = ref.read(feedRepositoryProvider);

    final result = await AsyncValue.guard(() async {
      final page = await repo.getFeed(type: arg, cursor: cursor, limit: limit);
      return current.copyWith(
        items: <Post>[...current.items, ...page.items],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    });

    if (result.hasError) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      return;
    }

    state = AsyncData(result.requireValue);
  }

  Future<void> toggleLike(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (_likeInFlight.contains(postId)) return;

    final index = current.items.indexWhere((p) => p.id == postId);
    if (index < 0) return;

    _likeInFlight.add(postId);

    final previous = current.items[index];
    final nextLiked = !previous.isLiked;
    final optimistic = previous.copyWith(
      isLiked: nextLiked,
      likesCount: math.max(0, previous.likesCount + (nextLiked ? 1 : -1)),
    );

    _replaceById(postId: postId, post: optimistic);

    try {
      final repo = ref.read(feedRepositoryProvider);
      final serverPost = await repo.toggleLike(postId: postId);
      _replaceById(postId: postId, post: serverPost);
    } catch (_) {
      _replaceById(postId: postId, post: previous);
      rethrow;
    } finally {
      _likeInFlight.remove(postId);
    }
  }

  Future<void> toggleBookmark(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (_bookmarkInFlight.contains(postId)) return;

    final index = current.items.indexWhere((p) => p.id == postId);
    if (index < 0) return;

    _bookmarkInFlight.add(postId);

    final previous = current.items[index];
    final nextBookmarked = !previous.isBookmarked;
    final optimistic = previous.copyWith(isBookmarked: nextBookmarked);

    _replaceById(postId: postId, post: optimistic);

    try {
      final repo = ref.read(feedRepositoryProvider);
      if (nextBookmarked) {
        final serverPost = await repo.addBookmark(postId: postId);
        _replaceById(postId: postId, post: serverPost);
      } else {
        await repo.removeBookmark(postId: postId);
      }
    } catch (_) {
      _replaceById(postId: postId, post: previous);
      rethrow;
    } finally {
      _bookmarkInFlight.remove(postId);
    }
  }

  Future<void> softDelete(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.items.where((p) => p.id != postId).toList();
    state = AsyncData(current.copyWith(items: updated));

    try {
      final repo = ref.read(feedRepositoryProvider);
      await repo.softDeletePost(postId: postId);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  Future<void> archive(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // Archived posts don't belong in the public feed — remove optimistically.
    final updated = current.items.where((p) => p.id != postId).toList();
    state = AsyncData(current.copyWith(items: updated));

    try {
      final repo = ref.read(feedRepositoryProvider);
      await repo.archivePost(postId: postId);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  void _replaceById({required String postId, required Post post}) {
    final current = state.valueOrNull;
    if (current == null) return;

    final index = current.items.indexWhere((p) => p.id == postId);
    if (index < 0 || index >= current.items.length) return;

    final updated = List<Post>.of(current.items);
    updated[index] = post;
    state = AsyncData(current.copyWith(items: updated));
  }
}
