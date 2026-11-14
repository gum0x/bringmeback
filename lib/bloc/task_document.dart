import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';

import 'tasks_bloc.dart';

/// The task list as a CRDT document, so copies on different devices converge when they exchange
/// changes.
///
/// - `order`: task ids in a movable list, which keeps each task's identity across reorders.
/// - `fields`: one last-writer-wins map for every task field, keyed `<taskId>/<field>`. Time entries
///   are keyed `<taskId>/e/<start>` with the end as value (null while running).
///
/// The order is today's note: the tasks written on it, done or not. A task checked off stays in the
/// order with `<taskId>/doneAt` set, struck through. A deleted task leaves the order but keeps its
/// fields, with `<taskId>/deletedAt` set, so its history stays in the document. (Before notes, a done
/// task left the order too; such tasks still read as done.)
///
/// When a note is torn off, its tasks leave the order and the note is kept as `note/<noteId>/ids`
/// (task ids joined by commas, in order), `note/<noteId>/startedAt` and `note/<noteId>/closedAt`.
/// Its unfinished tasks wait to be written again on the new note (a new task with
/// `<newId>/carriedFrom` and `<oldId>/carriedTo`) or let go (`<oldId>/letGoAt`).
/// `current/startedAt` is when the note in the order was started.
///
/// The backlog holds tasks kept for later, off the note: a task with `<taskId>/backlogAt` set and
/// not in the order. Writing one on the note puts its id in the order and clears `backlogAt`; an
/// unfinished task of a torn-off note moved to the backlog is written as a new task instead, as
/// when it is carried.
///
/// `<taskId>/pomodoro` is where the task's Pomodoro is, as a `PomodoroRecord` in JSON, so a focus
/// picks up where it was on any device.
///
/// Pauses are logged as hidden tasks: fields with `<taskId>/kind` set to `pause` and one time entry,
/// never in the order.
class TaskDocument {
  final CRDTDocument doc;
  final CRDTFugueMovableListHandler<String> _order;
  final CRDTMapHandler<Object?> _fields;

  TaskDocument(this.doc)
      : _order = CRDTFugueMovableListHandler<String>(doc, 'order',
            handlerType: 'bmb.order'),
        _fields =
            CRDTMapHandler<Object?>(doc, 'fields', handlerType: 'bmb.fields');

  /// Task ids in order. Another device's changes are untrusted, so anything that isn't a string, or
  /// a list that doesn't read, counts as no task.
  List<String> get ids {
    try {
      return [for (final Object? id in _order.value) if (id is String) id];
    } on Object {
      return const [];
    }
  }

  /// Every field, or none if the map doesn't read.
  Map<String, Object?> get _values {
    try {
      return _fields.value;
    } on Object {
      return const {};
    }
  }

