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
      expect(TimeEntry(deviceId: 'a', start: 100, end: 160).secondsSince(0, 500), 60);
      expect(TimeEntry(deviceId: 'a', start: 100).secondsSince(0, 130), 30);
    });

    test('ignores time before the reset', () {
      final e = TimeEntry(deviceId: 'a', start: 100, end: 160);
      expect(e.secondsSince(130, 500), 30);
      expect(e.secondsSince(200, 500), 0);
    });

    test('round-trips through JSON', () {
      final e = TimeEntry.fromJson(
          TimeEntry(deviceId: 'a', start: 1, end: null).toJson());
      expect([e.deviceId, e.start, e.end], ['a', 1, null]);
    });
  });

  test('total sums entries from every device since the reset', () {
    final task = TaskState(
      name: 't',
      id: const ValueKey('x'),
      entries: [
        TimeEntry(deviceId: 'laptop', start: 0, end: 100),
        TimeEntry(deviceId: 'phone', start: 200, end: 260),
        TimeEntry(deviceId: 'laptop', start: 300),
      ],
    );
    expect(task.totalSecondsAt(310), 170);
    task.totalResetAt = 250;
    expect(task.totalSecondsAt(310), 20);
  });
}
