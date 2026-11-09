import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../bloc/tasks_bloc.dart';
import 'alert_schedule.dart';

/// Shows alerts while the app isn't running them itself.
abstract class AlertScheduler {
  /// Asks for permission to notify. Called once a timer runs, so the request makes sense.
  Future<void> requestPermission();

  /// Replaces any scheduled alerts with `alerts`, silent when `muted`.
  Future<void> schedule(List<ScheduledAlert> alerts, {required bool muted});

  /// Cancels every scheduled alert and clears shown ones.
  Future<void> cancel();
}

/// Hands the alerts to scheduled notifications while the app is in the background, where its own
/// timer may not run.
///
/// Going to the background schedules a notification for each alert the running countdown will
/// raise, and keeps the bloc from raising them too. While in the background, a change synced from
/// another device that moves those alerts reschedules them. Coming back cancels them and the
/// bloc's own alerts take over. Only Android and iOS stop the app's timer in the background, so
/// only they get a scheduler.
class BackgroundAlerts with WidgetsBindingObserver {
  final TasksBloc _bloc;
  final AlertScheduler _scheduler;
  final int Function() _now;
  StreamSubscription<TasksState>? _states;
  List<ScheduledAlert>? _scheduled;
  bool _scheduledMuted = false;
  bool _asked = false;
  bool _background = false;
  // Scheduling calls run one at a time, in order.
  Future<void> _queue = Future.value();

  BackgroundAlerts(this._bloc, this._scheduler, {int Function()? now}) : _now = now ?? nowSeconds {
    _states = _bloc.stream.listen(_changed);
  }

  /// A scheduler for this platform, or null where the app's own timer keeps running.
  static AlertScheduler? platformScheduler() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => LocalNotificationsScheduler(),
      _ => null,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        if (_background) return;
        _background = true;
        _bloc.inBackground = true;
        _changed(_bloc.state);
      case AppLifecycleState.resumed:
        if (!_background) return;
        _background = false;
        _bloc.inBackground = false;
        _scheduled = null;
        _run(_scheduler.cancel);
      case AppLifecycleState.inactive || AppLifecycleState.detached:
    }
  }

  void _changed(TasksState state) {
    if (!_background) {
      if (!_asked && state.tasks.any((t) => t.running)) {
        _asked = true;
        _run(_scheduler.requestPermission);
      }
      return;
    }
    // The bloc emits every second; reschedule only when the alerts themselves change.
    final alerts = alertsAfter(state.tasks, _now());
    if (_scheduledMuted == state.muted && listEquals(alerts, _scheduled)) return;
    _scheduled = alerts;
    _scheduledMuted = state.muted;
    _run(() => _scheduler.schedule(alerts, muted: state.muted));
  }

  void _run(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((Object e) {
      debugPrint('Background alerts: $e');
    });
  }

  Future<void> close() async {
    await _states?.cancel();
    await _queue;
  }
}

/// [AlertScheduler] with flutter_local_notifications.
///
/// On Android the alarms are exact where the user allows it (Settings, Alarms & reminders), and
/// otherwise inexact, which Android may hold back by some minutes while the phone sleeps.
class LocalNotificationsScheduler implements AlertScheduler {
  static const _channel = 'alerts';
  static const _silentChannel = 'silent-alerts';

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialized;

  Future<void> _init() => _initialized ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Asked for in requestPermission, once a timer runs.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> requestPermission() async {
    await _init();
    await _android?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
  }

  @override
  Future<void> schedule(List<ScheduledAlert> alerts, {required bool muted}) async {
    await _init();
    await _plugin.cancelAll();
    if (alerts.isEmpty) return;
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    final details = NotificationDetails(
      android: muted
          ? const AndroidNotificationDetails(_silentChannel, 'Silent timer alerts',
              channelDescription: 'Timer alerts while sounds are muted',
              importance: Importance.high,
              priority: Priority.high,
              playSound: false,
              enableVibration: false,
              category: AndroidNotificationCategory.alarm)
          : const AndroidNotificationDetails(_channel, 'Timer alerts',
              channelDescription: 'When a countdown runs out, and every 30 minutes',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.alarm),
      iOS: DarwinNotificationDetails(presentSound: !muted),
    );
    for (final (i, alert) in alerts.indexed) {
      final (title, body) = _text(alert);
      await _plugin.zonedSchedule(
        id: i,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, alert.at * 1000),
        notificationDetails: details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static (String, String?) _text(ScheduledAlert alert) => switch (alert.kind) {
        AlertKind.timeUp => ("Time's up", alert.taskName.isEmpty ? null : alert.taskName),
        AlertKind.reminder => (
            'Another 30 minutes',
            alert.taskName.isEmpty ? null : alert.taskName,
          ),
      };

  @override
  Future<void> cancel() async {
    await _init();
    await _plugin.cancelAll();
  }
}
