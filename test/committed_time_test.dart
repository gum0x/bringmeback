import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/timer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

int at(int hour, int minute, [int second = 0]) =>
    DateTime(2026, 11, 13, hour, minute, second).millisecondsSinceEpoch ~/ 1000;

TaskState task(String id,
        {int minutes = 20, bool done = false, List<TimeEntry>? entries}) =>
    TaskState(
      name: id,
      id: ValueKey(id),
      timerLengthSeconds: minutes * 60,
      entries: entries,
      doneAt: done ? at(9, 0) : null,
    );

void main() {
  test('the finish rounds up to the next quarter hour', () {
    expect(roundUpToQuarterHour(at(10, 0)), at(10, 0));
    expect(roundUpToQuarterHour(at(10, 0, 1)), at(10, 15));
    expect(roundUpToQuarterHour(at(10, 14, 59)), at(10, 15));
    expect(roundUpToQuarterHour(at(10, 31)), at(10, 45));
    expect(roundUpToQuarterHour(at(10, 50)), at(11, 0));
  });

  test('committed time adds up every task, and the finish what is left', () {
    final state = TasksState(tasks: [
      task('done', minutes: 30, done: true),
      // Worked on for 10 of its 25 minutes, from 10:00 to 10:10.
      task('current', minutes: 25, entries: [
        TimeEntry(start: at(10, 0), end: at(10, 10)),
      ]),
      task('next', minutes: 45),
    ]);
    expect(state.committedSeconds, (30 + 25 + 45) * 60);
    // 15 + 45 minutes left from 10:20 is 11:20, shown as 11:30.
    expect(state.secondsLeftAt(at(10, 20)), (15 + 45) * 60);
    expect(state.finishAt(at(10, 20)), at(11, 30));
    expect(state.overCommitted, isFalse);
  });

  test('a task over its time adds nothing to what is left', () {
    final state = TasksState(tasks: [
      task('over', minutes: 10, entries: [
        TimeEntry(start: at(10, 0), end: at(10, 30)),
      ]),
    ]);
    expect(state.secondsLeftAt(at(11, 0)), 0);
    expect(state.finishAt(at(11, 0)), isNull);
  });

  test('more than the note holds is over committed', () {
    final tasks = [for (var i = 0; i < 5; i++) task('t$i', minutes: 60)];
    expect(
        TasksState(tasks: tasks, noteMinutes: 5 * 60).overCommitted, isFalse);
    expect(TasksState(tasks: tasks, noteMinutes: 4 * 60).overCommitted, isTrue);
  });

  test('minutes read as hours and minutes', () {
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(120), '2 h');
    expect(formatMinutes(130), '2 h 10 min');
  });
}
