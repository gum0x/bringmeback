// End-to-end tests: they launch the real app on a device (Linux desktop or Chrome in CI) and drive
// it through the UI the way a person would, including saving to and loading from real storage.
//
//   flutter test integration_test -d linux
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d web-server
import 'package:bringmeback/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final addOnTopButton = find.widgetWithText(FloatingActionButton, 'New task');
final taskCards = find.byType(Task);

Finder inTask(int index, Finder finder) =>
    find.descendant(of: taskCards.at(index), matching: finder);

Finder nameField(int index) => inTask(
    index,
    find.byWidgetPredicate((w) =>
        w is TextField &&
        w.decoration?.hintText == 'What are you working on?'));

Finder minutesField(int index) => inTask(
    index,
    find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Minutes'));

Finder taskButton(int index, IconData icon) =>
    inTask(index, find.widgetWithIcon(IconButton, icon));

/// The play/pause button, which only the top task has.
Finder playPause(int index) => inTask(
    index,
    find.byWidgetPredicate((w) =>
        w is IconButton &&
        w.icon is Icon &&
        {Icons.play_arrow, Icons.pause}.contains((w.icon as Icon).icon)));

/// Picks an entry from a task's "More actions" menu.
Future<void> taskMenu(WidgetTester tester, int index, String entry) async {
  await tester.tap(inTask(index, find.byTooltip('More actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

String nameOf(WidgetTester tester, int index) =>
    tester.widget<TextField>(nameField(index)).controller!.text;

String minutesText(WidgetTester tester, int index) =>
    tester.widget<TextField>(minutesField(index)).controller!.text;

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

Future<void> typeName(WidgetTester tester, int index, String name) async {
  await tester.enterText(nameField(index), name);
  // Names are saved after a 500 ms pause in typing.
  await wait(tester, const Duration(milliseconds: 800));
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
    expect(find.text('No tasks yet'), findsOneWidget);

    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    expect(taskCards, findsOneWidget);
    expect(
        seconds(countdown(tester, 0)), inInclusiveRange(20 * 60 - 3, 20 * 60));
    expect(taskButton(0, Icons.pause), findsOneWidget);

    await typeName(tester, 0, 'Write the report');
    await wait(tester, const Duration(milliseconds: 2500));
    expect(seconds(countdown(tester, 0)), lessThan(20 * 60 - 1));
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(2));

    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), isEmpty);
    expect(nameOf(tester, 1), 'Write the report');
    // Only the top task runs, and only it has a play/pause button.
    expect(taskButton(0, Icons.pause), findsOneWidget);
    expect(playPause(1), findsNothing);
    final belowTotal = total(tester, 1);
    await wait(tester, const Duration(milliseconds: 2000));
    expect(total(tester, 1), belowTotal);

    // Finishing the top task hands the work to the next one.
    await tester.tap(taskButton(0, Icons.check_circle_outline));
    await tester.pumpAndSettle();
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Write the report');
    expect(taskButton(0, Icons.pause), findsOneWidget);
    expect(find.text('Task done'), findsOneWidget);
  });

  testWidgets('a task marked done can be brought back', (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'Second');
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'First');

    await tester.tap(taskButton(0, Icons.check_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('Done: First'), findsOneWidget);
    expect(nameOf(tester, 0), 'Second');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'First');
    expect(taskButton(0, Icons.pause), findsOneWidget);
    expect(playPause(1), findsNothing);
  });

  testWidgets('moving a task to the top makes it the running one',
      (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'Later');
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'Now');

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
    expect(taskButton(0, Icons.pause), findsOneWidget);
    expect(playPause(1), findsNothing);
  });

  testWidgets('pausing a task stops its clocks and resuming restarts them',
      (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await wait(tester, const Duration(milliseconds: 1500));

    await tester.tap(taskButton(0, Icons.pause));
    await tester.pumpAndSettle();
    expect(taskButton(0, Icons.play_arrow), findsOneWidget);
    final pausedCountdown = countdown(tester, 0);
    final pausedTotal = total(tester, 0);

    await wait(tester, const Duration(milliseconds: 2500));
    expect(countdown(tester, 0), pausedCountdown);
    expect(total(tester, 0), pausedTotal);

    await tester.tap(taskButton(0, Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(taskButton(0, Icons.pause), findsOneWidget);
    await wait(tester, const Duration(milliseconds: 2500));
    expect(seconds(total(tester, 0)), greaterThan(seconds(pausedTotal)));
  });

  testWidgets('the countdown length can be changed', (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();

    // Clearing the field on the way to a new number is fine; the change applies on Enter.
    await tester.enterText(minutesField(0), '');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(minutesField(0), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(seconds(countdown(tester, 0)), inInclusiveRange(5 * 60 - 3, 5 * 60));
    expect(minutesText(tester, 0), '5');

    // An invalid length is dropped and the field shows the current one again.
    await tester.enterText(minutesField(0), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(minutesText(tester, 0), '5');
    expect(seconds(countdown(tester, 0)), inInclusiveRange(5 * 60 - 5, 5 * 60));
  });

  testWidgets('the countdown can be restarted and the total reset',
      (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await wait(tester, const Duration(milliseconds: 2500));
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(2));

    await tester.tap(taskButton(0, Icons.pause));
    await tester.pumpAndSettle();
    await taskMenu(tester, 0, 'Restart countdown');
    expect(seconds(countdown(tester, 0)), 20 * 60);
    await taskMenu(tester, 0, 'Reset total time');
    expect(seconds(total(tester, 0)), 0);
  });

  testWidgets('tasks can be added below another task and deleted',
      (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'First');

    await tester.tap(taskButton(0, Icons.playlist_add));
    await tester.pumpAndSettle();
    await typeName(tester, 1, 'Second');
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'First');
    // A task added below waits its turn instead of starting.
    expect(playPause(1), findsNothing);

    await taskMenu(tester, 0, 'Delete task');
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Second');
    // Work carries on with the task that moved up.
    expect(taskButton(0, Icons.pause), findsOneWidget);

    // The deletion can be undone, and the task comes back where it was.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'First');
    expect(nameOf(tester, 1), 'Second');
    expect(taskButton(0, Icons.pause), findsOneWidget);
    expect(playPause(1), findsNothing);

    await taskMenu(tester, 1, 'Delete task');
    await taskMenu(tester, 0, 'Delete task');
    expect(taskCards, findsNothing);
  });

  testWidgets('keyboard shortcuts add and remove tasks', (tester) async {
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
    expect(taskCards, findsOneWidget);
    await typeName(tester, 0, 'Top');

    await press([
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.keyN
    ]);
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Top');

    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyN]);
    expect(taskCards, findsNWidgets(3));
    expect(nameOf(tester, 1), 'Top');

    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyD]);
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Top');

    // Alt variants, for browsers that keep Ctrl+N and Ctrl+D.
    await press([LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyN]);
    expect(taskCards, findsNWidgets(3));
    await press([LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyD]);
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Top');
  });

  testWidgets('tasks and their timers survive a restart', (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'Paused task');
    await tester.tap(taskButton(0, Icons.pause));
    await tester.pumpAndSettle();

    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'Running task');
    await wait(tester, const Duration(milliseconds: 1500));

    await restartApp(tester);
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'Running task');
    expect(nameOf(tester, 1), 'Paused task');
    expect(taskButton(0, Icons.pause), findsOneWidget);
    expect(playPause(1), findsNothing);
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(1));
  });
}
