// End-to-end tests: they launch the real app on a device (Linux desktop or Chrome in CI) and drive
// it through the UI the way a person would, including saving to and loading from real storage.
//
//   flutter test integration_test -d linux
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d web-server
import 'dart:convert';

import 'package:bringmeback/main.dart';
import 'package:bringmeback/sync/pairing.dart';
import 'package:bringmeback/sync/sync_status.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final addOnTopButton = find.widgetWithText(FloatingActionButton, 'New task');
final taskCards = find.byType(TaskLine);

Finder inTask(int index, Finder finder) =>
    find.descendant(of: taskCards.at(index), matching: finder);

Finder checkbox(int index) => inTask(index, find.byType(Checkbox));

final pauseButton = find.widgetWithIcon(IconButton, Icons.pause);
final resumeButton = find.widgetWithIcon(IconButton, Icons.play_arrow);

/// Only the current task shows its clocks.
Finder clocksOf(int index) => inTask(index, find.byType(TaskClock));

/// Checks that the task at [index] is the current one and its timer runs.
void expectRunning(int index) {
  expect(clocksOf(index), findsOneWidget);
  expect(pauseButton, findsOneWidget);
}

/// Selects a task by tapping its name, so the bottom bar acts on it.
Future<void> select(WidgetTester tester, int index) async {
  await tester.tap(inTask(index, find.byType(StrikeText)));
  // A tap waits to see whether it is a double tap.
  await wait(tester, const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Opens a task in the dialog with a double tap.
Future<void> doubleTapTask(WidgetTester tester, int index) async {
  final name = inTask(index, find.byType(StrikeText));
  await tester.tap(name);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(name);
  await tester.pumpAndSettle();
}

/// Selects a task, then picks an entry from the bottom bar's "More actions" menu.
Future<void> taskMenu(WidgetTester tester, int index, String entry) async {
  await select(tester, index);
  await tester.tap(find.byTooltip('More actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

String nameOf(WidgetTester tester, int index) =>
    tester.widget<StrikeText>(inTask(index, find.byType(StrikeText))).text;

bool doneAt(WidgetTester tester, int index) =>
    tester.widget<Checkbox>(checkbox(index)).value!;

/// Fills in the task dialog and saves it.
Future<void> fillTaskDialog(WidgetTester tester, String name,
    {String? minutes, String save = 'Add'}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Task'), name);
  if (minutes != null) {
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), minutes);
  }
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, save));
  await tester.pumpAndSettle();
}

/// Writes a task through the dialog that [opener] opens: on top with New task by default.
Future<void> writeTask(WidgetTester tester, String name,
    {Finder? opener, String? minutes}) async {
  await tester.tap(opener ?? addOnTopButton);
  await tester.pumpAndSettle();
  await fillTaskDialog(tester, name, minutes: minutes);
}

/// A clock as shown on screen, e.g. "Left 19:58" or "Total 00:02". The first line of a task's
/// clock is the countdown, the second the total time tracked.
String clockText(WidgetTester tester, int index, int line) {
  final clock = inTask(index, find.byType(TaskClock));
  return tester
      .widgetList<Text>(find.descendant(of: clock, matching: find.byType(Text)))
      .elementAt(line)
      .data!;
}

String countdown(WidgetTester tester, int index) => clockText(tester, index, 0);
String total(WidgetTester tester, int index) => clockText(tester, index, 1);

/// "Left 19:58" or "Total 1:00:02" as seconds. Timing checks allow a few seconds of slack for slow
/// machines.
int seconds(String clock) => RegExp(r'[\d:]+')
    .firstMatch(clock)!
    .group(0)!
    .split(':')
    .map(int.parse)
    .fold(0, (sum, part) => sum * 60 + part);

/// Lets real time pass while the app keeps rendering, so its timers tick.
Future<void> wait(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> startApp(WidgetTester tester) async {
  await tester.pumpWidget(const App());
  await tester.pumpAndSettle();
}

/// Replaces the app with a fresh one, as if it was closed and opened again.
Future<void> restartApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await startApp(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  tearDown(() async {
    // Wait for pending saves, so they don't leak into the next test.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  testWidgets('a new task starts on top and its timer runs', (tester) async {
    await startApp(tester);
    expect(taskCards, findsNothing);
    expect(find.text('Write your first task'), findsOneWidget);

    await writeTask(tester, 'Write the report');
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Write the report');
    expect(
        seconds(countdown(tester, 0)), inInclusiveRange(20 * 60 - 3, 20 * 60));
    expectRunning(0);

    await wait(tester, const Duration(milliseconds: 2500));
    expect(seconds(countdown(tester, 0)), lessThan(20 * 60 - 1));
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(2));

    // An interruption goes on top and takes the timer.
    await writeTask(tester, 'Answer the phone');
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Answer the phone');
    expect(nameOf(tester, 1), 'Write the report');
    expectRunning(0);
    expect(clocksOf(1), findsNothing);
  });

  testWidgets('a task checked off stays on the note and hands the timer on',
      (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Second');
    await writeTask(tester, 'First');

    await tester.tap(checkbox(0));
    await tester.pumpAndSettle();
    expect(taskCards, findsNWidgets(2));
    expect(doneAt(tester, 0), isTrue);
    expect(nameOf(tester, 0), 'First');
    // The next unchecked task is now the current one, and it runs.
    expect(clocksOf(0), findsNothing);
    expectRunning(1);
    final doneTotal = total(tester, 1);

    await tester.tap(checkbox(1));
    await tester.pumpAndSettle();
    expect(find.text('ALL DONE'), findsOneWidget);
    expect(clocksOf(1), findsNothing);
    await wait(tester, const Duration(milliseconds: 1500));

    // Unchecking takes the task back up as the current one.
    await tester.tap(checkbox(1));
    await tester.pumpAndSettle();
    expect(find.text('ALL DONE'), findsNothing);
    expect(doneAt(tester, 1), isFalse);
    expect(clocksOf(1), findsOneWidget);
    expect(seconds(total(tester, 1)), greaterThanOrEqualTo(seconds(doneTotal)));
  });

  testWidgets('dragging an unchecked task to the top makes it the running one',
      (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Later');
    await writeTask(tester, 'Now');

    final handle = inTask(1, find.byIcon(Icons.drag_indicator));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(nameOf(tester, 0), 'Later');
    expect(nameOf(tester, 1), 'Now');
    expectRunning(0);
    expect(clocksOf(1), findsNothing);
  });

  testWidgets('pausing a task stops its clocks and resuming restarts them',
      (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Focus');
    await wait(tester, const Duration(milliseconds: 1500));

    await tester.tap(pauseButton);
    await tester.pumpAndSettle();
    expect(resumeButton, findsOneWidget);
    final pausedCountdown = countdown(tester, 0);
    final pausedTotal = total(tester, 0);

    await wait(tester, const Duration(milliseconds: 2500));
    expect(countdown(tester, 0), pausedCountdown);
    expect(total(tester, 0), pausedTotal);

    await tester.tap(resumeButton);
    await tester.pumpAndSettle();
    expectRunning(0);
    await wait(tester, const Duration(milliseconds: 2500));
    expect(seconds(total(tester, 0)), greaterThan(seconds(pausedTotal)));
  });

  testWidgets('the task dialog sets the name and countdown length', (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Short one', minutes: '5');
    expect(seconds(countdown(tester, 0)), inInclusiveRange(5 * 60 - 3, 5 * 60));

    await doubleTapTask(tester, 0);
    // A length that isn't a number of minutes can't be saved.
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '0');
    await tester.pump();
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed,
        isNull);
    await tester.tap(find.text('45 min'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Details'), 'First line\nSecond line');
    await fillTaskDialog(tester, 'Long one', save: 'Save');
    expect(nameOf(tester, 0), 'Long one');
    expect(inTask(0, find.text('First line\nSecond line')), findsOneWidget);
    expect(seconds(countdown(tester, 0)), inInclusiveRange(45 * 60 - 3, 45 * 60));
  });

  testWidgets('the countdown can be restarted and the total reset',
      (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Timed');
    await wait(tester, const Duration(milliseconds: 2500));
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(2));

    await tester.tap(pauseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restart countdown'));
    await tester.pumpAndSettle();
    expect(seconds(countdown(tester, 0)), 20 * 60);
    await taskMenu(tester, 0, 'Reset total time');
    expect(seconds(total(tester, 0)), 0);
  });

  testWidgets('tasks can be written above and below another task and deleted',
      (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Middle');

    // A task just written is selected, which shows its (+) buttons.
    await writeTask(tester, 'Last', opener: inTask(0, find.byTooltip('Add a task below')));
    await select(tester, 0);
    await writeTask(tester, 'First', opener: inTask(0, find.byTooltip('Add a task above')));
    expect([for (var i = 0; i < 3; i++) nameOf(tester, i)], ['First', 'Middle', 'Last']);
    // Written above the current task, First takes over the timer.
    expectRunning(0);

    await taskMenu(tester, 0, 'Delete task');
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Middle');
    // Work carries on with the task that moved up.
    expectRunning(0);

    // The deletion can be undone, and the task comes back where it was.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(taskCards, findsNWidgets(3));
    expect(nameOf(tester, 0), 'First');
    expectRunning(0);
    expect(clocksOf(1), findsNothing);
  });

  testWidgets('keyboard shortcuts add, check off and remove tasks', (tester) async {
    await startApp(tester);

    Future<void> press(List<LogicalKeyboardKey> keys) async {
      for (final key in keys) {
        await tester.sendKeyDownEvent(key);
      }
      for (final key in keys.reversed) {
        await tester.sendKeyUpEvent(key);
      }
      await tester.pumpAndSettle();
    }

    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyN]);
    await fillTaskDialog(tester, 'Top');
    expect(taskCards, findsOneWidget);

    await press([
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.keyN
    ]);
    await fillTaskDialog(tester, 'Next');
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Top');
    expect(nameOf(tester, 1), 'Next');

    // The task just written is selected: check it off and back.
    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.enter]);
    expect(doneAt(tester, 1), isTrue);
    await press([LogicalKeyboardKey.altLeft, LogicalKeyboardKey.enter]);
    expect(doneAt(tester, 1), isFalse);

    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyD]);
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Top');

    // Alt variants, for browsers that keep Ctrl+N and Ctrl+D.
    await press([LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyN]);
    await fillTaskDialog(tester, 'Interruption');
    expect(taskCards, findsNWidgets(2));
    await press([LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyD]);
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Top');
  });

  testWidgets('tasks and their timers survive a restart', (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Done task');
    await tester.tap(checkbox(0));
    await tester.pumpAndSettle();
    await writeTask(tester, 'Running task');
    await wait(tester, const Duration(milliseconds: 1500));

    await restartApp(tester);
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Running task');
    expect(nameOf(tester, 1), 'Done task');
    expect(doneAt(tester, 1), isTrue);
    expectRunning(0);
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(1));
  });

  testWidgets('a fresh note carries over what was not done', (tester) async {
    await startApp(tester);
    await writeTask(tester, 'Still to do');
    await writeTask(tester, 'Finished');
    await tester.tap(checkbox(0));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Note actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tear off and start a fresh note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tear it off'));
    await tester.pumpAndSettle();

    expect(taskCards, findsNothing);
    expect(find.text('Not finished on your last note'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Write again'));
    await tester.pumpAndSettle();
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Still to do');
    expect(find.text('Not finished on your last note'), findsNothing);

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('written again'), findsOneWidget);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Done at'), findsOneWidget);
  });

  // On the web this runs Symbolon's JavaScript binding, and elsewhere its native library.
  testWidgets('devices can start a group and run the handshake', (tester) async {
    await startApp(tester);
    await tester.tap(find.byType(SyncStatusButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a new group'));
    await tester.pumpAndSettle();
    expect(find.text('Group fingerprint'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}\n')), findsOneWidget);

    await loadSymbolon();
    final keys = PairingCode.generate().deriveKeys();
    final a = DeviceIdentity.generate(), b = DeviceIdentity.generate();
    final prologue = utf8.encode('e2e');
    final initiator = symbolon.initiator(a.key, b.publicKey, keys.inner, prologue);
    final responder = symbolon.responder(b.key, keys.inner, prologue);
    responder.readMessage(initiator.writeMessage([]));
    initiator.readMessage(responder.writeMessage([]));
    final sent = initiator.intoChannel().encrypt(utf8.encode('hello'));
    expect(utf8.decode(responder.intoChannel().decrypt(sent)), 'hello');
  });
}
