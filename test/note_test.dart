import 'package:bringmeback/bloc/history.dart';
import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/focus/pomodoro.dart';
import 'package:bringmeback/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs [body] on the app's task view, without sync, which needs native code.
void noteTest(String description, Future<void> Function(WidgetTester tester, TasksBloc bloc) body,
    {Size size = const Size(1000, 900)}) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = TasksBloc();
    await tester.pumpWidget(BlocProvider.value(
      value: bloc,
      child: const MaterialApp(home: TasksStack()),
    ));
    // Loading reads shared preferences asynchronously.
    await settle(tester);
    await body(tester, bloc);
    // Stops the bloc's clock, which would otherwise outlive the test.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pumpAndSettle();
}

/// Writes a task through the dialog the button at [button] opens.
Future<void> writeThrough(WidgetTester tester, Finder button, String name,
    {String? minutes}) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Task'), name);
  if (minutes != null) {
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), minutes);
  }
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await settle(tester);
}

List<String> names(TasksBloc bloc) => [for (final t in bloc.state.tasks) t.name];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  noteTest('tasks are written through the dialog as numbered lines', (tester, bloc) async {
    expect(find.text('Write your first task'), findsOneWidget);

    await writeThrough(tester, find.text('Write your first task'), 'Write report',
        minutes: '25');
    await writeThrough(tester, find.text('Add a task'), 'Call the bank');
    await writeThrough(tester, find.widgetWithText(FloatingActionButton, 'New task'),
        'Answer the phone');

    expect(names(bloc), ['Answer the phone', 'Write report', 'Call the bank']);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
    expect(bloc.state.tasks[1].timerLengthSeconds, 25 * 60);
    // A task on top is an interruption: it is timed.
    expect(bloc.state.tasks.first.running, isTrue);
    expect(find.byType(TaskClock), findsOneWidget);
    // Every task waiting its turn shows how long it is expected to take.
    expect(find.text('Expected 25:00'), findsOneWidget);
    expect(find.text('Expected 20:00'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Left \d+:\d+ of 20:00$')), findsOneWidget);
  });

  noteTest('checking a task off strikes it through and hands the timer on', (tester, bloc) async {
    await writeThrough(tester, find.text('Write your first task'), 'First');
    await writeThrough(tester, find.text('Add a task'), 'Second');
    bloc.add(ResumeTimerEvent(index: 0));
    await settle(tester);
    expect(bloc.state.tasks[0].running, isTrue);

    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);
    expect(bloc.state.tasks.map((t) => t.done), [true, false]);
    expect(names(bloc), ['First', 'Second'], reason: 'done tasks stay on the note');
    expect(bloc.state.currentIndex, 1);
    expect(bloc.state.tasks[1].running, isTrue);

    await tester.tap(find.byType(Checkbox).last);
    await settle(tester);
    expect(find.text('ALL DONE'), findsOneWidget);

    // Unchecking the first task makes it current again and takes the timer back.
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);
    expect(bloc.state.currentIndex, 0);
    expect(find.text('ALL DONE'), findsNothing);
  });

  noteTest('the (+) buttons of a selected task write above and below it', (tester, bloc) async {
    // A task just written is selected, so its (+) buttons show.
    await writeThrough(tester, find.text('Write your first task'), 'Middle');
    await writeThrough(tester, find.byTooltip('Add a task above'), 'Above');
    await tester.tap(find.text('Middle'));
    // A tap waits to see whether it is a double tap.
    await tester.pump(kDoubleTapTimeout);
    await settle(tester);
    await writeThrough(tester, find.byTooltip('Add a task below'), 'Below');
    expect(names(bloc), ['Above', 'Middle', 'Below']);
  });

  noteTest('a task is edited in the dialog', (tester, bloc) async {
    await writeThrough(tester, find.text('Write your first task'), 'Draft');
    // A double tap on the task opens it.
    await tester.tap(find.text('Draft'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Details'), 'Step one\nStep two');
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Final');
    await tester.tap(find.text('45 min'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(names(bloc), ['Final']);
    expect(bloc.state.tasks.single.timerLengthSeconds, 45 * 60);
    expect(bloc.state.tasks.single.notes, 'Step one\nStep two');
    expect(find.text('Step one\nStep two'), findsOneWidget);
  });

  /// Writes [count] tasks straight through the bloc.
  Future<void> fill(WidgetTester tester, TasksBloc bloc, int count) async {
    for (var i = 0; i < count; i++) {
      bloc.add(InsertTaskEvent(index: i, name: 'Task $i', id: ValueKey('t$i')));
    }
    await settle(tester);
  }

  noteTest('there is no hard cap on the note', (tester, bloc) async {
    await fill(tester, bloc, defaultTaskLimit + 5);
    expect(bloc.state.tasks, hasLength(defaultTaskLimit + 5));
    expect(find.text('Add a task'), findsOneWidget);
    expect(find.textContaining('over your limit of $defaultTaskLimit'), findsOneWidget);
  });

  noteTest('past the limit, a new task asks first and can go to the backlog', (tester, bloc) async {
    await fill(tester, bloc, defaultTaskLimit);
    expect(bloc.state.atLimit, isTrue);
    expect(find.textContaining('at your limit of $defaultTaskLimit'), findsOneWidget);

    await writeThrough(tester, find.text('Add a task'), 'Later thing');
    expect(find.text('Your note is at its limit'), findsOneWidget);
    await tester.tap(find.text('Save to backlog'));
    await settle(tester);
    expect(bloc.state.tasks, hasLength(defaultTaskLimit));
    expect([for (final t in bloc.state.backlog) t.name], ['Later thing']);
    expect(find.text('Backlog · 1'), findsOneWidget);

    // Cancelling writes nothing.
    await writeThrough(tester, find.text('Add a task'), 'Never mind');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(bloc.state.tasks, hasLength(defaultTaskLimit));
    expect(bloc.state.backlog, hasLength(1));

    // Or it goes on the note anyway.
    await writeThrough(tester, find.text('Add a task'), 'Urgent');
    await tester.tap(find.text('Write on note anyway'));
    await settle(tester);
    expect(names(bloc), contains('Urgent'));
    expect(bloc.state.tasks, hasLength(defaultTaskLimit + 1));
  });

  noteTest('done tasks don\'t count towards the limit', (tester, bloc) async {
    await fill(tester, bloc, defaultTaskLimit);
    bloc.add(SetDoneEvent(index: 0, done: true));
    await settle(tester);
    expect(bloc.state.atLimit, isFalse);
    await writeThrough(tester, find.text('Add a task'), 'One more');
    expect(find.text('Your note is at its limit'), findsNothing);
    expect(names(bloc), contains('One more'));
  });

  noteTest('a backlog task is written on the note, or removed', (tester, bloc) async {
    bloc.add(AddToBacklogEvent(name: 'Read the paper', id: const ValueKey('b1')));
    bloc.add(AddToBacklogEvent(name: 'Fix the bike', id: const ValueKey('b2')));
    await settle(tester);
    await tester.tap(find.text('Backlog · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Write on note').first);
    await settle(tester);
    expect(names(bloc), ['Read the paper']);
    expect([for (final t in bloc.state.backlog) t.name], ['Fix the bike']);

    await tester.tap(find.byTooltip('Remove from backlog'));
    await settle(tester);
    expect(bloc.state.backlog, isEmpty);
    expect(find.textContaining('Backlog'), findsNothing);
    expect(bloc.taskDocument!.status('b2'), TaskStatus.deleted);
  });

  noteTest('writing from the backlog past the limit asks first', (tester, bloc) async {
    await fill(tester, bloc, defaultTaskLimit);
    bloc.add(AddToBacklogEvent(name: 'Someday', id: const ValueKey('b1')));
    await settle(tester);
    await tester.ensureVisible(find.text('Backlog · 1'));
    await tester.tap(find.text('Backlog · 1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Write on note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Write on note'));
    await tester.pumpAndSettle();
    expect(find.text('Save to backlog'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(bloc.state.backlog, hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, 'Write on note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write on note anyway'));
    await settle(tester);
    expect(bloc.state.backlog, isEmpty);
    expect(names(bloc).last, 'Someday');
  });

  noteTest('an unfinished task of the last note can go to the backlog', (tester, bloc) async {
    bloc.add(InsertTaskEvent(index: 0, name: 'Carry me', id: const ValueKey('c1')));
    await settle(tester);
    bloc.add(TearOffNoteEvent());
    await settle(tester);
    await tester.tap(find.byTooltip('Move to backlog'));
    await settle(tester);
    expect(bloc.state.pending, isEmpty);
    expect([for (final t in bloc.state.backlog) t.name], ['Carry me']);

    // Written from the backlog, it is a new task carried from the old one, which keeps its note.
    bloc.add(WriteFromBacklogEvent(id: 'c1'));
    await settle(tester);
    expect(names(bloc), ['Carry me']);
    expect(bloc.state.tasks.single.id.value, isNot('c1'));
    expect(bloc.taskDocument!.status('c1'), TaskStatus.carried);
  });

  noteTest('the limit is set in Settings and kept', (tester, bloc) async {
    await fill(tester, bloc, 4);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('$defaultTaskLimit'), findsOneWidget);
    for (var i = 0; i < defaultTaskLimit - minTaskLimit + 1; i++) {
      await tester.tap(find.byTooltip('Lower task limit'));
      await settle(tester);
    }
    expect(bloc.state.taskLimit, minTaskLimit);
    expect(find.text('$minTaskLimit'), findsOneWidget);

    // A lower limit moves nothing already written.
    expect(bloc.state.tasks, hasLength(4));
    expect(bloc.state.atLimit, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('taskLimit'), minTaskLimit);
  });

  noteTest('the Pomodoro lengths are set in Settings and kept', (tester, bloc) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Long break every'), 100);
    expect(find.text('25 min'), findsOneWidget);
    for (final tooltip in ['Longer focus', 'Longer focus', 'Shorter short break']) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
    }
    expect(find.text('27 min'), findsOneWidget);
    expect(find.text('4 min'), findsOneWidget);
    // 4 × 27 min of focus, 3 short breaks of 4 and a long one of 15.
    await tester.scrollUntilVisible(find.byKey(const Key('pomodoroCycle')), 100);
    expect(find.text('Full cycle 2 h 15 min: 1 h 48 min of focus in 4 sessions'),
        findsOneWidget);

    final saved = await tester.runAsync(PomodoroSettings.load);
    expect(saved?.workMinutes, 27);
    expect(saved?.shortBreakMinutes, 4);
    expect(saved?.longBreakMinutes, 15);
  });

  noteTest('tearing off the note carries over what is not done', (tester, bloc) async {
    for (final (i, name) in ['Done one', 'Still to do', 'Not needed'].indexed) {
      bloc.add(InsertTaskEvent(index: i, name: name, id: ValueKey('t$i')));
    }
    bloc.add(SetDoneEvent(index: 0, done: true));
    bloc.add(TearOffNoteEvent());
    await settle(tester);

    expect(bloc.state.tasks, isEmpty);
    expect(find.text('Not finished on your last note'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Write again').first);
    await settle(tester);
    await tester.tap(find.byTooltip('Let go'));
    await settle(tester);

    expect(names(bloc), ['Still to do']);
    expect(bloc.state.pending, isEmpty);
    expect(find.text('Not finished on your last note'), findsNothing);

    final history = buildHistory(bloc.taskDocument!);
    expect(history.notes, hasLength(2));
    expect([for (final t in history.notes.last.tasks) (t.name, t.status)], [
      ('Done one', TaskStatus.done),
      ('Still to do', TaskStatus.carried),
      ('Not needed', TaskStatus.letGo),
    ]);
  });

  noteTest('a note from an earlier day has to be torn off first', (tester, bloc) async {
    bloc.add(InsertTaskEvent(index: 0, name: 'Yesterday', id: const ValueKey('y')));
    await settle(tester);
    expect(bloc.state.needsTearOff(), isFalse);
    expect(bloc.state.needsTearOff(nowSeconds() + 24 * 3600), isTrue);
    expect(dayOf(nowSeconds()) == dayOf(nowSeconds() + 24 * 3600), isFalse);
  });

  noteTest('history shows notes and the task list', (tester, bloc) async {
    bloc.add(InsertTaskEvent(index: 0, name: 'Read', id: const ValueKey('r')));
    bloc.add(SetDoneEvent(index: 0, done: true));
    await settle(tester);
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('in use'), findsOneWidget);
    expect(find.text('1 of 1 done'), findsOneWidget);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Done at'), findsOneWidget);
  });

  noteTest('fits a phone screen', size: const Size(360, 740), (tester, bloc) async {
    await writeThrough(tester, find.text('Write your first task'),
        'A fairly long task name that has to wrap on a phone');
    await tester.tap(find.textContaining('A fairly long'));
    await tester.pump(kDoubleTapTimeout);
    await settle(tester);
  });
}
