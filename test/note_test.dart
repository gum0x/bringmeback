import 'package:bringmeback/bloc/history.dart';
import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/main.dart';
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
    await settle(tester);
    await writeThrough(tester, find.byTooltip('Add a task below'), 'Below');
    expect(names(bloc), ['Above', 'Middle', 'Below']);
  });

  noteTest('a task is edited in the dialog', (tester, bloc) async {
    await writeThrough(tester, find.text('Write your first task'), 'Draft');
    await tester.tap(find.byTooltip('Edit task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Final');
    await tester.tap(find.text('45 min'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(names(bloc), ['Final']);
    expect(bloc.state.tasks.single.timerLengthSeconds, 45 * 60);
  });

  noteTest('the note holds a limited number of tasks', (tester, bloc) async {
    for (var i = 0; i < noteLines + 2; i++) {
      bloc.add(InsertTaskEvent(index: i, name: 'Task $i', id: ValueKey('t$i')));
    }
    await settle(tester);
    expect(bloc.state.tasks, hasLength(noteLines));
    expect(find.text('Add a task'), findsNothing);
    expect(find.textContaining('The note is full'), findsOneWidget);
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
    await settle(tester);
  });
}
