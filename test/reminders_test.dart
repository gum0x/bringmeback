import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/reminders/reminder_notifier.dart';
import 'package:bringmeback/reminders/reminders_cubit.dart';
import 'package:bringmeback/reminders/routine_reminders.dart';
import 'package:bringmeback/settings/settings_page.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the cubit asks of the system's notifications.
class FakeNotifier implements ReminderNotifier {
  @override
  final bool schedulesInBackground;
  bool allow;

  int permissionRequests = 0;
  List<ScheduledReminder>? scheduled;
  final shown = <RoutineReminder>[];

  FakeNotifier({required this.schedulesInBackground, this.allow = true});

  int prepared = 0;

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<void> replaceScheduled(List<ScheduledReminder> reminders) async => scheduled = reminders;

  @override
  Future<void> show(RoutineReminder reminder) async => shown.add(reminder);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RoutineSettings', () {
    const on = RoutineSettings(
      morning: ReminderTime(enabled: true, minutes: 9 * 60),
      afternoon: ReminderTime(enabled: true, minutes: 17 * 60 + 30),
    );

    test('both reminders are off until turned on, at 09:00 and 17:00', () async {
      final s = await RoutineSettings.load();
      expect(s.morning, const ReminderTime(enabled: false, minutes: 9 * 60));
      expect(s.afternoon, const ReminderTime(enabled: false, minutes: 17 * 60));
      expect(s.anyEnabled, isFalse);
      expect(s.upcoming(DateTime(2026, 11, 14, 8)), isEmpty);
      expect(s.next(DateTime(2026, 11, 14, 8)), isNull);
    });

    test('are kept in this device\'s preferences, not in the synced list', () async {
      await on.save();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reminders.morning.on'), isTrue);
      expect(prefs.getInt('reminders.afternoon.at'), 17 * 60 + 30);
      expect(await RoutineSettings.load(), on);
    });

    test('a stored time out of range falls back to the default', () async {
      SharedPreferences.setMockInitialValues({'reminders.morning.at': 5000});
      expect((await RoutineSettings.load()).morning.minutes, 9 * 60);
    });

    test('upcoming reminders start today, or tomorrow once today\'s time has passed', () {
      final soon = on.upcoming(DateTime(2026, 11, 14, 12), days: 2);
      expect(soon.map((s) => (s.reminder, s.at)), [
        (RoutineReminder.afternoon, DateTime(2026, 11, 14, 17, 30)),
        (RoutineReminder.morning, DateTime(2026, 11, 15, 9)),
        (RoutineReminder.afternoon, DateTime(2026, 11, 15, 17, 30)),
      ]);
      expect(on.next(DateTime(2026, 11, 14, 12))!.reminder, RoutineReminder.afternoon);
      expect(on.next(DateTime(2026, 11, 14, 17, 30))!.at, DateTime(2026, 11, 15, 9));
    });

    test('each day gets its own notification id, across a month\'s end', () {
      final all = on.upcoming(DateTime(2026, 11, 25, 6));
      expect(all, hasLength(2 * RoutineSettings.daysAhead));
      expect(all.map((s) => s.id).toSet(), hasLength(all.length));
      expect(all.last.at, DateTime(2026, 12, 8, 17, 30));
    });

    test('a reminder that is off is left out', () {
      final mornings = on
          .withTime(RoutineReminder.afternoon, on.afternoon.copyWith(enabled: false))
          .upcoming(DateTime(2026, 11, 14, 12));
      expect(mornings.every((s) => s.reminder == RoutineReminder.morning), isTrue);
      expect(mornings, hasLength(RoutineSettings.daysAhead - 1));
    });

