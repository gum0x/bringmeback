import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('newId', () {
    test('is 32 hex characters and unique', () {
      final ids = List.generate(1000, (_) => newId());
      expect(ids.every((id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id)), isTrue);
      expect(ids.toSet().length, ids.length);
    });
  });

  group('TimeEntry', () {
    test('counts closed and open entries', () {
      expect(TimeEntry(start: 100, end: 160).secondsSince(0, 500), 60);
      expect(TimeEntry(start: 100).secondsSince(0, 130), 30);
    });

    test('ignores time before the reset', () {
      final e = TimeEntry(start: 100, end: 160);
      expect(e.secondsSince(130, 500), 30);
      expect(e.secondsSince(200, 500), 0);
    });

    test('round-trips through JSON', () {
      final e = TimeEntry.fromJson(TimeEntry(start: 1).toJson());
      expect([e.start, e.end], [1, null]);
    });
  });

  group('TaskState', () {
    TaskState task(List<TimeEntry> entries) =>
        TaskState(name: 't', id: const ValueKey('x'), entries: entries);

    test('total sums entries since the reset', () {
      final t = task([
        TimeEntry(start: 0, end: 100),
        TimeEntry(start: 200, end: 260),
        TimeEntry(start: 300),
      ]);
      expect(t.totalSecondsAt(310), 170);
      t.totalResetAt = 250;
      expect(t.totalSecondsAt(310), 20);
    });

    test('countdown is derived from the same entries', () {
      final t = task([TimeEntry(start: 0, end: 100), TimeEntry(start: 200)])
        ..timerLengthSeconds = 300
        ..timerStartAt = 50;
      expect(t.remainingSecondsAt(250), 300 - 50 - 50);
      expect(t.remainingSecondsAt(600), -150);
    });

    test('running is whether an entry is open', () {
      final t = task([]);
      expect(t.running, isFalse);
      t.running = true;
      expect(t.running, isTrue);
      expect(t.entries.length, 1);
      t.running = true;
      expect(t.entries.length, 1);
      t.running = false;
      expect(t.running, isFalse);
      expect(t.entries.single.end, isNotNull);
    });

    test('copyWith keeps the running state unless told otherwise', () {
      final t = task([TimeEntry(start: 0)]);
      expect(t.copyWith(name: 'n').running, isTrue);
      expect(t.copyWith(running: false).running, isFalse);
    });
  });
}
