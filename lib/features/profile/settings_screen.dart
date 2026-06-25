import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/notifications/local_notifications_service.dart';
import '../../core/storage/opened_posts_store.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/widgets/notification_bell_button.dart';
import '../auth/controller/auth_controller.dart';
import '../feed/controller/feed_controller.dart';
import '../notifications/controller/notifications_controller.dart';
import 'controller/profile_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _clearUserStateAndGoToLogin(
      BuildContext context, WidgetRef ref) async {
    // Clear all user-scoped state so nothing leaks across sessions.
    ref.invalidate(authControllerProvider);
    ref.invalidate(feedControllerProvider);
    ref.invalidate(profileControllerProvider);
    ref.invalidate(currentUserIdProvider);
    ref.invalidate(notificationsControllerProvider);
    ref.invalidate(unreadNotificationsCountProvider);

    // Clear local caches (keep theme).
    final prefs = await SharedPreferences.getInstance();
    final themeMode = prefs.getString('theme_mode');
    await prefs.clear();
    if (themeMode != null) {
      await prefs.setString('theme_mode', themeMode);
    }
    await OpenedPostsStore.clear();

    if (!context.mounted) return;
    context.go('/login');
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('You will need to log in again to continue.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    await ref.read(authControllerProvider.notifier).logout();
    if (!context.mounted) return;
    await _clearUserStateAndGoToLogin(context, ref);
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final shouldSendOtp = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'A verification code will be sent to your email. Enter this code to permanently delete your account and content.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: const Text('Send Code'),
            ),
          ],
        );
      },
    );

    if (shouldSendOtp != true) return;

    // Call API to send OTP
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.post<void>('/api/v1/users/me/delete-otp');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to send verification code. Please try again.')),
      );
      return;
    }

    if (!context.mounted) return;

    // Show Dialog to input OTP
    final otpController = TextEditingController();
    final otpSubmitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Enter Verification Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please enter the 6-digit code sent to your email to confirm deletion.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Verification Code',
                  hintText: '000000',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
              ),
              child: const Text('Delete Account'),
            ),
          ],
        );
      },
    );

    if (otpSubmitted != true || otpController.text.trim().isEmpty) return;

    try {
      final dio = ref.read(apiClientProvider).dio;
      final otp = otpController.text.trim();
      await dio.delete<void>('/api/v1/users/me', queryParameters: {'otp': otp});
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Invalid or expired verification code. Please try again.')),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account permanently deleted.')),
    );

    await ref.read(authControllerProvider.notifier).logout();
    if (!context.mounted) return;
    await _clearUserStateAndGoToLogin(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode =
        ref.watch(themeControllerProvider).valueOrNull ?? ThemeMode.dark;
    final isDarkMode = themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: GlassAppBar(
        title: Text(
          'PaperStock',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        left: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        right: const NotificationBellButton(),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: <Widget>[
                const SizedBox(height: 6),
                Text(
                  'Settings',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Card.filled(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        title: const Text('Dark mode'),
                        trailing: Switch(
                          value: isDarkMode,
                          onChanged: (value) => ref
                              .read(themeControllerProvider.notifier)
                              .setDarkMode(value),
                        ),
                      ),
                      if (LocalNotificationsService.instance.isSupported) ...<Widget>[
                        const Divider(height: 1),
                        const _DailyReminderTile(),
                      ],
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Swipe Tutorial'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/swipe-demo'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Recycle Bin'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/recycle-bin'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Logout'),
                        trailing: const Icon(Icons.logout),
                        onTap: () => _logout(context, ref),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          'Delete account',
                          style: TextStyle(
                            color: isDarkMode 
                                ? Colors.red[400] 
                                : colorScheme.error,
                          ),
                        ),
                        trailing: Icon(
                          Icons.delete_forever,
                          color: isDarkMode 
                              ? Colors.red[400] 
                              : colorScheme.error,
                        ),
                        onTap: () => _deleteAccount(context, ref),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Android-only toggle + time picker for the daily Question-of-the-Day reminder.
class _DailyReminderTile extends ConsumerStatefulWidget {
  const _DailyReminderTile();

  @override
  ConsumerState<_DailyReminderTile> createState() => _DailyReminderTileState();
}

class _DailyReminderTileState extends ConsumerState<_DailyReminderTile> {
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(
    hour: LocalNotificationsService.defaultHour,
    minute: LocalNotificationsService.defaultMinute,
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = LocalNotificationsService.instance;
    final enabled = await svc.isEnabled();
    final (h, m) = await svc.reminderTime();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _time = TimeOfDay(hour: h, minute: m);
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    final svc = LocalNotificationsService.instance;
    if (value) {
      final granted = await svc.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enable notifications in system settings to use reminders.')),
          );
        }
        return;
      }
      await svc.scheduleDaily(hour: _time.hour, minute: _time.minute);
    } else {
      await svc.cancelReminder();
    }
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
    if (_enabled) {
      await LocalNotificationsService.instance
          .scheduleDaily(hour: picked.hour, minute: picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(title: Text('Daily question reminder'));
    }
    return Column(
      children: <Widget>[
        ListTile(
          title: const Text('Daily question reminder'),
          subtitle: const Text('A daily nudge to answer the Question of the Day'),
          trailing: Switch(value: _enabled, onChanged: _toggle),
        ),
        if (_enabled)
          ListTile(
            dense: true,
            title: const Text('Reminder time'),
            trailing: Text(_time.format(context)),
            onTap: _pickTime,
          ),
      ],
    );
  }
}
