import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/focus/focus_page.dart';
import 'package:bringmeback/focus/pomodoro.dart';
import 'package:bringmeback/settings/keep_screen_on.dart';
import 'package:bringmeback/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'doc_sync_test.dart' show newDocument;

/// K1 of docs/USER-STORIES.md: the screen stays on while a timer runs.
void main() {
  late TasksBloc tasks;
  late List<bool> asked;

  /// What the platform was last asked: true while the screen is held on.
  bool held() => asked.isNotEmpty && asked.last;

  KeepScreenOnCubit newScreen() =>
      KeepScreenOnCubit(tasks: tasks, setAwake: (on) async => asked.add(on));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Future<void> addTask(WidgetTester tester, String name) async {
    tasks.add(AddTaskOnTopEvent(name: '', id: ValueKey(name)));
    await settle(tester);
    tasks.add(UpdateTaskNameEvent(id: ValueKey(name), newName: name));
    await settle(tester);
  }

  setUpAll(() {
    // TasksBloc makes an audio player; tests have no audio plugin.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) async {
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      }
      return handler?.call(message);
    };
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    asked = [];
  });

  testWidgets('K1.1 the screen stays on while a task timer runs, and goes back to normal after',
      (tester) async {
    await tester.runAsync(() async {
      tasks = TasksBloc();
      await tasks.document;
    });
    final screen = newScreen();
    await tester.runAsync(screen.load);
    // A new task starts with its timer running.
    await addTask(tester, 'Write docs');
    expect(tasks.state.tasks.first.running, isTrue);
    expect(held(), isTrue);

    tasks.add(StopTimerEvent(index: 0));
    await settle(tester);
    expect(held(), isFalse);

    tasks.add(ResumeTimerEvent(index: 0));
    await settle(tester);
    expect(held(), isTrue);

    // Closing the app lets the screen go.
    await tester.runAsync(() async {
      await screen.close();
      await tasks.close();
    });
    expect(held(), isFalse);
  });

  testWidgets('K1.2 turned off in Settings, the screen sleeps as usual, and the choice is kept',
      (tester) async {
    await tester.runAsync(() async {
      tasks = TasksBloc();
      await tasks.document;
    });
    final screen = newScreen();
    await tester.runAsync(screen.load);
    expect(screen.state.enabled, isTrue, reason: 'On by default');
    await addTask(tester, 'Write docs');
    expect(held(), isTrue);

    await tester.pumpWidget(MultiBlocProvider(providers: [
      BlocProvider.value(value: tasks),
      BlocProvider.value(value: screen),
    ], child: const MaterialApp(home: SettingsPage())));
    await tester.pump();
    final toggle = find.byKey(const Key('keepScreenOn'));
    await tester.scrollUntilVisible(toggle, 100);
    await tester.tap(toggle);
    await settle(tester);
    expect(screen.state.enabled, isFalse);
    expect(held(), isFalse, reason: 'Off while the timer still runs');

    // The app starts again: the setting stays off.
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('keepScreenOn'), isFalse);
    final again = newScreen();
    await tester.runAsync(again.load);
    expect(again.state.enabled, isFalse);
    expect(again.state.awake, isFalse);

    await tester.tap(toggle);
    await settle(tester);
    expect(held(), isTrue, reason: 'Back on, with the timer running');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await again.close();
      await screen.close();
      await tasks.close();
    });
  });

  testWidgets('K1.3 a Pomodoro break keeps the screen on, though no task timer runs',
      (tester) async {
    await tester.runAsync(() async {
      tasks = TasksBloc();
      await tasks.document;
    });
    final now = DateTime(2026, 11, 18, 9);
    final pomodoro = PomodoroCubit(now: () => now, startTicking: false);
    final screen = newScreen();
    await addTask(tester, 'Write docs');

    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider.value(value: tasks),
        BlocProvider.value(value: pomodoro),
        BlocProvider.value(value: screen),
      ],
      child: const MaterialApp(home: FocusPage(taskId: 'Write docs')),
    ));
    await settle(tester);
    expect(pomodoro.state.running, isTrue);
    expect(held(), isTrue);

    await tester.tap(find.byTooltip('Skip to break'));
    await settle(tester);
    expect(pomodoro.state.phase, PomodoroPhase.shortBreak);
    expect(tasks.state.tasks.first.running, isFalse);
    expect(held(), isTrue, reason: 'The break clock is still counting down');

    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(held(), isFalse);

    // Resumed, then the focus view is left: it pauses, and the screen goes back to normal.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    expect(held(), isTrue);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(held(), isFalse);

    await tester.runAsync(() async {
      await screen.close();
      await pomodoro.close();
      await tasks.close();
    });
  });

  testWidgets(
      'K1.4 a timer started on another device keeps this screen on too, once the change arrives',
      (tester) async {
    await tester.runAsync(() async {
      tasks = TasksBloc();
      await tasks.document;
    });
    final screen = newScreen();
    final here = (await tester.runAsync(() => tasks.document))!;
    final desktop = newDocument();
    // What sync does: the desktop's new changes are imported here.
    void exchange() => here.importChanges(
        desktop.doc.exportChanges(fromVersionVector: here.getVersionVector()));
    desktop.insert(0, 'd1', name: 'From the desktop');
    await tester.runAsync(() async => exchange());
    await settle(tester);
    expect(held(), isFalse);

    desktop.setRunning('d1', true);
    await tester.runAsync(() async => exchange());
    await settle(tester);
    expect(tasks.state.tasks.single.running, isTrue);
    expect(held(), isTrue);

    desktop.setRunning('d1', false);
    await tester.runAsync(() async => exchange());
    await settle(tester);
    expect(held(), isFalse);

    await tester.runAsync(() async {
      await screen.close();
      await tasks.close();
    });
  });

  test('K1.5 a platform that refuses the wake lock leaves the app working', () async {
    var calls = 0;
    final screen = KeepScreenOnCubit(setAwake: (on) async {
      calls++;
      throw UnsupportedError('No wake lock here');
    });
    screen.setFocusRunning(true);
    await pumpEventQueue();
    expect(screen.state.awake, isTrue);
    expect(calls, 1);

    // Asked again when the app comes back to the foreground.
    screen.reapply();
    await pumpEventQueue();
    expect(calls, 2);
    await screen.close();
  });
}
