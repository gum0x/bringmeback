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
/// A removed task leaves the order but keeps its fields, so its history stays in the document. A task
/// marked done leaves the order the same way, with `<taskId>/doneAt` set.
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
      id: ValueKey<String>(id),
      timerLengthSeconds: field<int>('timerLength', 20 * 60),
      timerStartAt: field<int>('timerStartAt', 0),
      totalResetAt: field<int>('totalResetAt', 0),
      entries: entries,
      inFocus: inFocus,
    );
  }

  List<TaskState> tasks({String? focusId}) =>
      [for (final id in ids) task(id, inFocus: id == focusId)];

  /// Adds a task at [index] with the given fields; [running] opens its first time entry now.
  void insert(int index, String id,
      {String name = '',
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
      for (final e in entries) {
        _fields.set('$id/e/${e.start}', e.end);
      }
      if (running && !entries.any((e) => e.end == null)) {
        _fields.set('$id/e/${nowSeconds()}', null);
      }
    });
  }

  void removeAt(int index) => _order.delete(index);

  /// Puts a removed or done task back at [index]; its fields never left the document.
  void restore(int index, String id) => doc.runInTransaction(() {
        _order.insert(index, id);
        if (_values['$id/doneAt'] != null) _fields.set('$id/doneAt', null);
      });

  /// Takes the task at [index] off the list as done, keeping when it was finished.
  void markDone(int index, String id) => doc.runInTransaction(() {
        _fields.set('$id/doneAt', nowSeconds());
        _order.delete(index);
      });

  int? doneAt(String id) => switch (_values['$id/doneAt']) { int v => v, _ => null };

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

  /// Ends every pause still running.
  void endPauses() {
    for (final id in pauseIds) {
      setRunning(id, false);
    }
  }

  void move(int from, int to) => _order.move(from, to);

  void setName(String id, String name) => _fields.set('$id/name', name);

  void setTimer(String id, int lengthSeconds, int startAt) =>
      doc.runInTransaction(() {
        _fields
          ..set('$id/timerLength', lengthSeconds)
          ..set('$id/timerStartAt', startAt);
      });

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
