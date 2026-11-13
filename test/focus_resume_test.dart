import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/focus/pomodoro.dart';
import 'package:bringmeback/main.dart';
import 'package:crdt_lf/crdt_lf.dart';
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

  group('PomodoroRecord', () {
    final now = DateTime(2026, 11, 13, 9);
    const paused = PomodoroState(
        settings: settings,
        phase: PomodoroPhase.shortBreak,
        remainingSeconds: 200,
        running: false,
        completedSessions: 2,
        workSeconds: 30 * 60);

    PomodoroRecord? roundTrip(PomodoroRecord r, {DateTime? at}) =>
        PomodoroRecord.decode(r.encode(), now: at ?? now);

    test('a paused clock comes back as it was', () {
      final r = roundTrip(PomodoroRecord(
          state: paused, endsAt: null, open: true, savedAt: now))!;
      final (clock, endsAt) = r.at(now.add(const Duration(hours: 1)));
      expect(clock.phase, PomodoroPhase.shortBreak);
      expect(clock.remainingSeconds, 200, reason: 'time away does not count');
      expect(clock.completedSessions, 2);
      expect(clock.settings, settings);
      expect(clock.running, isFalse);
      expect(endsAt, isNull);
      expect(r.open, isTrue);
    });

    test('a running clock carries on by the wall clock', () {
      final r = roundTrip(PomodoroRecord(
          state: paused.copyWith(running: true),
          endsAt: now.add(const Duration(seconds: 200)),
          open: true,
          savedAt: now))!;
      final (clock, endsAt) = r.at(now.add(const Duration(seconds: 50)));
      expect(clock.running, isTrue);
      expect(clock.remainingSeconds, 150);
      expect(endsAt, now.add(const Duration(seconds: 200)));
    });

    test('a running phase that ended unwatched waits at the next one', () {
      final r = roundTrip(PomodoroRecord(
          state: const PomodoroState(
              settings: settings,
              phase: PomodoroPhase.work,
              remainingSeconds: 60,
              running: true,
              completedSessions: 1,
              workSeconds: 30 * 60),
          endsAt: now.add(const Duration(seconds: 60)),
          open: true,
          savedAt: now))!;
      final (clock, endsAt) = r.at(now.add(const Duration(hours: 2)));
      expect(clock.phase, PomodoroPhase.shortBreak);
      expect(clock.completedSessions, 2);
      expect(clock.remainingSeconds, 6 * 60);
      expect(clock.running, isFalse);
      expect(endsAt, isNull);
    });

    test('same content, same key; old or damaged reads as none', () {
      final a =
          PomodoroRecord(state: paused, endsAt: null, open: true, savedAt: now);
      final b = PomodoroRecord(
          state: paused,
          endsAt: null,
          open: true,
          savedAt: now.add(const Duration(minutes: 3)));
      expect(a.key, b.key);
      expect(
          PomodoroRecord(state: paused, endsAt: null, open: false, savedAt: now)
              .key,
          isNot(a.key));
      expect(
          roundTrip(a,
              at: now.add(PomodoroRecord.maxAge - const Duration(minutes: 1))),
          isNotNull);
      expect(roundTrip(a, at: now.add(PomodoroRecord.maxAge)), isNull);
      expect(PomodoroRecord.decode('{not json', now: now), isNull);
      expect(PomodoroRecord.decode('{"phase":"work"}', now: now), isNull);
      expect(PomodoroRecord.decode(null, now: now), isNull);
    });

    test('syncs with the task to another device', () {
      TaskDocument doc() => TaskDocument(
          CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks'));
      final laptop = doc()..insert(0, 'r', name: 'Write report');
      final phone = doc();
      laptop.setPomodoro(
          'r',
          PomodoroRecord(state: paused, endsAt: null, open: true, savedAt: now)
              .encode());
      phone.doc.importChanges(laptop.doc.exportChanges());
      final r = PomodoroRecord.decode(phone.task('r').pomodoro, now: now)!;
      expect(r.state.remainingSeconds, 200);
      expect(r.open, isTrue);
    });
  });

  test('a clock picked up keeps its state; a running one keeps running', () {
    var now = DateTime(2026, 11, 13, 9);
    const clock = PomodoroState(
        settings: settings,
        phase: PomodoroPhase.work,
        remainingSeconds: 600,
        running: true,
        completedSessions: 1,
        workSeconds: 30 * 60);
    final paused =
        PomodoroCubit(resumeFrom: clock, now: () => now, startTicking: false);
    expect(paused.state.running, isFalse,
        reason: 'running needs to know when it ends');
    final running = PomodoroCubit(
        resumeFrom: clock,
        endsAt: now.add(const Duration(seconds: 600)),
        now: () => now,
        startTicking: false);
    now = now.add(const Duration(minutes: 2));
    running.tick();
    expect(running.state.remainingSeconds, 480);
    expect(running.state.completedSessions, 1);

    // Another device paused it.
    running.apply(clock.copyWith(running: false, remainingSeconds: 300), null);
    expect(running.state.running, isFalse);
    expect(running.endsAt, isNull);
    now = now.add(const Duration(minutes: 2));
    running.tick();
    expect(running.state.remainingSeconds, 300);
    paused.close();
    running.close();
  });

  testWidgets('leaving the focus view and coming back picks up where it was',
      (tester) async {
    final bloc = await startApp(tester);
    bloc.add(InsertTaskEvent(
        index: 0, name: 'Write report', id: const ValueKey('r')));
    await settle(tester);

    await openFocusOn(tester, 'Write report');
    expect(find.textContaining('Session 1 of '), findsOneWidget);
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

  testWidgets('after a crash the app reopens the focus view, running on',
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
    expect(find.textContaining('Session 2 of '), findsOneWidget);

    final kept = await crash(tester, bloc);
    SharedPreferences.setMockInitialValues(kept);
    bloc = await startApp(tester);

    expect(find.byKey(const Key('focusTaskName')), findsOneWidget);
    expect(find.text('Call bank'), findsWidgets);
    expect(find.textContaining('Session 2 of '), findsOneWidget);
    expect(find.text('Picked up where you left off'), findsOneWidget);
    // Still running, as is the task's own timer.
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(bloc.state.tasks.first.name, 'Call bank');
    expect(bloc.state.tasks.first.running, isTrue);

    // Closed on purpose this time: paused, and the next start stays on the list.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final again = {for (final k in prefs!.getKeys()) k: prefs.get(k)!};
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
    SharedPreferences.setMockInitialValues(again);
    bloc = await startApp(tester);
    expect(find.byKey(const Key('pomodoroClock')), findsNothing);
    final record = PomodoroRecord.decode(bloc.state.tasks.first.pomodoro)!;
    expect(record.open, isFalse);
    expect(record.state.running, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets('a paused clock reopens paused after a crash', (tester) async {
    var bloc = await startApp(tester);
    bloc.add(InsertTaskEvent(
        index: 0, name: 'Write report', id: const ValueKey('r')));
    await settle(tester);
    await openFocusOn(tester, 'Write report');
    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await settle(tester);

    final kept = await crash(tester, bloc);
    SharedPreferences.setMockInitialValues(kept);
    bloc = await startApp(tester);
    expect(find.byKey(const Key('focusTaskName')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);
    expect(bloc.state.tasks.first.running, isFalse);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets('a change from another device shows in the open focus view',
      (tester) async {
    final bloc = await startApp(tester);
    bloc.add(InsertTaskEvent(
        index: 0, name: 'Write report', id: const ValueKey('r')));
    await settle(tester);
    await openFocusOn(tester, 'Write report');
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    // The phone paused it in its long break, as the synced task now says.
    bloc.add(SetPomodoroEvent(
        taskId: 'r',
        record: PomodoroRecord(
                state: const PomodoroState(
                    settings: PomodoroSettings(),
                    phase: PomodoroPhase.longBreak,
                    remainingSeconds: 600,
                    running: false,
                    completedSessions: 4,
                    workSeconds: 25 * 60),
                endsAt: null,
                open: true,
                savedAt: DateTime.now())
            .encode()));
    await settle(tester);
    expect(find.text('Long break'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('4 done'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
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

    expect(bloc.state.tasks.first.pomodoro, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });
}
