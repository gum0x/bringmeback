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

final addOnTopButton = find.widgetWithIcon(ElevatedButton, Icons.add);
final taskCards = find.byType(Task);

Finder inTask(int index, Finder finder) =>
    find.descendant(of: taskCards.at(index), matching: finder);

Finder nameField(int index) => inTask(
    index,
    find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == 'Task description here'));

Finder minutesField(int index) => inTask(
    index,
    find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'min'));

Finder taskButton(int index, IconData icon) =>
    inTask(index, find.widgetWithIcon(FloatingActionButton, icon));

String nameOf(WidgetTester tester, int index) =>
    tester.widget<TextField>(nameField(index)).controller!.text;

/// The clock as shown on screen, e.g. "00 : 19 : 58". The first clock in a task is the countdown,
/// the second the total time tracked.
String clockText(WidgetTester tester, int index, int clock) {
  final widget = inTask(index, find.byType(TaskWidget)).at(clock);
  return tester
      .widgetList<Text>(
          find.descendant(of: widget, matching: find.byType(Text)))
      .map((t) => t.data)
      .join(' ');
}

String countdown(WidgetTester tester, int index) => clockText(tester, index, 0);
String total(WidgetTester tester, int index) => clockText(tester, index, 1);

/// "00 : 19 : 58" as seconds. Timing checks allow a few seconds of slack for slow machines.
int seconds(String clock) =>
    clock.split(' : ').map(int.parse).fold(0, (sum, part) => sum * 60 + part);

/// Lets real time pass while the app keeps rendering, so its timers tick.
Future<void> wait(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> startApp(WidgetTester tester) async {
  await tester.pumpWidget(App());
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

    await tester.enterText(minutesField(0), '5');
    await tester.pumpAndSettle();
    expect(seconds(countdown(tester, 0)), inInclusiveRange(5 * 60 - 3, 5 * 60));
  });

  testWidgets('tasks can be added below another task and deleted',
      (tester) async {
    await startApp(tester);
    await tester.tap(addOnTopButton);
    await tester.pumpAndSettle();
    await typeName(tester, 0, 'First');

    await tester.tap(taskButton(0, Icons.add));
    await tester.pumpAndSettle();
    await typeName(tester, 1, 'Second');
    expect(taskCards, findsNWidgets(2));
    expect(nameOf(tester, 0), 'First');
    // A task added below waits its turn instead of starting.
    expect(taskButton(1, Icons.play_arrow), findsOneWidget);

    await tester.tap(taskButton(0, Icons.delete));
    await tester.pumpAndSettle();
    expect(taskCards, findsOneWidget);
    expect(nameOf(tester, 0), 'Second');
    // The task that moves to the top starts running.
    expect(taskButton(0, Icons.pause), findsOneWidget);
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
    expect(taskButton(1, Icons.play_arrow), findsOneWidget);
    expect(seconds(total(tester, 0)), greaterThanOrEqualTo(1));
  });
}
