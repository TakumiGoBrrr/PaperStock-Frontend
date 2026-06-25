import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/controller/notifications_controller.dart';

/// A notification bell icon button that automatically shows a badge
/// when there are unread notifications. Can be dropped anywhere in the
/// widget tree - it manages its own Riverpod access internally.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsCountProvider);

    return Badge.count(
      count: unread,
      isLabelVisible: unread > 0,
      offset: const Offset(-4, 4),
      child: IconButton(
        icon: const Icon(Icons.notifications),
        tooltip: 'Notifications',
        onPressed: () => context.push('/notifications'),
      ),
    );
  }
}
