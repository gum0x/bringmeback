import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/focus/pomodoro.dart';
import 'package:bringmeback/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settings = PomodoroSettings(
    workMinutes: 30,
    shortBreakMinutes: 6,
    longBreakMinutes: 20,
    sessionsBeforeLongBreak: 3);

Future<void> settle(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pumpAndSettle();
}

/// Starts the app's task view on what shared preferences hold now, as a fresh start of the app.
Future<TasksBloc> startApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bloc = TasksBloc();
  await tester.pumpWidget(BlocProvider.value(
    value: bloc,
    child: const MaterialApp(home: TasksStack()),
  ));
  await settle(tester);
  return bloc;
}

/// Ends the app the way a crash or a closed tab does: nothing is disposed first, so all that
/// survives is what was already saved. Returns what was.
Future<Map<String, Object>> crash(WidgetTester tester, TasksBloc bloc) async {
  final prefs = await tester.runAsync(SharedPreferences.getInstance);
  final kept = {for (final k in prefs!.getKeys()) k: prefs.get(k)!};
  // Taken down only after the copy, so the view's goodbye save doesn't count.
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(bloc.close);
  return kept;
}

Future<void> openFocusOn(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Focus with Pomodoro'));
  await settle(tester);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No audio plugin in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) async {
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      }
      return handler?.call(message);
    };
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PomodoroMemory', () {
    final now = DateTime(2026, 11, 13, 9);
    const state = PomodoroState(
        settings: settings,
        phase: PomodoroPhase.shortBreak,
        remainingSeconds: 200,
        running: true,
        completedSessions: 2);

    test('keeps each task\'s clock, which comes back paused', () async {
      await PomodoroMemory.save('a', state, now: now);
      await PomodoroMemory.save('b', PomodoroState.initial(settings), now: now);

      final a = await PomodoroMemory.load('a', now: now);
      expect(a?.phase, PomodoroPhase.shortBreak);
      expect(a?.remainingSeconds, 200);
      expect(a?.completedSessions, 2);
      expect(a?.settings, settings);
      expect(a?.running, isFalse);
      expect((await PomodoroMemory.load('b', now: now))?.remainingSeconds,
          30 * 60);
      expect(await PomodoroMemory.load('c', now: now), isNull);
    });

    test('forgets a clock left alone too long, or forgotten on purpose',
        () async {
      await PomodoroMemory.save('a', state, now: now);
      await PomodoroMemory.save('b', state, now: now);
      expect(
          await PomodoroMemory.load('a',
              now: now.add(PomodoroMemory.maxAge - const Duration(minutes: 1))),
          isNotNull);
      expect(
          await PomodoroMemory.load('a', now: now.add(PomodoroMemory.maxAge)),
          isNull);

      await PomodoroMemory.forget('b');
      expect(await PomodoroMemory.load('b', now: now), isNull);
    });

    test('leaves the saved lengths alone', () async {
      await settings.save();
      await PomodoroMemory.save('a', state, now: now);
      await PomodoroMemory.setOpen('a');
      expect(await PomodoroSettings.load(), settings);
      expect(await PomodoroMemory.openTask(), 'a');
      await PomodoroMemory.setOpen(null);
      expect(await PomodoroMemory.openTask(), isNull);
    });

    test('a damaged record starts fresh instead of failing', () async {
      SharedPreferences.setMockInitialValues({'focusClocks': '{not json'});
      expect(await PomodoroMemory.load('a', now: now), isNull);
      await PomodoroMemory.save('a', state, now: now);
      expect(await PomodoroMemory.load('a', now: now), isNotNull);
    });
  });

  test('a clock picked up waits paused, then carries on from there', () {
    var now = DateTime(2026, 11, 13, 9);
    final cubit = PomodoroCubit(
      resumeFrom: const PomodoroState(
          settings: settings,
          phase: PomodoroPhase.work,
          remainingSeconds: 600,
          running: true,
          completedSessions: 1),
      now: () => now,
      startTicking: false,
    );
    expect(cubit.state.running, isFalse);
    expect(cubit.state.remainingSeconds, 600);
    now = now.add(const Duration(minutes: 5));
    cubit.tick();
    expect(cubit.state.remainingSeconds, 600,
        reason: 'time away does not count');
    cubit.start();
    now = now.add(const Duration(minutes: 2));
    cubit.tick();
    expect(cubit.state.remainingSeconds, 480);
    expect(cubit.state.completedSessions, 1);
    cubit.close();
  });

  testWidgets('leaving the focus view and coming back picks up where it was',
      (tester) async {
    final bloc = await startApp(tester);
    bloc.add(InsertTaskEvent(
        index: 0, name: 'Write report', id: const ValueKey('r')));
    await settle(tester);

    await openFocusOn(tester, 'Write report');
    expect(find.text('Session 1 of 4'), findsOneWidget);
    // One session finished: on to the short break.
    await tester.tap(find.byTooltip('Skip to break'));
    await settle(tester);
    expect(find.text('Short break'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.byKey(const Key('pomodoroClock')), findsNothing);

    await openFocusOn(tester, 'Write report');
    expect(find.text('Short break'), findsOneWidget);
    expect(find.text('1 done'), findsOneWidget);
    expect(find.text('Picked up where you left off'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets(
      'after a crash the app reopens the focus view, paused where it was',
      (tester) async {
    var bloc = await startApp(tester);
    bloc.add(InsertTaskEvent(
        index: 0, name: 'Write report', id: const ValueKey('r')));
    bloc.add(
        InsertTaskEvent(index: 1, name: 'Call bank', id: const ValueKey('c')));
    await settle(tester);
    await openFocusOn(tester, 'Call bank');
    await tester.tap(find.byTooltip('Skip to break'));
    await settle(tester);
    await tester.tap(find.byTooltip('Skip break'));
    await settle(tester);
    expect(find.text('Session 2 of 4'), findsOneWidget);

    final kept = await crash(tester, bloc);
    SharedPreferences.setMockInitialValues(kept);
    bloc = await startApp(tester);

    expect(find.byKey(const Key('focusTaskName')), findsOneWidget);
    expect(find.text('Call bank'), findsWidgets);
    expect(find.text('Session 2 of 4'), findsOneWidget);
    expect(find.text('Picked up where you left off'), findsOneWidget);
    // Waiting for the person, and so is the task's own timer.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(bloc.state.tasks.first.name, 'Call bank');
    expect(bloc.state.tasks.first.running, isFalse);

    // Closed on purpose this time: the next start stays on the list.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final again = {for (final k in prefs!.getKeys()) k: prefs.get(k)!};
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
    SharedPreferences.setMockInitialValues(again);
    bloc = await startApp(tester);
    expect(find.byKey(const Key('pomodoroClock')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets('a task marked done in focus starts fresh next time',
      (tester) async {
    final bloc = await startApp(tester);
    bloc.add(InsertTaskEvent(
        index: 0, name: 'Write report', id: const ValueKey('r')));
    await settle(tester);
    await openFocusOn(tester, 'Write report');
    await tester.tap(find.byTooltip('Skip to break'));
    await settle(tester);
    await tester.tap(find.text('Mark task done'));
    await settle(tester);

    expect(await tester.runAsync(() => PomodoroMemory.load('r')), isNull);
    expect(await tester.runAsync(PomodoroMemory.openTask), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });
}
