import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/focus/focus_page.dart';
import 'package:bringmeback/focus/pomodoro.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late TasksBloc tasks;
  late PomodoroCubit pomodoro;
  late DateTime now;

  Future<void> pumpFocus(WidgetTester tester, String taskId) async {
    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider.value(value: tasks),
        BlocProvider.value(value: pomodoro),
      ],
      child: MaterialApp(home: FocusPage(taskId: taskId)),
    ));
    await tester.pump();
  }

  Future<void> addTasks(WidgetTester tester, List<String> names) async {
    // Added on top in reverse, so the list reads in the given order.
    for (final name in names.reversed) {
      tasks.add(AddTaskOnTopEvent(name: '', id: ValueKey(name)));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      tasks.add(UpdateTaskNameEvent(id: ValueKey(name), newName: name));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  }

  setUpAll(() {
    // TasksBloc makes an audio player; tests have no audio plugin.
    TestWidgetsFlutterBinding.ensureInitialized();
    // Its method and event channels get empty answers; everything else goes through as usual.
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
    now = DateTime(2026, 11, 9, 9);
  });

  testWidgets(
      'focusing a task makes it current and shows the others as up next',
      (tester) async {
    await tester.runAsync(() async {
      tasks = TasksBloc();
      await tasks.document;
    });
    pomodoro = PomodoroCubit(now: () => now, startTicking: false);
    await addTasks(tester, ['Write docs', 'Review PR', 'Call bank']);

    // Desktop width: the clock and the up next list side by side.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpFocus(tester, 'Review PR');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(tasks.state.tasks.first.name, 'Review PR');
    expect(find.text('Review PR'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('1. Write docs'), findsOneWidget);
    expect(find.text('2. Call bank'), findsOneWidget);

    await tester.runAsync(() async {
      await pomodoro.close();
      await tasks.close();
    });
  });

  testWidgets('the task timer runs during focus and pauses during breaks',
      (tester) async {
    await tester.runAsync(() async {
      tasks = TasksBloc();
      await tasks.document;
    });
    pomodoro = PomodoroCubit(now: () => now, startTicking: false);
    await addTasks(tester, ['Write docs']);
    await pumpFocus(tester, 'Write docs');

    // Pause from the list first, so starting the Pomodoro is what resumes it.
    tasks.add(StopTimerEvent(index: 0));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(tasks.state.tasks.first.running, isFalse);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(pomodoro.state.running, isTrue);
    expect(tasks.state.tasks.first.running, isTrue);

    await tester.tap(find.byTooltip('Skip to break'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(pomodoro.state.phase, PomodoroPhase.shortBreak);
    expect(tasks.state.tasks.first.running, isFalse);
    expect(find.text('Short break'), findsOneWidget);

    await tester.runAsync(() async {
      await pomodoro.close();
      await tasks.close();
    });
  });

  testWidgets('settings dialog returns the new lengths', (tester) async {
    PomodoroSettings? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<PomodoroSettings>(
            context: context,
            builder: (_) =>
                const PomodoroSettingsDialog(settings: PomodoroSettings()),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Focus'), '50');
    await tester.enterText(find.widgetWithText(TextField, 'Short break'), '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.workMinutes, 50);
    expect(result?.shortBreakMinutes, 10);
    expect(result?.longBreakMinutes, 15);
  });

  testWidgets('settings dialog refuses an empty length', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home:
          Scaffold(body: PomodoroSettingsDialog(settings: PomodoroSettings())),
    ));
    await tester.enterText(find.widgetWithText(TextField, 'Focus'), '');
    await tester.pump();
    final save =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save.onPressed, isNull);
    expect(find.text('Enter a number above 0'), findsOneWidget);
  });
}
