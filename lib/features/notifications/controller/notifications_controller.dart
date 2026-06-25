import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client_provider.dart';
import '../models/app_notification.dart';
import '../repository/notifications_repository.dart';

class NotificationsState {
  const NotificationsState({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isRefreshing,
  });

  final List<AppNotification> items;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isRefreshing;

  NotificationsState copyWith({
    List<AppNotification>? items,
    String? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  static const empty = NotificationsState(
    items: <AppNotification>[],
    nextCursor: null,
    hasMore: false,
    isLoadingMore: false,
    isRefreshing: false,
  );
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return NotificationsRepository(dio: dio);
});

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final asyncState = ref.watch(notificationsControllerProvider);
  final items = asyncState.valueOrNull?.items;
  if (items == null) return 0;
  return items.where((n) => !n.isRead).length;
});

class NotificationsController extends AsyncNotifier<NotificationsState> {
  final Set<String> _markReadInFlight = <String>{};

  @override
  Future<NotificationsState> build() async {
    final repo = ref.watch(notificationsRepositoryProvider);
    final page = await repo.getNotifications(cursor: null);

    return NotificationsState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      isLoadingMore: false,
      isRefreshing: false,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> refreshFirstPage({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }

    if (current.isRefreshing) return;
    if (current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isRefreshing: true));

    try {
      final repo = ref.read(notificationsRepositoryProvider);
      final page = await repo.getNotifications(cursor: null, limit: limit);
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

  Future<void> fetchNext({int limit = 20}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isRefreshing) return;
    if (!current.hasMore) return;

    final cursor = current.nextCursor;
    if (cursor == null || cursor.isEmpty) return;

    if (current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final repo = ref.read(notificationsRepositoryProvider);

    final result = await AsyncValue.guard(() async {
      final page = await repo.getNotifications(cursor: cursor, limit: limit);
      return current.copyWith(
        items: <AppNotification>[...current.items, ...page.items],
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

  Future<void> markRead({required String notificationId}) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final idx = current.items.indexWhere((n) => n.id == notificationId);
    if (idx == -1) return;

    final before = current.items[idx];

    if (_markReadInFlight.contains(notificationId)) return;
    _markReadInFlight.add(notificationId);

    // Optimistically remove the notification from the list immediately.
    final optimisticItems = List<AppNotification>.of(current.items)
      ..removeAt(idx);
    state = AsyncData(current.copyWith(items: optimisticItems));

    // Already read - no API call needed, just remove from list.
    if (before.isRead) {
      _markReadInFlight.remove(notificationId);
      return;
    }

    try {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markRead(notificationId: notificationId);
      // Item already removed; nothing else to update.
    } catch (_) {
      // Rollback: restore the original list.
      state = AsyncData(current);
      rethrow;
    } finally {
      _markReadInFlight.remove(notificationId);
    }
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null) return;

    // Check if there are any unread notifications
    final hasUnread = current.items.any((n) => !n.isRead);
    if (!hasUnread) return;

    // Optimistically mark all as read using copyWith
    final optimisticItems = current.items.map((n) => n.copyWith(isRead: true)).toList();

    state = AsyncData(current.copyWith(items: optimisticItems));

    try {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markAllRead();
    } catch (_) {
      // Rollback on error
      state = AsyncData(current);
    }
  }
}
