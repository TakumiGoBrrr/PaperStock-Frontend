import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client_provider.dart';
import '../../feed/models/post.dart';
import '../models/user_profile.dart';
import '../repository/profile_repository.dart';

class ProfileState {
  const ProfileState({
    required this.userId,
    required this.isMe,
    required this.profile,
    required this.posts,
    required this.postsNextCursor,
    required this.postsHasMore,
    required this.isLoadingMorePosts,
    required this.isRefreshingPosts,
    required this.bookmarksEnabled,
    required this.bookmarks,
    required this.bookmarksNextCursor,
    required this.bookmarksHasMore,
    required this.isLoadingMoreBookmarks,
    required this.isRefreshingBookmarks,
  });

  final String userId;
  final bool isMe;
  final UserProfile profile;

  final List<Post> posts;
  final String? postsNextCursor;
  final bool postsHasMore;
  final bool isLoadingMorePosts;
  final bool isRefreshingPosts;

  final bool bookmarksEnabled;
  final List<Post> bookmarks;
  final String? bookmarksNextCursor;
  final bool bookmarksHasMore;
  final bool isLoadingMoreBookmarks;
  final bool isRefreshingBookmarks;

  ProfileState copyWith({
    bool? isMe,
    UserProfile? profile,
    List<Post>? posts,
    String? postsNextCursor,
    bool? postsHasMore,
    bool? isLoadingMorePosts,
    bool? isRefreshingPosts,
    bool? bookmarksEnabled,
    List<Post>? bookmarks,
    String? bookmarksNextCursor,
    bool? bookmarksHasMore,
    bool? isLoadingMoreBookmarks,
    bool? isRefreshingBookmarks,
  }) {
    return ProfileState(
      userId: userId,
      isMe: isMe ?? this.isMe,
      profile: profile ?? this.profile,
      posts: posts ?? this.posts,
      postsNextCursor: postsNextCursor ?? this.postsNextCursor,
      postsHasMore: postsHasMore ?? this.postsHasMore,
      isLoadingMorePosts: isLoadingMorePosts ?? this.isLoadingMorePosts,
      isRefreshingPosts: isRefreshingPosts ?? this.isRefreshingPosts,
      bookmarksEnabled: bookmarksEnabled ?? this.bookmarksEnabled,
      bookmarks: bookmarks ?? this.bookmarks,
      bookmarksNextCursor: bookmarksNextCursor ?? this.bookmarksNextCursor,
      bookmarksHasMore: bookmarksHasMore ?? this.bookmarksHasMore,
      isLoadingMoreBookmarks:
          isLoadingMoreBookmarks ?? this.isLoadingMoreBookmarks,
      isRefreshingBookmarks:
          isRefreshingBookmarks ?? this.isRefreshingBookmarks,
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return ProfileRepository(dio: dio);
});

final currentUserIdProvider = FutureProvider<String?>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  return repo.getCurrentUserId();
});

final profileScrollToTopProvider = StateProvider<int>((ref) => 0);

final profileControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    ProfileController, ProfileState, String>(
  ProfileController.new,
);

