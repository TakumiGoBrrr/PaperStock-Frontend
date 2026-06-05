import 'package:dio/dio.dart';

import '../models/comment.dart';
import '../models/post.dart';

class PostUnavailableException implements Exception {
  const PostUnavailableException({
    required this.authorId,
    required this.authorName,
    required this.reason,
  });

  final String authorId;
  final String authorName;
  final String reason;
}

class CommentsPage {
  const CommentsPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Comment> items;
  final String? nextCursor;
  final bool hasMore;
}

class PostDetailRepository {
  PostDetailRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<Post?> getPostDetail({required String postId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/posts/$postId',
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : null;

      if (data == null || data.isEmpty) return null;
      return Post.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail'];
        if (detail is Map<String, dynamic>) {
          throw PostUnavailableException(
            authorId: (detail['author_id'] as Object?)?.toString() ?? '',
            authorName: (detail['author_name'] as Object?)?.toString() ?? '',
            reason: (detail['reason'] as Object?)?.toString() ?? 'deleted',
          );
        }
      }
      rethrow;
    }
  }

  Future<CommentsPage> getCommentsPage({
    required String postId,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/posts/$postId/comments',
      queryParameters: <String, dynamic>{
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    final itemsJson =
        (data['items'] is List) ? (data['items'] as List) : const <dynamic>[];

    final items = itemsJson
        .whereType<Map<String, dynamic>>()
        .map(Comment.fromJson)
        .toList(growable: false);

    return CommentsPage(
      items: items,
      nextCursor: (data['next_cursor'] as Object?)?.toString(),
      hasMore: (data['has_more'] as Object?) == true,
    );
  }

  Future<Comment> addComment(
      {required String postId, required String body}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/posts/$postId/comments',
      data: <String, dynamic>{'body': body},
    );

    final envelope = response.data ?? const <String, dynamic>{};
    final data = (envelope['data'] is Map<String, dynamic>)
        ? (envelope['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return Comment.fromJson(data);
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    await _dio.delete<void>(
      '/api/v1/posts/$postId/comments/$commentId',
    );
  }

  Future<String?> getCurrentUserId() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/users/me');

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    final id = (data['id'] as Object?)?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<Post> toggleLike({required String postId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/posts/$postId/like',
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    final postJson = (data['post'] is Map<String, dynamic>)
        ? (data['post'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return Post.fromJson(postJson);
  }

  Future<Post> addBookmark({required String postId}) async {
    // Preferred (per frontend contract): POST /bookmarks/{id}
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/bookmarks/$postId',
      );
      return _parsePostFromEnvelope(response.data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != 404) rethrow;
    }

    // Fallback to current backend route: POST /posts/{id}/bookmark
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/posts/$postId/bookmark',
    );
    return _parsePostFromEnvelope(response.data);
  }

  Future<void> removeBookmark({required String postId}) async {
    // Preferred (per frontend contract): DELETE /bookmarks/{id}
    try {
      await _dio.delete<void>('/api/v1/bookmarks/$postId');
      return;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != 404) rethrow;
    }

    // Fallback to current backend route: DELETE /posts/{id}/bookmark
    await _dio.delete<void>('/api/v1/posts/$postId/bookmark');
  }

  Post _parsePostFromEnvelope(Map<String, dynamic>? envelope) {
    final body = envelope ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    if (data.containsKey('id')) {
      return Post.fromJson(data);
    }

    final postJson = (data['post'] is Map<String, dynamic>)
        ? (data['post'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return Post.fromJson(postJson);
  }
}
