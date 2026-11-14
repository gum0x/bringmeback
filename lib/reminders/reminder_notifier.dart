import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'routine_reminders.dart';

/// Shows and schedules the routine reminders' notifications.
abstract class ReminderNotifier {
  /// Whether the system keeps scheduled notifications and shows them with the app closed. Where it
  /// doesn't, the app shows each reminder itself while it is open.
  bool get schedulesInBackground;

  /// Gets ready to show notifications, ahead of the first one. Asks nothing.
  Future<void> prepare();

  /// Asks to show notifications, if this device asks. On the web this must follow a tap.
  Future<bool> requestPermission();

  /// Replaces every scheduled routine reminder with [reminders].
  Future<void> replaceScheduled(List<ScheduledReminder> reminders);

  /// Shows [reminder] now.
  Future<void> show(RoutineReminder reminder);
}

/// [ReminderNotifier] on the system's notifications, through flutter_local_notifications.
///
/// - Android, iOS and macOS keep scheduled notifications, so reminders ring with the app closed.
/// - Windows schedules them too, but an app that is not packaged as MSIX can't cancel them, so a
///   changed time would leave the old one ringing: there the app shows them itself while open.
/// - Linux has no scheduler, and browsers can't schedule notifications: same, while the app (or
///   its tab) is open.
class SystemReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('routine', 'Routine reminders',
        channelDescription: 'Morning and afternoon reminders to plan and close the day.'),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  @override
  bool get schedulesInBackground =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Started on first use, so a device with the reminders off never sets up notifications (on the
  /// web, that registers a service worker).
  Future<bool> _init() => _ready ??= () async {
        try {
          return await _plugin.initialize(
                settings: const InitializationSettings(
                  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
                  // Asked when a reminder is turned on, not when the app starts.
                  iOS: DarwinInitializationSettings(
                      requestAlertPermission: false,
                      requestBadgePermission: false,
                      requestSoundPermission: false),
                  macOS: DarwinInitializationSettings(
                      requestAlertPermission: false,
                      requestBadgePermission: false,
                      requestSoundPermission: false),
                  linux: LinuxInitializationSettings(defaultActionName: 'Open bringmeback'),
                  windows: WindowsInitializationSettings(
                      appName: 'bringmeback',
                      appUserModelId: 'bringmeback.bringmeback',
                      guid: '6f1d2a8e-3c4b-4f5a-9e7d-1b2c3d4e5f60'),
                ),
              ) ??
              false;
        } on Object catch (e) {
          debugPrint('Notifications are not available: $e');
          return false;
        }
      }();

  @override
  Future<void> prepare() => _init();

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      if (kIsWeb) {
        return await _plugin
                .resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin
                  .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                  ?.requestNotificationsPermission() ??
              false;
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, sound: true) ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, sound: true) ??
              false;
        default:
          // Linux and Windows don't ask.
          return true;
      }
    } on Object catch (e) {
      debugPrint('Could not ask to show notifications: $e');
      return false;
    }
  }

  @override
  Future<void> replaceScheduled(List<ScheduledReminder> reminders) async {
    if (!schedulesInBackground || !await _init()) return;
    for (final r in RoutineReminder.values) {
      for (var day = 0; day < RoutineSettings.daysAhead; day++) {
        await _plugin.cancel(id: r.idBase + day);
      }
    }
    for (final s in reminders) {
      // Scheduled at the instant, in UTC: the local wall-clock time was already worked out, summer
      // time included, so no time zone database is needed.
      await _plugin.zonedSchedule(
        id: s.id,
        title: s.reminder.title,
        body: s.reminder.body,
        scheduledDate: tz.TZDateTime.from(s.at, tz.UTC),
        notificationDetails: _details,
        // A routine reminder needn't be to the second, and inexact alarms need no extra permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> show(RoutineReminder reminder) async {
    if (!await _init()) return;
    // On the web the plugin's service worker shows the notification. Registering it returns before
    // it is active, so a first notification soon after can find it still installing: wait for it.
    for (var attempt = 1;; attempt++) {
      try {
        await _plugin.show(
            id: reminder.idBase,
            title: reminder.title,
            body: reminder.body,
            notificationDetails: _details);
        return;
      } on StateError catch (e) {
        if (!kIsWeb || attempt == 10) {
          debugPrint('Could not show the reminder: $e');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Registering again hands back the same worker, active by now.
        _ready = null;
        if (!await _init()) return;
      } on Object catch (e) {
        // On the web, permission may have been taken back since.
        debugPrint('Could not show the reminder: $e');
        return;
      }
    }
  }
}
