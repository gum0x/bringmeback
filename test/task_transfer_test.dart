import 'dart:convert';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/task_transfer.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

TaskDocument newDoc() =>
    TaskDocument(CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks'));

/// A 32-hex-digit id, as [newId] makes, ending in [n].
String hexId(int n) => n.toRadixString(16).padLeft(32, '0');

int _ids = 1000;
String nextId() => hexId(_ids++);

void main() {
  test('a note exported and imported into an empty document comes back the same', () {
    final from = newDoc()..setNoteStartedAt(100);
    from.insert(0, hexId(1),
        name: 'write report',
        notes: 'two pages\nwith a chart',
        timerLengthSeconds: 1500,
        timerStartAt: 200,
        totalResetAt: 150,
        entries: [TimeEntry(start: 200, end: 500), TimeEntry(start: 600, end: 900)]);
    from.insert(1, hexId(2), name: 'call bank', timerLengthSeconds: 600, timerStartAt: 300);
    from.insert(2, hexId(3), name: 'buy milk', timerStartAt: 300);
    from.setDoneAt(hexId(3), 950);

    final file = parseTasksFile(exportTasks(from, now: 1000));
    final to = newDoc();
    final result = importTasks(to, file, noteLines: 10, newId: nextId, now: 2000);

    expect((result.added, result.waiting, result.skipped), (3, 0, 0));
    expect(to.ids, [hexId(1), hexId(2), hexId(3)]);
    for (final id in from.ids) {
      final a = from.task(id), b = to.task(id);
      expect(b.name, a.name);
      expect(b.notes, a.notes);
      expect(b.timerLengthSeconds, a.timerLengthSeconds);
      expect(b.timerStartAt, a.timerStartAt);
      expect(b.totalResetAt, a.totalResetAt);
      expect(b.doneAt, a.doneAt);
      expect([for (final e in b.entries) (e.start, e.end)],
          [for (final e in a.entries) (e.start, e.end)]);
    }
    expect(to.task(hexId(1)).totalSecondsAt(2000), 300 + 300);
    expect(to.status(hexId(3)), TaskStatus.done);
  });

  test('a running timer is exported stopped, so an imported task never runs by itself', () {
    final from = newDoc()..insert(0, hexId(1), name: 'focus', entries: [TimeEntry(start: 100)]);
    expect(from.task(hexId(1)).running, isTrue);

    final json = jsonDecode(exportTasks(from, now: 400)) as Map;
    expect((json['tasks'] as List).single['entries'], [
      {'start': 100, 'end': 400}
    ]);

    final to = newDoc();
    importTasks(to, parseTasksFile(jsonEncode(json)), noteLines: 10, newId: nextId);
    expect(to.task(hexId(1)).running, isFalse);
    expect(to.task(hexId(1)).totalSecondsAt(10000), 300);
  });

  test('imported tasks go below the tasks already on the note', () {
    final from = newDoc()
      ..insert(0, hexId(1), name: 'one')
      ..insert(1, hexId(2), name: 'two');
    final to = newDoc()..insert(0, hexId(9), name: 'what I am doing');

    importTasks(to, parseTasksFile(exportTasks(from)), noteLines: 10, newId: nextId);

    expect(to.tasks().map((t) => t.name), ['what I am doing', 'one', 'two']);
  });

  test('importing the same file twice adds nothing the second time', () {
    final from = newDoc()
      ..insert(0, hexId(1), name: 'one')
      ..insert(1, hexId(2), name: 'two');
    final file = parseTasksFile(exportTasks(from));
    final to = newDoc();

    importTasks(to, file, noteLines: 10, newId: nextId);
    final again = importTasks(to, file, noteLines: 10, newId: nextId);

    expect((again.added, again.waiting, again.skipped), (0, 0, 2));
    expect(to.ids, [hexId(1), hexId(2)]);
    expect(again.summary, 'Imported: 2 tasks already here.');
  });

  test('a task deleted here is not brought back by importing it again', () {
    final from = newDoc()..insert(0, hexId(1), name: 'one');
    final to = newDoc();
    importTasks(to, parseTasksFile(exportTasks(from)), noteLines: 10, newId: nextId);
    to.removeAt(0, hexId(1));

    final again =
        importTasks(to, parseTasksFile(exportTasks(from)), noteLines: 10, newId: nextId);

    expect(again.skipped, 1);
    expect(to.ids, isEmpty);
  });

  test('tasks that don\'t fit on the note wait with the tasks of earlier notes', () {
    final from = newDoc();
    for (var i = 0; i < 5; i++) {
      from.insert(i, hexId(i + 1), name: 'task $i');
    }
    from.setDoneAt(hexId(5), 50);
    final to = newDoc()..insert(0, hexId(9), name: 'already here');

    final result =
        importTasks(to, parseTasksFile(exportTasks(from)), noteLines: 3, newId: nextId, now: 70);

    expect(to.tasks().map((t) => t.name), ['already here', 'task 0', 'task 1']);
    // The done one that didn't fit is kept too, in the imported note, but has nothing to wait for.
    expect(to.pendingIds, [hexId(3), hexId(4)]);
    expect(to.status(hexId(5)), TaskStatus.done);
    final note = to.notes.single;
    expect(note.taskIds, [hexId(3), hexId(4), hexId(5)]);
    expect((note.startedAt, note.closedAt), (70, 70));
    expect((result.added, result.waiting, result.skipped), (2, 2, 0));
    expect(result.summary,
        'Imported: 2 tasks added to the note, 2 tasks waiting to be written again.');
  });

  test('tasks waiting from torn-off notes are exported and wait again after importing', () {
    final from = newDoc()
      ..setNoteStartedAt(100)
      ..insert(0, hexId(1), name: 'done yesterday')
      ..insert(1, hexId(2), name: 'left over');
    from.setDone(hexId(1), true);
    from.tearOff('n1', 200);
    from.insert(0, hexId(3), name: 'today');

    final json = jsonDecode(exportTasks(from)) as Map;
    expect([for (final t in json['tasks'] as List) t['name']], ['today']);
    expect([for (final t in json['waiting'] as List) t['name']], ['left over']);

    final to = newDoc();
    final result = importTasks(to, parseTasksFile(jsonEncode(json)),
        noteLines: 10, newId: nextId);

    expect(to.tasks().map((t) => t.name), ['today']);
    expect(to.pendingIds, [hexId(2)]);
    expect((result.added, result.waiting), (1, 1));

    // It can be written again on the note like any task left over.
    to.carry(hexId(2), hexId(4), 1);
    expect(to.tasks().map((t) => t.name), ['today', 'left over']);
    expect(to.pendingIds, isEmpty);
  });

  test('a hand-written file needs only names, and gets fresh ids', () {
    final file = parseTasksFile(jsonEncode({
      'format': 'bringmeback-tasks',
      'version': 1,
      'tasks': [
        {'name': 'water plants'},
        {'name': 'odd id', 'id': 'note/x'},
      ],
    }));
    final to = newDoc();
    final made = <String>[];
    importTasks(to, file, noteLines: 10, newId: () {
      final id = nextId();
      made.add(id);
      return id;
    }, now: 500);

    expect(to.ids, made);
    expect(to.tasks().map((t) => t.name), ['water plants', 'odd id']);
    expect(to.task(made.first).timerLengthSeconds, 20 * 60);
    expect(to.task(made.first).timerStartAt, 500);
    expect(to.noteStartedAt, isNull, reason: 'an id can\'t write into the note\'s own fields');
  });

  group('a file that is not a tasks file is refused', () {
    void refused(Object? json, String message) {
      final text = json is String ? json : jsonEncode(json);
      expect(() => parseTasksFile(text),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(message))));
    }

    test('not JSON', () => refused('{not json', 'not a bringmeback tasks file'));
    test('another kind of JSON', () => refused({'tasks': []}, 'not a bringmeback tasks file'));
    test('a newer version', () {
      refused({'format': 'bringmeback-tasks', 'version': 2, 'tasks': []}, 'newer version');
    });
    test('a task without a name', () {
      refused({
        'format': 'bringmeback-tasks',
        'version': 1,
        'tasks': [
          {'notes': 'x'}
        ]
      }, 'no name');
    });
    test('a field of the wrong type', () {
      refused({
        'format': 'bringmeback-tasks',
        'version': 1,
        'tasks': [
          {'name': 'x', 'timerLengthSeconds': '20'}
        ]
      }, 'wrong type');
    });
    test('a time entry that never ends', () {
      refused({
        'format': 'bringmeback-tasks',
        'version': 1,
        'tasks': [
          {
            'name': 'x',
            'entries': [
              {'start': 10, 'end': null}
            ]
          }
        ]
      }, 'time entry');
    });
    test('too many tasks', () {
      refused({
        'format': 'bringmeback-tasks',
        'version': 1,
        'tasks': [for (var i = 0; i <= maxImportedTasks; i++) {'name': '$i'}]
      }, 'too many');
    });
  });
}