class ProfileController
    extends AutoDisposeFamilyAsyncNotifier<ProfileState, String> {
  bool _followInFlight = false;

  @override
  Future<ProfileState> build(String userId) async {
    final repo = ref.watch(profileRepositoryProvider);

    final meId = await ref.watch(currentUserIdProvider.future);
    final isMe = meId != null && meId == userId;

    final results = await Future.wait<Object?>(<Future<Object?>>[
      repo.getUserProfile(userId: userId),
      repo.getUserPosts(userId: userId),
      if (isMe) repo.getMyBookmarks() else Future<PostsPage?>.value(null),
    ]);

    final profile = results[0] as UserProfile;
    final postsPage = results[1] as PostsPage;
    final bookmarksPage = results[2] as PostsPage?;

    return ProfileState(
      userId: userId,
      isMe: isMe,
      profile: profile,
      posts: postsPage.items,
      postsNextCursor: postsPage.nextCursor,
      postsHasMore: postsPage.hasMore,
      isLoadingMorePosts: false,
      isRefreshingPosts: false,
      bookmarksEnabled: isMe,
      bookmarks: bookmarksPage?.items ?? const <Post>[],
      bookmarksNextCursor: bookmarksPage?.nextCursor,
      bookmarksHasMore: bookmarksPage?.hasMore ?? false,
      isLoadingMoreBookmarks: false,
      isRefreshingBookmarks: false,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  void removePost(String postId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.posts.where((p) => p.id != postId).toList();
    if (updated.length == current.posts.length) return;
    state = AsyncData(current.copyWith(posts: updated));
  }

  void updatePostArchived(String postId, {required bool isArchived}) {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.posts
        .map((p) => p.id == postId ? p.copyWith(isArchived: isArchived) : p)
        .toList();
    state = AsyncData(current.copyWith(posts: updated));
  }

  void updatePost(Post post) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updatedPosts = current.posts
        .map((p) => p.id == post.id ? post : p)
        .toList();

    final updatedBookmarks = current.bookmarks
        .map((p) => p.id == post.id ? post : p)
        .toList();

    state = AsyncData(
      current.copyWith(
        posts: updatedPosts,
        bookmarks: updatedBookmarks,
      ),
    );
  }

  void insertPostAtTop(Post post) {
    final current = state.valueOrNull;
    if (current == null) return;

    final withoutDupes = current.posts.where((p) => p.id != post.id).toList();
    state = AsyncData(
      current.copyWith(
        posts: <Post>[post, ...withoutDupes],
      ),
    );
  }

  Future<void> refreshPostsFirstPage({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }

    if (current.isRefreshingPosts) return;
    if (current.isLoadingMorePosts) return;

    state = AsyncData(current.copyWith(isRefreshingPosts: true));

    try {
      final repo = ref.read(profileRepositoryProvider);
      final profile = await repo.getUserProfile(userId: current.userId);
      final page = await repo.getUserPosts(
        userId: current.userId,
        cursor: null,
        limit: limit,
      );

      state = AsyncData(
        current.copyWith(
          profile: profile,
          posts: page.items,
          postsNextCursor: page.nextCursor,
          postsHasMore: page.hasMore,
          isLoadingMorePosts: false,
          isRefreshingPosts: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(isRefreshingPosts: false));
    }
  }

  Future<void> fetchNextPosts({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isRefreshingPosts) return;
    if (!current.postsHasMore) return;

    final cursor = current.postsNextCursor;
    if (cursor == null || cursor.isEmpty) return;

    if (current.isLoadingMorePosts) return;

    state = AsyncData(current.copyWith(isLoadingMorePosts: true));

    final repo = ref.read(profileRepositoryProvider);

    final result = await AsyncValue.guard(() async {
      final page = await repo.getUserPosts(
        userId: current.userId,
        cursor: cursor,
        limit: limit,
      );
      return current.copyWith(
        posts: <Post>[...current.posts, ...page.items],
        postsNextCursor: page.nextCursor,
        postsHasMore: page.hasMore,
        isLoadingMorePosts: false,
      );
    });

    if (result.hasError) {
      state = AsyncData(current.copyWith(isLoadingMorePosts: false));
      return;
    }

    state = AsyncData(result.requireValue);
  }

  Future<void> refreshBookmarksFirstPage({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }

    if (!current.bookmarksEnabled) return;
    if (current.isRefreshingBookmarks) return;
    if (current.isLoadingMoreBookmarks) return;

    state = AsyncData(current.copyWith(isRefreshingBookmarks: true));

    try {
      final repo = ref.read(profileRepositoryProvider);
      final page = await repo.getMyBookmarks(cursor: null, limit: limit);

      state = AsyncData(
        current.copyWith(
          bookmarks: page.items,
          bookmarksNextCursor: page.nextCursor,
          bookmarksHasMore: page.hasMore,
          isLoadingMoreBookmarks: false,
          isRefreshingBookmarks: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(isRefreshingBookmarks: false));
    }
  }

  Future<void> fetchNextBookmarks({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.bookmarksEnabled) return;
    if (current.isRefreshingBookmarks) return;
    if (!current.bookmarksHasMore) return;

    final cursor = current.bookmarksNextCursor;
    if (cursor == null || cursor.isEmpty) return;

    if (current.isLoadingMoreBookmarks) return;

    state = AsyncData(current.copyWith(isLoadingMoreBookmarks: true));

    final repo = ref.read(profileRepositoryProvider);

    final result = await AsyncValue.guard(() async {
      final page = await repo.getMyBookmarks(cursor: cursor, limit: limit);
      return current.copyWith(
        bookmarks: <Post>[...current.bookmarks, ...page.items],
        bookmarksNextCursor: page.nextCursor,
        bookmarksHasMore: page.hasMore,
        isLoadingMoreBookmarks: false,
      );
    });

    if (result.hasError) {
      state = AsyncData(current.copyWith(isLoadingMoreBookmarks: false));
      return;
    }

    state = AsyncData(result.requireValue);
  }

  void setFollowingCount(int count) {
    final current = state.valueOrNull;
    if (current == null) return;

    final corrected = current.profile.copyWith(followingCount: count);
    state = AsyncData(current.copyWith(profile: corrected));
  }

  Future<void> toggleFollow() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isMe) return;
    if (_followInFlight) return;

    _followInFlight = true;

    final before = current.profile;
    final nextFollow = !before.isFollowing;

    final optimistic = before.copyWith(
      isFollowing: nextFollow,
      followersCount:
          math.max(0, before.followersCount + (nextFollow ? 1 : -1)),
    );

    state = AsyncData(current.copyWith(profile: optimistic));

    try {
      final repo = ref.read(profileRepositoryProvider);
      final serverIsFollowing = nextFollow
          ? await repo.follow(userId: current.userId)
          : await repo.unfollow(userId: current.userId);

      final now = state.valueOrNull;
      if (now == null) return;

      if (serverIsFollowing != optimistic.isFollowing) {
        // If the server disagrees, revert the count delta too.
        final corrected = before.copyWith(isFollowing: serverIsFollowing);
        state = AsyncData(now.copyWith(profile: corrected));
      }
    } catch (_) {
      state = AsyncData(current.copyWith(profile: before));
      rethrow;
    } finally {
      _followInFlight = false;
    }
  }
}
