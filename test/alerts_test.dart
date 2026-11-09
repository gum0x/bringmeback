import 'package:bringmeback/alerts/alert_schedule.dart';
import 'package:bringmeback/alerts/background_alerts.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskState running(String name, {required int length, required int startedAt}) => TaskState(
    name: name,
    id: ValueKey(name),
    timerLengthSeconds: length,
    timerStartAt: startedAt,
    entries: [TimeEntry(start: startedAt)]);

/// The alerts the bloc's one-second tick raises from `now` on, for `seconds` seconds.
List<ScheduledAlert> ticked(TaskState task, int now, int seconds) => [
      for (var t = now + 1; t <= now + seconds; t++)
        if (alertBetween(task.remainingSecondsAt(t - 1), task.remainingSecondsAt(t))
            case final kind?)
          ScheduledAlert(t, kind, task.name),
    ];

class FakeScheduler implements AlertScheduler {
  final calls = <String>[];
  List<ScheduledAlert> alerts = [];
  bool muted = false;

  @override
  Future<void> requestPermission() async => calls.add('permission');

  @override
  Future<void> schedule(List<ScheduledAlert> alerts, {required bool muted}) async {
    calls.add('schedule');
    this.alerts = alerts;
    this.muted = muted;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    alerts = [];
  }
}

void main() {
  test('alertBetween: time up once, reminders every 30 minutes, none right after time up', () {
    expect(alertBetween(1, 0), AlertKind.timeUp);
    expect(alertBetween(5, -3), AlertKind.timeUp);
    expect(alertBetween(0, -1), isNull);
    expect(alertBetween(1800, 1799), AlertKind.reminder);
    expect(alertBetween(1801, 1800), isNull);
    expect(alertBetween(-1799, -1800), isNull);
    expect(alertBetween(-1800, -1801), AlertKind.reminder);
    expect(alertBetween(10, 10), isNull);
  });

  test('alertsAfter matches what the tick would raise', () {
    const now = 1000000;
    // A 70-minute countdown started 5 minutes ago: reminders at 30 and 0 minutes... and overtime.
    final task = running('write', length: 70 * 60, startedAt: now - 5 * 60);
    const span = 3 * 60 * 60;
    expect(alertsAfter([task], now, horizon: span, max: 100), ticked(task, now, span));
    expect(alertsAfter([task], now, horizon: span, max: 100).map((a) => a.kind).toList(), [
      AlertKind.reminder,
      AlertKind.reminder,
      AlertKind.timeUp,
      AlertKind.reminder,
      AlertKind.reminder,
      AlertKind.reminder,
    ]);
  });

  test('alertsAfter: overtime, stopped tasks, the limit and the horizon', () {
    const now = 1000000;
    final over = running('over', length: 60, startedAt: now - 1000);
    expect(alertsAfter([over], now, horizon: 4 * 3600, max: 100), ticked(over, now, 4 * 3600));
    final stopped = TaskState(
        name: 'stopped',
        id: const ValueKey('stopped'),
        timerLengthSeconds: 60,
        timerStartAt: now - 30,
        entries: [TimeEntry(start: now - 30, end: now - 20)]);
    expect(alertsAfter([stopped], now), isEmpty);
    expect(alertsAfter([over], now, max: 3), hasLength(3));
    expect(alertsAfter([over], now).last.at - now, lessThanOrEqualTo(24 * 3600));
  });

  group('BackgroundAlerts', () {
    late TasksBloc bloc;
    late FakeScheduler scheduler;
    late BackgroundAlerts alerts;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // The bloc's audio player; these tests play nothing.
      for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
      }
      SharedPreferences.setMockInitialValues({});
      bloc = TasksBloc();
      scheduler = FakeScheduler();
      alerts = BackgroundAlerts(bloc, scheduler);
      await bloc.document;
    });

    tearDown(() async {
      await alerts.close();
      await bloc.close();
    });

    test('asks once a timer runs, schedules in the background and cancels on return', () async {
      bloc.add(AddTaskOnTopEvent(name: '', id: const ValueKey('a')));
      bloc.add(UpdateTaskNameEvent(id: const ValueKey('a'), newName: 'write'));
      await pumpEventQueue();
      expect(scheduler.calls, ['permission']);

      alerts.didChangeAppLifecycleState(AppLifecycleState.hidden);
      alerts.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(bloc.inBackground, isTrue);
      expect(scheduler.calls, ['permission', 'schedule']);
      expect(scheduler.alerts.first.kind, AlertKind.timeUp);
      expect(scheduler.alerts.first.taskName, 'write');

      // Ticks don't move the alerts, so nothing is rescheduled.
      bloc.add(UpdateTimerEvent());
      await pumpEventQueue();
      expect(scheduler.calls, ['permission', 'schedule']);

      // A change that moves them, like one synced from another device, does.
      bloc.add(StopTimerEvent(index: 0));
      await pumpEventQueue();
      expect(scheduler.calls, ['permission', 'schedule', 'schedule']);
      expect(scheduler.alerts, isEmpty);

      alerts.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(bloc.inBackground, isFalse);
      expect(scheduler.calls.last, 'cancel');
    });

    test('an alert passed in the background is not raised again on return', () async {
      final timeUp = <String>[];
      bloc.timeUp.listen(timeUp.add);
      bloc.add(AddTaskOnTopEvent(name: '', id: const ValueKey('a')));
      bloc.add(UpdateTaskTimerEvent(index: 0, seconds: 1));
      bloc.add(UpdateTimerEvent());
      await pumpEventQueue();

      alerts.didChangeAppLifecycleState(AppLifecycleState.paused);
      // The phone stops the app's timer while it is away.
      bloc.tick?.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      alerts.didChangeAppLifecycleState(AppLifecycleState.resumed);
      bloc.add(UpdateTimerEvent());
      await pumpEventQueue();
      expect(timeUp, isEmpty);
    });
  });
}
