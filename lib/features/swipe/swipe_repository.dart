import 'package:dio/dio.dart';

import '../feed/models/post.dart';

class SwipeDeckPage {
  const SwipeDeckPage({required this.stories, required this.count});

  final List<Post> stories;
  final int count;
}

class SwipeRepository {
  SwipeRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<SwipeDeckPage> getDeck({int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/deck',
      queryParameters: <String, dynamic>{'limit': limit},
    );

    final body = response.data ?? const <String, dynamic>{};

    // The deck endpoint returns { stories: [...], count: N } at the top level
    final storiesJson = (body['stories'] is List)
        ? (body['stories'] as List)
        : const <dynamic>[];

    final stories = storiesJson
        .whereType<Map<String, dynamic>>()
        .map(Post.fromJson)
        .toList(growable: false);

    final count = (body['count'] is num) ? (body['count'] as num).toInt() : stories.length;

    return SwipeDeckPage(stories: stories, count: count);
  }

  Future<void> recordSwipe({
    required String storyId,
    required String direction,
  }) async {
    await _dio.post<void>(
      '/api/v1/swipe',
      data: <String, dynamic>{
        'story_id': storyId,
        'direction': direction,
      },
    );
  }

  /// Returns the story_id that was undone, or null if nothing to undo.
  Future<String?> undoSwipe() async {
    final response = await _dio.delete<Map<String, dynamic>>('/api/v1/swipe/undo');
    final body = response.data ?? const <String, dynamic>{};
    return body['undone_story_id']?.toString();
  }

  Future<void> clearAllSwipes() async {
    await _dio.post<void>('/api/v1/swipe/clear');
  }

  Future<List<Post>> getActiveAds() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api/v1/ads/active');
      final list = response.data ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((json) => Post(
                id: (json['id'] ?? '').toString(),
                authorId: '',
                authorName: 'Sponsored',
                title: (json['title'] ?? '').toString(),
                body: (json['body'] ?? '').toString(),
                tags: const ['Sponsored'],
                readTimeMinutes: 0,
                likesCount: 0,
                isLiked: false,
                isBookmarked: false,
                isArchived: false,
                moderationStatus: 'approved',
                createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
                updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
                isAd: true,
                adImageUrl: null,
                adTargetUrl: json['target_url']?.toString(),
              ))
          .toList(growable: false);
    } catch (_) {
      return const <Post>[];
    }
  }

  Future<void> recordAdImpression(String adId) async {
    try {
      await _dio.post<void>('/api/v1/ads/$adId/impression');
    } catch (_) {}
  }

  Future<void> recordAdClick(String adId) async {
    try {
      await _dio.post<void>('/api/v1/ads/$adId/click');
    } catch (_) {}
  }
}
