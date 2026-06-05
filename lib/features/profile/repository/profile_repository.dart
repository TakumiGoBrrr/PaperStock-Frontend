import 'package:dio/dio.dart';

import '../../feed/models/post.dart';
import '../models/user_profile.dart';

class PostsPage {
  const PostsPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Post> items;
  final String? nextCursor;
  final bool hasMore;
}

class ProfileRepository {
  ProfileRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

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

  Future<UserProfile> getUserProfile({required String userId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/users/$userId',
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return UserProfile.fromJson(data, fallbackId: userId);
  }

  Future<bool> follow({required String userId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/users/$userId/follow',
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return data['is_following'] == true;
  }

  Future<bool> unfollow({required String userId}) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/api/v1/users/$userId/follow',
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return data['is_following'] == true;
  }

  Future<PostsPage> getUserPosts({
    required String userId,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/users/$userId/posts',
      queryParameters: <String, dynamic>{
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

    return PostsPage(
      items: items,
      nextCursor: (data['next_cursor'] as Object?)?.toString(),
      hasMore: (data['has_more'] as Object?) == true,
    );
  }

  Future<PostsPage> getMyBookmarks({
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/bookmarks',
      queryParameters: <String, dynamic>{
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

    return PostsPage(
      items: items,
      nextCursor: (data['next_cursor'] as Object?)?.toString(),
      hasMore: (data['has_more'] as Object?) == true,
    );
  }
}