    test('the time shows as hours and minutes', () {
      expect(const ReminderTime(enabled: true, minutes: 9 * 60 + 5).label, '09:05');
      expect(const ReminderTime(enabled: true, minutes: 17 * 60 + 30).label, '17:30');
    });
  });

  group('RemindersCubit where the system schedules', () {
    final now = DateTime(2026, 11, 14, 10);

    test('turning a reminder on asks for permission and schedules the next days', () async {
      final notifier = FakeNotifier(schedulesInBackground: true);
      final cubit = RemindersCubit(notifier: notifier, now: () => now);
      await cubit.load();
      expect(notifier.scheduled, isEmpty);
      expect(notifier.permissionRequests, 0, reason: 'nothing is asked at start');

      await cubit.setEnabled(RoutineReminder.morning, true);
      expect(notifier.permissionRequests, 1);
      expect(cubit.state.settings.morning.enabled, isTrue);
      // Today's 09:00 has passed: the first is tomorrow's.
      expect(notifier.scheduled!.first.at, DateTime(2026, 11, 15, 9));
      expect(notifier.scheduled, hasLength(RoutineSettings.daysAhead - 1));
      expect(cubit.timerActive, isFalse, reason: 'the system rings them, not the app');

      await cubit.setMinutes(RoutineReminder.morning, 11 * 60);
      expect(notifier.scheduled!.first.at, DateTime(2026, 11, 14, 11));
      expect((await RoutineSettings.load()).morning.minutes, 11 * 60);

      await cubit.setEnabled(RoutineReminder.morning, false);
      expect(notifier.scheduled, isEmpty);
      expect(notifier.permissionRequests, 1, reason: 'turning off asks nothing');
      await cubit.close();
    });

    test('a refused permission leaves the reminder off and says so', () async {
      final notifier = FakeNotifier(schedulesInBackground: true, allow: false);
      final cubit = RemindersCubit(notifier: notifier, now: () => now);
      await cubit.load();
      await cubit.setEnabled(RoutineReminder.afternoon, true);
      expect(cubit.state.settings.afternoon.enabled, isFalse);
      expect(cubit.state.denied, isTrue);
      expect((await RoutineSettings.load()).afternoon.enabled, isFalse);

      notifier.allow = true;
      await cubit.setEnabled(RoutineReminder.afternoon, true);
      expect(cubit.state.denied, isFalse);
      expect(cubit.state.settings.afternoon.enabled, isTrue);
      await cubit.close();
    });

    test('starting and coming back top the schedule up from today', () async {
      SharedPreferences.setMockInitialValues({'reminders.afternoon.on': true});
      var today = now;
      final notifier = FakeNotifier(schedulesInBackground: true);
      final cubit = RemindersCubit(notifier: notifier, now: () => today);
      await cubit.load();
      expect(notifier.scheduled!.first.at, DateTime(2026, 11, 14, 17));
      today = DateTime(2026, 11, 20, 18);
      await cubit.resumed();
      expect(notifier.scheduled!.first.at, DateTime(2026, 11, 21, 17));
      expect(notifier.scheduled!.last.at, DateTime(2026, 12, 3, 17));
      await cubit.close();
    });
  });

  group('RemindersCubit where the app rings them itself', () {
    test('shows each reminder at its time while open, every day', () {
      SharedPreferences.setMockInitialValues({
        'reminders.morning.on': true,
        'reminders.afternoon.on': true,
      });
      fakeAsync((async) {
        final start = DateTime(2026, 11, 14, 8);
        final clock = async.getClock(start);
        final notifier = FakeNotifier(schedulesInBackground: false);
        final cubit = RemindersCubit(notifier: notifier, now: clock.now);
        cubit.load();
        async.flushMicrotasks();
        expect(notifier.scheduled, isNull, reason: 'nothing is handed to the system');
        expect(notifier.prepared, 1);
        expect(cubit.timerActive, isTrue);

        async.elapse(const Duration(minutes: 59));
        expect(notifier.shown, isEmpty);
        async.elapse(const Duration(minutes: 1));
        expect(notifier.shown, [RoutineReminder.morning]);
        async.elapse(const Duration(hours: 8));
        expect(notifier.shown, [RoutineReminder.morning, RoutineReminder.afternoon]);
        async.elapse(const Duration(hours: 16));
        expect(notifier.shown,
            [RoutineReminder.morning, RoutineReminder.afternoon, RoutineReminder.morning]);

        cubit.close();
        async.flushMicrotasks();
        expect(cubit.timerActive, isFalse);
      });
    });

    test('a reminder turned off or moved rings at its new time, or not at all', () {
      SharedPreferences.setMockInitialValues({'reminders.morning.on': true});
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 11, 14, 8));
        final notifier = FakeNotifier(schedulesInBackground: false);
        final cubit = RemindersCubit(notifier: notifier, now: clock.now);
        cubit.load();
        async.flushMicrotasks();

        cubit.setMinutes(RoutineReminder.morning, 8 * 60 + 30);
        async.elapse(const Duration(minutes: 30));
        expect(notifier.shown, [RoutineReminder.morning]);

        cubit.setEnabled(RoutineReminder.morning, false);
        async.elapse(const Duration(days: 1));
        expect(notifier.shown, [RoutineReminder.morning]);
        expect(cubit.timerActive, isFalse);
        cubit.close();
      });
    });

    test('a reminder that comes too late, after the device slept, is dropped', () {
      SharedPreferences.setMockInitialValues({'reminders.morning.on': true});
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 11, 14, 8));
        // The wall clock runs ahead of the timers, as it does while a laptop sleeps.
        var slept = Duration.zero;
        final notifier = FakeNotifier(schedulesInBackground: false);
        final cubit = RemindersCubit(notifier: notifier, now: () => clock.now().add(slept));
        cubit.load();
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 30));
        slept = const Duration(hours: 2);
        async.elapse(const Duration(minutes: 30));
        expect(notifier.shown, isEmpty);
        expect(cubit.timerActive, isTrue, reason: 'tomorrow\'s is still due');
        cubit.close();
      });
    });
  });

  group('Settings', () {
    late TasksBloc tasks;

    Future<void> finish(WidgetTester tester, RemindersCubit cubit) async {
      // Stops the task list's clock, which would otherwise outlive the test.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(tasks.close);
      await cubit.close();
    }

    Future<(RemindersCubit, FakeNotifier)> pumpSettings(WidgetTester tester,
        {bool background = true}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final notifier = FakeNotifier(schedulesInBackground: background);
      final cubit = RemindersCubit(notifier: notifier, now: () => DateTime(2026, 11, 14, 10));
      tasks = TasksBloc();
      await tester.runAsync(cubit.load);
      await tester.pumpWidget(MultiBlocProvider(providers: [
        BlocProvider.value(value: tasks),
        BlocProvider.value(value: cubit),
      ], child: const MaterialApp(home: SettingsPage())));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      return (cubit, notifier);
    }

    testWidgets('lists both reminders with their times, off', (tester) async {
      final (cubit, _) = await pumpSettings(tester);
      expect(find.text('Morning reminder'), findsOneWidget);
      expect(find.text('Afternoon reminder'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('reminder.morning.on'))).value, isFalse);
      expect(find.textContaining('with the app closed too'), findsOneWidget);
      expect(find.textContaining('on this device only'), findsOneWidget);
      await finish(tester, cubit);
    });

    testWidgets('the switch turns a reminder on', (tester) async {
      final (cubit, notifier) = await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('reminder.afternoon.on')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(notifier.permissionRequests, 1);
      expect(cubit.state.settings.afternoon.enabled, isTrue);
      expect(tester.widget<Switch>(find.byKey(const Key('reminder.afternoon.on'))).value, isTrue);
      await finish(tester, cubit);
    });

    testWidgets('the time opens a picker that sets it', (tester) async {
      final (cubit, _) = await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('reminder.morning.time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      // Type the time instead of dragging the dial.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '7');
      await tester.enterText(fields.at(1), '45');
      await tester.tap(find.text('OK'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(cubit.state.settings.morning.minutes, 7 * 60 + 45);
      expect(find.text('07:45'), findsOneWidget);
      await finish(tester, cubit);
    });

    testWidgets('a refused permission says how to allow it', (tester) async {
      final (cubit, notifier) = await pumpSettings(tester);
      notifier.allow = false;
      await tester.tap(find.byKey(const Key('reminder.morning.on')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('Notifications are blocked'), findsOneWidget);
      await finish(tester, cubit);
    });

    testWidgets('says reminders ring only while open where the app rings them', (tester) async {
      final (cubit, _) = await pumpSettings(tester, background: false);
      expect(find.textContaining('while bringmeback is open'), findsOneWidget);
      await finish(tester, cubit);
    });
  });
}
