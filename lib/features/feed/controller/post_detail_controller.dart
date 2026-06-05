import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client_provider.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../repository/post_detail_repository.dart';

class PostDetailState {
  const PostDetailState({
    required this.post,
    required this.comments,
    required this.currentUserId,
    required this.commentsNextCursor,
    required this.commentsHasMore,
    required this.isLoadingComments,
    required this.isLoadingMoreComments,
    required this.commentsError,
    required this.loadMoreCommentsError,
    required this.isSubmittingComment,
    required this.isCommentRateLimited,
    required this.commentRateLimitUntil,
    required this.uiMessage,
    required this.uiMessageNonce,
  });

  final Post? post;
  final List<Comment> comments;
  final String? currentUserId;
  final String? commentsNextCursor;
  final bool commentsHasMore;
  final bool isLoadingComments;
  final bool isLoadingMoreComments;
  final String? commentsError;
  final String? loadMoreCommentsError;
  final bool isSubmittingComment;

  /// Whether the user is currently rate limited from commenting on this post.
  ///
  /// When [commentRateLimitUntil] is non-null, the limit is considered active
  /// if now is before that timestamp.
  final bool isCommentRateLimited;
  final DateTime? commentRateLimitUntil;

  /// One-off UI message set by the controller (e.g., snackbars).
  final String? uiMessage;
  final int uiMessageNonce;

  PostDetailState copyWith({
    Post? post,
    List<Comment>? comments,
    String? currentUserId,
    String? commentsNextCursor,
    bool? commentsHasMore,
    bool? isLoadingComments,
    bool? isLoadingMoreComments,
    String? commentsError,
    String? loadMoreCommentsError,
    bool? isSubmittingComment,
    bool? isCommentRateLimited,
    DateTime? commentRateLimitUntil,
    String? uiMessage,
    int? uiMessageNonce,
  }) {
    return PostDetailState(
      post: post ?? this.post,
      comments: comments ?? this.comments,
      currentUserId: currentUserId ?? this.currentUserId,
      commentsNextCursor: commentsNextCursor ?? this.commentsNextCursor,
      commentsHasMore: commentsHasMore ?? this.commentsHasMore,
      isLoadingComments: isLoadingComments ?? this.isLoadingComments,
      isLoadingMoreComments:
          isLoadingMoreComments ?? this.isLoadingMoreComments,
      commentsError: commentsError,
      loadMoreCommentsError: loadMoreCommentsError,
      isSubmittingComment: isSubmittingComment ?? this.isSubmittingComment,
      isCommentRateLimited: isCommentRateLimited ?? this.isCommentRateLimited,
      commentRateLimitUntil:
          commentRateLimitUntil ?? this.commentRateLimitUntil,
      uiMessage: uiMessage,
      uiMessageNonce: uiMessageNonce ?? this.uiMessageNonce,
    );
  }

  static const empty = PostDetailState(
    post: null,
    comments: <Comment>[],
    currentUserId: null,
    commentsNextCursor: null,
    commentsHasMore: false,
    isLoadingComments: false,
    isLoadingMoreComments: false,
    commentsError: null,
    loadMoreCommentsError: null,
    isSubmittingComment: false,
    isCommentRateLimited: false,
    commentRateLimitUntil: null,
    uiMessage: null,
    uiMessageNonce: 0,
  );
}

final postDetailRepositoryProvider = Provider<PostDetailRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return PostDetailRepository(dio: dio);
});

final postDetailControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    PostDetailController, PostDetailState, String>(
  PostDetailController.new,
);