  /// Reads a task. Fields of the wrong type, which only another device's bad changes could write,
  /// read as their defaults.
  TaskState task(String id, {bool inFocus = false}) {
    final fields = _values;
    T field<T>(String name, T fallback) => switch (fields['$id/$name']) { T v => v, _ => fallback };
    final entryPrefix = '$id/e/';
    final entries = [
      for (final MapEntry(:key, :value) in fields.entries)
        if (key.startsWith(entryPrefix) && (value == null || value is int))
          if (int.tryParse(key.substring(entryPrefix.length)) case final start?)
            TimeEntry(start: start, end: value as int?),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return TaskState(
      name: field<String>('name', ''),
      notes: field<String>('notes', ''),
      doneAt: fields['$id/doneAt'] is int ? fields['$id/doneAt'] as int : null,
      carriedFrom: field<String?>('carriedFrom', null),
      id: ValueKey<String>(id),
      timerLengthSeconds: field<int>('timerLength', 20 * 60),
      timerStartAt: field<int>('timerStartAt', 0),
      totalResetAt: field<int>('totalResetAt', 0),
      entries: entries,
      inFocus: inFocus,
      pomodoro: field<String?>('pomodoro', null),
    );
  }

  List<TaskState> tasks({String? focusId}) =>
      [for (final id in ids) task(id, inFocus: id == focusId)];

  /// Adds a task at [index] with the given fields; [running] opens its first time entry now.
  void insert(int index, String id,
      {String name = '',
      String notes = '',
      int timerLengthSeconds = 20 * 60,
      int? timerStartAt,
      int totalResetAt = 0,
      List<TimeEntry> entries = const [],
      bool running = false}) {
    doc.runInTransaction(() {
      _order.insert(index, id);
      _fields
        ..set('$id/name', name)
        ..set('$id/timerLength', timerLengthSeconds)
        ..set('$id/timerStartAt', timerStartAt ?? nowSeconds())
        ..set('$id/totalResetAt', totalResetAt);
      if (notes.isNotEmpty) _fields.set('$id/notes', notes);
      for (final e in entries) {
        _fields.set('$id/e/${e.start}', e.end);
      }
      if (running && !entries.any((e) => e.end == null)) {
        _fields.set('$id/e/${nowSeconds()}', null);
      }
    });
  }

  /// Deletes the task at [index] from the note, keeping its fields and when it was deleted.
  void removeAt(int index, String id) => doc.runInTransaction(() {
        _fields.set('$id/deletedAt', nowSeconds());
        _order.delete(index);
      });

  /// Puts a deleted task back at [index]; its fields never left the document.
  void restore(int index, String id) => doc.runInTransaction(() {
        _order.insert(index, id);
        if (_values['$id/deletedAt'] != null) _fields.set('$id/deletedAt', null);
      });

  /// Checks a task off, keeping when it was finished, or unchecks it. It stays on the note either way.
  void setDone(String id, bool done) =>
      _fields.set('$id/doneAt', done ? nowSeconds() : null);

  int? doneAt(String id) => switch (_values['$id/doneAt']) { int v => v, _ => null };

  /// When the note in the order was started, or null in a document from before notes.
  int? get noteStartedAt => switch (_values['current/startedAt']) { int v => v, _ => null };

  void setNoteStartedAt(int at) => _fields.set('current/startedAt', at);

  /// Every note torn off, oldest first.
  List<NoteRecord> get notes {
    final fields = _values;
    final notes = <NoteRecord>[];
    for (final MapEntry(:key, :value) in fields.entries) {
      if (!key.startsWith('note/') || !key.endsWith('/ids') || value is! String) continue;
      final id = key.substring('note/'.length, key.length - '/ids'.length);
      final startedAt = fields['note/$id/startedAt'];
      final closedAt = fields['note/$id/closedAt'];
      if (startedAt is! int || closedAt is! int) continue;
      notes.add(NoteRecord(
          id: id,
          startedAt: startedAt,
          closedAt: closedAt,
          taskIds: [for (final t in value.split(',')) if (t.isNotEmpty) t]));
    }
    return notes..sort((a, b) => a.closedAt.compareTo(b.closedAt));
  }

  /// Tears off the note in the order: keeps it as note [noteId] and starts an empty one at [at].
  void tearOff(String noteId, int at) => doc.runInTransaction(() {
        final ids = this.ids;
        for (final id in ids) {
          setRunning(id, false);
        }
        _fields
          ..set('note/$noteId/ids', ids.join(','))
          ..set('note/$noteId/startedAt', noteStartedAt ?? at)
          ..set('note/$noteId/closedAt', at)
          ..set('current/startedAt', at);
        for (var i = ids.length - 1; i >= 0; i--) {
          _order.delete(i);
        }
      });

  /// Writes the unfinished task [fromId] of an earlier note again at [index], as task [newId].
  void carry(String fromId, String newId, int index) => doc.runInTransaction(() {
        final from = task(fromId);
        insert(index, newId,
            name: from.name,
            notes: from.notes,
            timerLengthSeconds: from.timerLengthSeconds);
        _fields
          ..set('$newId/carriedFrom', fromId)
          ..set('$fromId/carriedTo', newId);
      });

  /// Lets go of the unfinished task [id] of an earlier note: it is not written again.
  void letGo(String id) => _fields.set('$id/letGoAt', nowSeconds());

  /// Keeps a new task [id] in the backlog, off the note.
  void addToBacklog(String id,
      {String name = '', String notes = '', int timerLengthSeconds = 20 * 60}) {
    doc.runInTransaction(() {
      _fields
        ..set('$id/name', name)
        ..set('$id/timerLength', timerLengthSeconds)
        ..set('$id/timerStartAt', nowSeconds())
        ..set('$id/totalResetAt', 0)
        ..set('$id/backlogAt', nowSeconds());
      if (notes.isNotEmpty) _fields.set('$id/notes', notes);
    });
  }

  /// Lets go of a new task [id] on purpose, without writing it on the note: History keeps it as let
  /// go on the day it was dropped.
  void letGoNew(String id, {String name = '', String notes = ''}) {
    doc.runInTransaction(() {
      _fields
        ..set('$id/name', name)
        ..set('$id/timerLength', 20 * 60)
        ..set('$id/timerStartAt', nowSeconds())
        ..set('$id/totalResetAt', 0)
        ..set('$id/letGoAt', nowSeconds());
      if (notes.isNotEmpty) _fields.set('$id/notes', notes);
    });
  }

  /// Moves the unfinished task [id] of an earlier note to the backlog.
  void moveToBacklog(String id) => _fields.set('$id/backlogAt', nowSeconds());

  /// Writes the backlog task [id] on the note at [index]. A task from a torn-off note is written as
  /// the new task [newId], carried from it, so the old note keeps its line.
  void writeFromBacklog(String id, String newId, int index) => doc.runInTransaction(() {
        _fields.set('$id/backlogAt', null);
        if (_onNotes().contains(id)) {
          carry(id, newId, index);
        } else {
          _order.insert(index, id);
        }
      });

  /// Takes the task [id] out of the backlog without writing it: it is let go, on purpose.
  void removeFromBacklog(String id) => doc.runInTransaction(() {
        _fields.set('$id/backlogAt', null);
        letGo(id);
      });

  /// Tasks in the backlog, oldest first.
  List<String> get backlogIds {
    final fields = _values;
    final order = ids.toSet();
    final onNotes = _onNotes();
    final found = [
      for (final MapEntry(:key, :value) in fields.entries)
        if (key.endsWith('/backlogAt') && value is int)
          if (key.substring(0, key.length - '/backlogAt'.length) case final id
              when _status(id, fields, order, onNotes) == TaskStatus.backlog)
            id
    ];
    int at(String id) => fields['$id/backlogAt'] as int;
    return found..sort((a, b) => at(a) != at(b) ? at(a).compareTo(at(b)) : a.compareTo(b));
  }

  /// What became of task [id].
  TaskStatus status(String id) => _status(id, _values, ids.toSet(), _onNotes());

  Set<String> _onNotes() => {for (final n in notes) ...n.taskIds};

  TaskStatus _status(
      String id, Map<String, Object?> fields, Set<String> order, Set<String> onNotes) {
    if (fields['$id/deletedAt'] is int) return TaskStatus.deleted;
    if (fields['$id/doneAt'] is int) return TaskStatus.done;
    if (fields['$id/carriedTo'] is String) return TaskStatus.carried;
    if (fields['$id/letGoAt'] is int) return TaskStatus.letGo;
    if (order.contains(id)) return TaskStatus.open;
    if (fields['$id/backlogAt'] is int) return TaskStatus.backlog;
    // Not on the note and never torn off with one: deleted before deletions were recorded.
    if (!onNotes.contains(id)) return TaskStatus.deleted;
    return TaskStatus.pending;
  }

  /// What became of every task in [taskIds], read in one pass.
  Map<String, TaskStatus> statuses(Iterable<String> taskIds) {
    final fields = _values;
    final order = ids.toSet();
    final onNotes = _onNotes();
    return {for (final id in taskIds) id: _status(id, fields, order, onNotes)};
  }

  int? fieldInt(String key) => switch (_values[key]) { int v => v, _ => null };

  /// The ids of every task ever written, pauses left out, in no particular order.
  List<String> get allTaskIds {
    final fields = _values;
    return [
      for (final key in fields.keys)
        if (key.endsWith('/name') && !key.startsWith('note/') && !key.startsWith('current/'))
          if (key.substring(0, key.length - '/name'.length) case final id
              when fields['$id/kind'] != 'pause')
            id
    ];
  }

  /// Unfinished tasks of torn-off notes still waiting to be written again or let go, in the order
  /// they were on their notes, oldest note first.
  List<String> get pendingIds {
    final notes = this.notes;
    final ordered = <String>[
      for (final note in notes) ...note.taskIds,
    ];
    final statuses = this.statuses(ordered);
    final seen = <String>{};
    return [
      for (final id in ordered)
        if (seen.add(id) && statuses[id] == TaskStatus.pending) id
    ];
  }

  /// The ids of every pause logged, in no particular order.
  List<String> get pauseIds => [
        for (final MapEntry(:key, :value) in _values.entries)
          if (key.endsWith('/kind') && value == 'pause')
            key.substring(0, key.length - '/kind'.length)
      ];

  /// Logs a pause starting now, as a hidden task whose time entry runs until [endPauses].
  void startPause(String id) => doc.runInTransaction(() {
        _fields
          ..set('$id/kind', 'pause')
          ..set('$id/name', 'Pause')
          ..set('$id/e/${nowSeconds()}', null);
      });

  /// When the pause under way started, or null when no pause is running. Should a merge leave
  /// more than one open, the earliest counts.
  int? get pauseStartedAt {
    int? start;
    for (final id in pauseIds) {
      for (final e in task(id).entries) {
        if (e.end == null && (start == null || e.start < start)) start = e.start;
      }
    }
    return start;
  }

  /// Ends every pause still running.
  void endPauses() {
    for (final id in pauseIds) {
      setRunning(id, false);
    }
  }

  void move(int from, int to) => _order.move(from, to);

  void setName(String id, String name) => _fields.set('$id/name', name);

  void setNotes(String id, String notes) => _fields.set('$id/notes', notes);

  void setTimer(String id, int lengthSeconds, int startAt) =>
      doc.runInTransaction(() {
        _fields
          ..set('$id/timerLength', lengthSeconds)
          ..set('$id/timerStartAt', startAt);
      });

  /// Keeps where the task's Pomodoro is, or forgets it with null.
  void setPomodoro(String id, String? record) => _fields.set('$id/pomodoro', record);

  void setTotalResetAt(String id, int at) => _fields.set('$id/totalResetAt', at);

  /// Starts the timer by opening a time entry, or stops it by closing every open one.
  void setRunning(String id, bool running) {
    final now = nowSeconds();
    final current = task(id);
    if (running && !current.running) {
      _fields.set('$id/e/$now', null);
    } else if (!running) {
      for (final e in current.entries.where((e) => e.end == null)) {
        _fields.set('$id/e/${e.start}', now);
      }
    }
  }

  /// Every change in the document, encoded for storage.
  String encodeChanges() => jsonEncode(
      [for (final c in doc.exportChanges()) base64Encode(c.toBytes())]);

  void importEncodedChanges(String encoded) {
    final list = jsonDecode(encoded) as List;
    doc.importChanges([
      for (final c in list) Change.fromBytes(Uint8List.fromList(base64Decode(c)))
    ]);
  }
}

/// What became of a task.
enum TaskStatus {
  /// On the current note, not done yet.
  open,
  done,

  /// Torn off unfinished, waiting to be written again or let go.
  pending,

  /// Torn off unfinished and written again on a later note.
  carried,

  /// Torn off unfinished and not written again.
  letGo,

  /// Kept for later, off the note.
  backlog,
  deleted,
}

/// A note torn off: the tasks written on it, in order, and when it was started and torn off.
class NoteRecord {
  final String id;
  final int startedAt;
  final int closedAt;
  final List<String> taskIds;

  const NoteRecord(
      {required this.id,
      required this.startedAt,
      required this.closedAt,
      required this.taskIds});
}
