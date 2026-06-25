import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Schedules the daily "Question of the Day" reminder as a *local* on-device
/// notification - no FCM / server push. Android-only: on web (incl. the iOS
/// web-clip / PWA) and other platforms every method is a safe no-op.
class LocalNotificationsService {
  LocalNotificationsService._();
  static final LocalNotificationsService instance = LocalNotificationsService._();

  static const _prefEnabled = 'qotd_reminder_enabled';
  static const _prefHour = 'qotd_reminder_hour';
  static const _prefMinute = 'qotd_reminder_minute';
  static const int _reminderId = 1001;
  static const String _payload = '/qotd';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// True only where local notifications are actually supported.
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Default reminder time: 7:00 PM.
  static const int defaultHour = 19;
  static const int defaultMinute = 0;

  Future<void> init({void Function(String? payload)? onTap}) async {
    if (!isSupported || _initialized) return;

    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) => onTap?.call(resp.payload),
    );
    _initialized = true;

    // If the app was launched by tapping the notification while terminated.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onTap?.call(launch!.notificationResponse?.payload);
    }

    // Re-arm any previously-enabled reminder (schedules don't survive reinstall).
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefEnabled) ?? false) {
      await scheduleDaily(
        hour: prefs.getInt(_prefHour) ?? defaultHour,
        minute: prefs.getInt(_prefMinute) ?? defaultMinute,
      );
    }
  }

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  Future<(int, int)> reminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_prefHour) ?? defaultHour, prefs.getInt(_prefMinute) ?? defaultMinute);
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> scheduleDaily({required int hour, required int minute}) async {
    if (!isSupported) return;
    if (!_initialized) await init();

    await requestPermission();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
    await prefs.setInt(_prefHour, hour);
    await prefs.setInt(_prefMinute, minute);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'qotd_daily',
        'Daily Question Reminder',
        channelDescription: 'A daily nudge to answer the Question of the Day.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    await _plugin.zonedSchedule(
      _reminderId,
      "Today's question is waiting 👀",
      'Tap to answer the Question of the Day on PaperStock.',
      _nextInstanceOf(hour, minute),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: _payload,
    );
  }

  Future<void> cancelReminder() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
    await _plugin.cancel(_reminderId);
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
