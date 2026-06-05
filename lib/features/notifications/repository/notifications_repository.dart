import 'package:dio/dio.dart';

import '../models/app_notification.dart';

class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<AppNotification> items;
  final String? nextCursor;
  final bool hasMore;
}

class NotificationsRepository {
  NotificationsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<NotificationsPage> getNotifications({
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/notifications',
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
        .map(AppNotification.fromJson)
        .toList(growable: false);

    return NotificationsPage(
      items: items,
      nextCursor: (data['next_cursor'] as Object?)?.toString(),
      hasMore: (data['has_more'] as Object?) == true,
    );
  }

  Future<AppNotification> markRead({required String notificationId}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/notifications/$notificationId/read',
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return AppNotification.fromJson(data);
  }

  Future<int> markAllRead() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/notifications/read-all',
    );

    final body = response.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? (body['data'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    return (data['updated'] as num?)?.toInt() ?? 0;
  }
}
