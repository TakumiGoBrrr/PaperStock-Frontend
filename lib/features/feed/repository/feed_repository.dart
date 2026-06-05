import 'package:dio/dio.dart';

import '../models/post.dart';

class TrashItem {
  const TrashItem({
    required this.id,
    required this.title,
    required this.tags,
    required this.createdAt,
    required this.deletedAt,
  });

  final String id;
  final String title;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime deletedAt;

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      tags: (json['tags'] is List)
          ? (json['tags'] as List)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deletedAt: DateTime.tryParse((json['deleted_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class TrashPage {
  const TrashPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<TrashItem> items;
  final String? nextCursor;
  final bool hasMore;
}

enum FeedType {
  forYou('foryou');

  const FeedType(this.queryValue);

  final String queryValue;
}

class FeedPage {
  const FeedPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Post> items;
  final String? nextCursor;
  final bool hasMore;
}

class FeedRepository {
  FeedRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<FeedPage> getFeed({
    required FeedType type,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/posts',
      queryParameters: <String, dynamic>{
        'type': type.queryValue,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
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
        .map(Post.fromJson)
        .toList(growable: false);

    return FeedPage(
      items: items,
      nextCursor: data['next_cursor']?.toString(),
      hasMore: data['has_more'] == true,
    );
  }

  Future<Post> createPost({
    required String title,
    required String body,
    required List<String> tags,
    required String postType,
    required String? storyType,
    String? parentId,
    bool isNsfw = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/posts',
      data: <String, dynamic>{
        'title': title,
        'body': body,
        'tags': tags,
        'post_type': postType,
        'story_type': storyType,
        'is_nsfw': isNsfw,
        if (parentId != null) 'parent_id': parentId,
      },
    );

    final bodyJson = response.data ?? const <String, dynamic>{};
    final data = (bodyJson['data'] is Map<String, dynamic>)
        ? (bodyJson['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return Post.fromJson(data);
  }

  Future<Post> updatePost({
    required String postId,
    String? title,
    String? body,
    List<String>? tags,
    String? postType,
    String? storyType,
    bool? isNsfw,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/posts/$postId',
      data: <String, dynamic>{
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        if (tags != null) 'tags': tags,
        if (postType != null) 'post_type': postType,
        if (storyType != null) 'story_type': storyType,
        if (isNsfw != null) 'is_nsfw': isNsfw,
      },
    );
    return _parsePostFromEnvelope(response.data);
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

  Future<void> softDeletePost({required String postId}) async {
    await _dio.delete<void>('/api/v1/posts/$postId');
  }

  Future<void> archivePost({required String postId}) async {
    await _dio.post<void>('/api/v1/posts/$postId/archive');
  }

  Future<void> unarchivePost({required String postId}) async {
    await _dio.post<void>('/api/v1/posts/$postId/unarchive');
  }

  Future<TrashPage> getTrash({String? cursor, int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/posts/trash',
      queryParameters: <String, dynamic>{
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
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
        .map(TrashItem.fromJson)
        .toList(growable: false);

    return TrashPage(
      items: items,
      nextCursor: data['next_cursor']?.toString(),
      hasMore: data['has_more'] == true,
    );
  }

  Future<void> restorePost({required String postId}) async {
    await _dio.post<void>('/api/v1/posts/$postId/restore');
  }

  Future<void> permanentlyDeletePost({required String postId}) async {
    await _dio.delete<void>('/api/v1/posts/$postId/permanent');
  }

  Post _parsePostFromEnvelope(Map<String, dynamic>? envelope) {
    final body = envelope ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    // Some endpoints return PostOut directly under data.
    if (data.containsKey('id')) {
      return Post.fromJson(data);
    }

    final postJson = (data['post'] is Map<String, dynamic>)
        ? (data['post'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    return Post.fromJson(postJson);
  }
}