class PostDetailController
    extends AutoDisposeFamilyAsyncNotifier<PostDetailState, String> {
  bool _likeInFlight = false;
  bool _bookmarkInFlight = false;
  bool _deleteInFlight = false;

  @override
  Future<PostDetailState> build(String postId) async {
    final repo = ref.watch(postDetailRepositoryProvider);

    final post = await repo.getPostDetail(postId: postId);

    String? currentUserId;
    try {
      currentUserId = await repo.getCurrentUserId();
    } catch (_) {
      currentUserId = null;
    }

    try {
      final page = await repo.getCommentsPage(postId: postId);
      return PostDetailState(
        post: post,
        comments: page.items,
        currentUserId: currentUserId,
        commentsNextCursor: page.nextCursor,
        commentsHasMore: page.hasMore,
        isLoadingComments: false,
        isLoadingMoreComments: false,
        commentsError: null,
        loadMoreCommentsError: null,
        isSubmittingComment: false,
        isCommentRateLimited: false,
        commentRateLimitUntil: null,
        uiMessage: null,
        uiMessageNonce: 0,
      );
    } catch (e) {
      return PostDetailState(
        post: post,
        comments: const <Comment>[],
        currentUserId: currentUserId,
        commentsNextCursor: null,
        commentsHasMore: false,
        isLoadingComments: false,
        isLoadingMoreComments: false,
        commentsError: e.toString(),
        loadMoreCommentsError: null,
        isSubmittingComment: false,
        isCommentRateLimited: false,
        commentRateLimitUntil: null,
        uiMessage: null,
        uiMessageNonce: 0,
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> toggleLike() async {
    final current = state.valueOrNull;
    final post = current?.post;
    if (current == null || post == null) return;
    if (_likeInFlight) return;

    _likeInFlight = true;

    final nextLiked = !post.isLiked;
    final optimistic = post.copyWith(
      isLiked: nextLiked,
      likesCount: math.max(0, post.likesCount + (nextLiked ? 1 : -1)),
    );

    state = AsyncData(current.copyWith(post: optimistic));

    try {
      final repo = ref.read(postDetailRepositoryProvider);
      final serverPost = await repo.toggleLike(postId: post.id);
      state = AsyncData(current.copyWith(post: serverPost));
    } catch (_) {
      state = AsyncData(current.copyWith(post: post));
      rethrow;
    } finally {
      _likeInFlight = false;
    }
  }

  Future<void> toggleBookmark() async {
    final current = state.valueOrNull;
    final post = current?.post;
    if (current == null || post == null) return;
    if (_bookmarkInFlight) return;

    _bookmarkInFlight = true;

    final nextBookmarked = !post.isBookmarked;
    final optimistic = post.copyWith(isBookmarked: nextBookmarked);

    state = AsyncData(current.copyWith(post: optimistic));

    try {
      final repo = ref.read(postDetailRepositoryProvider);
      if (nextBookmarked) {
        final serverPost = await repo.addBookmark(postId: post.id);
        state = AsyncData(current.copyWith(post: serverPost));
      } else {
        await repo.removeBookmark(postId: post.id);
      }
    } catch (_) {
      state = AsyncData(current.copyWith(post: post));
      rethrow;
    } finally {
      _bookmarkInFlight = false;
    }
  }

  Future<bool> addComment(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;

    final current = state.valueOrNull;
    final post = current?.post;
    if (current == null || post == null) return false;
    if (current.isSubmittingComment) return false;

    final now = DateTime.now();
    final until = current.commentRateLimitUntil;
    if (until != null && now.isAfter(until)) {
      state = AsyncData(
        current.copyWith(
          isCommentRateLimited: false,
          commentRateLimitUntil: null,
        ),
      );
    }

    final refreshed = state.valueOrNull ?? current;
    if (refreshed.commentRateLimitUntil != null &&
        DateTime.now().isBefore(refreshed.commentRateLimitUntil!)) {
      _pushUiMessage(
        refreshed,
        'You can comment once per hour on this post',
      );
      return false;
    }

    state = AsyncData(refreshed.copyWith(isSubmittingComment: true));

    try {
      final repo = ref.read(postDetailRepositoryProvider);
      final comment = await repo.addComment(postId: post.id, body: trimmed);
      final updated = <Comment>[comment, ...refreshed.comments];
      state = AsyncData(
        refreshed.copyWith(
          comments: updated,
          commentsError: null,
          isSubmittingComment: false,
          isCommentRateLimited: false,
          commentRateLimitUntil: null,
        ),
      );
      return true;
    } on DioException catch (e) {
      final serverMessage = _extractServerError(e) ?? '';

      if (serverMessage.toLowerCase().contains('comment once per hour')) {
        final next = refreshed.copyWith(
          isSubmittingComment: false,
          isCommentRateLimited: true,
          commentRateLimitUntil: DateTime.now().add(const Duration(hours: 1)),
        );
        state = AsyncData(next);
        _pushUiMessage(next, 'You can comment once per hour on this post');
        return false;
      }

      state = AsyncData(refreshed.copyWith(isSubmittingComment: false));
      _pushUiMessage(
        refreshed,
        'Failed to add comment. Please try again.',
      );
      return false;
    } catch (_) {
      state = AsyncData(refreshed.copyWith(isSubmittingComment: false));
      _pushUiMessage(
        refreshed,
        'Failed to add comment. Please try again.',
      );
      return false;
    }
  }

  void consumeUiMessage() {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.uiMessage == null) return;

    state = AsyncData(current.copyWith(uiMessage: null));
  }

  void _pushUiMessage(PostDetailState current, String message) {
    state = AsyncData(
      current.copyWith(
        uiMessage: message,
        uiMessageNonce: current.uiMessageNonce + 1,
      ),
    );
  }

  String? _extractServerError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error']?.toString();
      if (error != null && error.trim().isNotEmpty) return error;
    }
    return e.message;
  }

  Future<void> reloadComments() async {
    final current = state.valueOrNull;
    final post = current?.post;
    if (current == null || post == null) return;
    if (current.isLoadingComments) return;

    state = AsyncData(
      current.copyWith(
        isLoadingComments: true,
        commentsError: null,
        loadMoreCommentsError: null,
      ),
    );

    try {
      final repo = ref.read(postDetailRepositoryProvider);
      final page = await repo.getCommentsPage(postId: post.id);
      state = AsyncData(
        current.copyWith(
          comments: page.items,
          commentsNextCursor: page.nextCursor,
          commentsHasMore: page.hasMore,
          isLoadingComments: false,
          isLoadingMoreComments: false,
          commentsError: null,
          loadMoreCommentsError: null,
        ),
      );
    } catch (e) {
      state = AsyncData(
        current.copyWith(
          isLoadingComments: false,
          commentsError: e.toString(),
        ),
      );
    }
  }

  Future<void> loadMoreComments() async {
    final current = state.valueOrNull;
    final post = current?.post;
    if (current == null || post == null) return;
    if (!current.commentsHasMore) return;
    if (current.isLoadingMoreComments || current.isLoadingComments) return;

    state = AsyncData(
      current.copyWith(
        isLoadingMoreComments: true,
        loadMoreCommentsError: null,
      ),
    );

    try {
      final repo = ref.read(postDetailRepositoryProvider);
      final page = await repo.getCommentsPage(
        postId: post.id,
        cursor: current.commentsNextCursor,
      );

      final merged = <Comment>[...current.comments, ...page.items];
      state = AsyncData(
        current.copyWith(
          comments: merged,
          commentsNextCursor: page.nextCursor,
          commentsHasMore: page.hasMore,
          isLoadingMoreComments: false,
          loadMoreCommentsError: null,
        ),
      );
    } catch (e) {
      state = AsyncData(
        current.copyWith(
          isLoadingMoreComments: false,
          loadMoreCommentsError: e.toString(),
        ),
      );
    }
  }

  Future<void> deleteComment({required String commentId}) async {
    final current = state.valueOrNull;
    final post = current?.post;
    if (current == null || post == null) return;
    if (_deleteInFlight) return;

    final me = current.currentUserId;
    if (me == null || me.isEmpty) return;

    final idx = current.comments.indexWhere((c) => c.id == commentId);
    if (idx == -1) return;

    final comment = current.comments[idx];
    if (comment.authorId != me) return;

    _deleteInFlight = true;

    final optimistic = <Comment>[...current.comments]..removeAt(idx);
    state = AsyncData(current.copyWith(comments: optimistic));

    try {
      final repo = ref.read(postDetailRepositoryProvider);
      await repo.deleteComment(postId: post.id, commentId: commentId);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    } finally {
      _deleteInFlight = false;
    }
  }
}
