import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'task_document.dart';
import 'tasks_bloc.dart';

/// The `format` field every tasks file carries, so a stray JSON file isn't read as tasks.
const tasksFileFormat = 'bringmeback-tasks';

/// The version of the file layout written by [exportTasks]. Files of a newer version are refused.
const tasksFileVersion = 1;

/// The most tasks a file may hold. A file is untrusted, and more than this is not a task list.
const maxImportedTasks = 1000;

/// A task as a tasks file holds it.
///
/// A file is plain JSON, readable and editable by hand:
///
/// ```json
/// {
///   "format": "bringmeback-tasks",
///   "version": 1,
///   "exportedAt": "2026-11-13T12:00:00.000Z",
///   "tasks": [
///     {"id": "…", "name": "Write report", "notes": "", "timerLengthSeconds": 1200,
///      "timerStartAt": 1763030000, "totalResetAt": 0, "doneAt": null,
///      "entries": [{"start": 1763030000, "end": 1763031200}]}
///   ],
///   "waiting": [ … ]
/// }
/// ```
///
/// `tasks` is the current note, in order, done tasks included. `waiting` is the unfinished tasks of
/// torn-off notes not yet written again or let go. Only `name` is required; times are Unix seconds.
class TransferTask {
  final String? id;
  final String name;
  final String notes;
  final int timerLengthSeconds;
  final int? timerStartAt;
  final int totalResetAt;
  final int? doneAt;
  final List<TimeEntry> entries;

  const TransferTask(
      {this.id,
      required this.name,
      this.notes = '',
      this.timerLengthSeconds = 20 * 60,
      this.timerStartAt,
      this.totalResetAt = 0,
      this.doneAt,
      this.entries = const []});

  /// [task] as of [now]: a timer still running is written as stopped at [now], so an imported task
  /// never starts counting by itself.
  factory TransferTask.of(TaskState task, int now) => TransferTask(
        id: task.id.value,
        name: task.name,
        notes: task.notes,
        timerLengthSeconds: task.timerLengthSeconds,
        timerStartAt: task.timerStartAt,
        totalResetAt: task.totalResetAt,
        doneAt: task.doneAt,
        entries: [
          for (final e in task.entries) TimeEntry(start: e.start, end: e.end ?? now)
        ],
      );

  /// This task as task [id] of a document, written at [now] when the file doesn't say.
  TaskState toTask(String id, int now) => TaskState(
        id: ValueKey<String>(id),
        name: name,
        notes: notes,
        timerLengthSeconds: timerLengthSeconds,
        timerStartAt: timerStartAt ?? now,
        totalResetAt: totalResetAt,
        doneAt: doneAt,
        entries: entries,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'timerLengthSeconds': timerLengthSeconds,
        'timerStartAt': timerStartAt,
        'totalResetAt': totalResetAt,
        'doneAt': doneAt,
        'entries': [
          for (final e in entries) {'start': e.start, 'end': e.end}
        ],
      };

  /// Reads one task of a file. Throws [FormatException] for anything that isn't one.
  factory TransferTask.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('A task is not an object.');
    final name = json['name'];
    if (name is! String) throw const FormatException('A task has no name.');
    T? optional<T>(String key) => switch (json[key]) {
          null => null,
          T v => v,
          _ => throw FormatException('A task\'s "$key" has the wrong type.'),
        };
    final length = optional<int>('timerLengthSeconds') ?? 20 * 60;
    if (length <= 0) {
      throw const FormatException('A task\'s timer length must be positive.');
    }
    final entries = <TimeEntry>[];
    for (final e in optional<List>('entries') ?? const []) {
      if (e is! Map || e['start'] is! int || (e['end'] != null && e['end'] is! int)) {
        throw const FormatException('A task has a time entry that does not read.');
      }
      final start = e['start'] as int;
      final end = e['end'] as int?;
      // An open entry would leave the task running; a backwards one would count negative time.
      if (end == null || end < start) {
        throw const FormatException('A task has a time entry that does not end after it starts.');
      }
      entries.add(TimeEntry(start: start, end: end));
    }
    return TransferTask(
      id: optional<String>('id'),
      name: name,
      notes: optional<String>('notes') ?? '',
      timerLengthSeconds: length,
      timerStartAt: optional<int>('timerStartAt'),
      totalResetAt: optional<int>('totalResetAt') ?? 0,
      doneAt: optional<int>('doneAt'),
      entries: entries,
    );
  }
}

/// The tasks a file holds.
class TasksFile {
  /// The current note, in order.
  final List<TransferTask> tasks;

  /// Unfinished tasks of torn-off notes.
  final List<TransferTask> waiting;

  const TasksFile({this.tasks = const [], this.waiting = const []});

  int get length => tasks.length + waiting.length;
}

/// The current note and the tasks waiting from torn-off notes in [doc], as the text of a tasks file.
String exportTasks(TaskDocument doc, {int? now}) {
  now ??= nowSeconds();
  return const JsonEncoder.withIndent('  ').convert({
    'format': tasksFileFormat,
    'version': tasksFileVersion,
    'exportedAt':
        DateTime.fromMillisecondsSinceEpoch(now * 1000, isUtc: true).toIso8601String(),
    'tasks': [for (final t in doc.tasks()) TransferTask.of(t, now).toJson()],
    'waiting': [for (final id in doc.pendingIds) TransferTask.of(doc.task(id), now).toJson()],
  });
}

/// Reads the text of a tasks file. Throws [FormatException], with a message to show, when it isn't
/// one.
TasksFile parseTasksFile(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This file is not a bringmeback tasks file.');
  }
  if (json is! Map || json['format'] != tasksFileFormat) {
    throw const FormatException('This file is not a bringmeback tasks file.');
  }
  final Map fields = json;
  final version = fields['version'];
  if (version is! int || version < 1) {
    throw const FormatException('This tasks file has no version.');
  }
  if (version > tasksFileVersion) {
    throw const FormatException(
        'This tasks file was made by a newer version of bringmeback. Update the app to import it.');
  }
  List<TransferTask> list(String key) {
    final value = fields[key];
    if (value == null) return const [];
    if (value is! List) throw FormatException('"$key" is not a list.');
    return [for (final t in value) TransferTask.fromJson(t)];
  }

  final file = TasksFile(tasks: list('tasks'), waiting: list('waiting'));
  if (file.length > maxImportedTasks) {
    throw const FormatException('This file holds too many tasks to import.');
  }
  return file;
}

/// What an import did.
class ImportResult {
  /// Tasks written on the current note.
  final int added;

  /// Tasks put with the unfinished tasks of earlier notes, to be written again or let go: the
  /// file's waiting tasks, and any that didn't fit on the note.
  final int waiting;

  /// Tasks left out because this device already has them, such as when importing a file twice.
  final int skipped;

  const ImportResult({this.added = 0, this.waiting = 0, this.skipped = 0});

  String get summary {
    String tasks(int n) => n == 1 ? '1 task' : '$n tasks';
    final parts = [
      if (added > 0) '${tasks(added)} added to the note',
      if (waiting > 0) '${tasks(waiting)} waiting to be written again',
      if (skipped > 0) '${tasks(skipped)} already here',
    ];
    return parts.isEmpty ? 'The file has no tasks.' : 'Imported: ${parts.join(', ')}.';
  }
}

/// Whether [id] reads as an id [newId] makes, so a file can't write into fields that aren't a
/// task's, such as `note/…` or `current/…`.
bool _validId(String id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id);

/// Imports [file] into [doc]. Tasks go at the end of the current note, below what is being worked
/// on, as long as it has room under [noteLines]; the rest, and the file's waiting tasks, are kept as
/// an imported note torn off at [now], so the unfinished ones wait to be written again like those
/// of any torn-off note, and nothing in the file is lost.
///
/// A task whose id is already in [doc] is skipped, so importing the same file again, or on a device
/// that synced it, adds nothing twice. [newId] names tasks the file gives no usable id.
ImportResult importTasks(TaskDocument doc, TasksFile file,
    {required int noteLines, required String Function() newId, int? now}) {
  now ??= nowSeconds();
  final known = doc.allTaskIds.toSet();
  var skipped = 0;
  String? idFor(TransferTask t) {
    final id = t.id;
    if (id == null || !_validId(id)) return newId();
    if (!known.add(id)) {
      skipped++;
      return null;
    }
    return id;
  }

  final onNote = <({String id, TaskState task})>[];
  final waiting = <({String id, TaskState task})>[];
  for (final t in file.tasks) {
    final id = idFor(t);
    if (id == null) continue;
    (doc.ids.length + onNote.length < noteLines ? onNote : waiting)
        .add((id: id, task: t.toTask(id, now)));
  }
  for (final t in file.waiting) {
    final id = idFor(t);
    if (id != null) waiting.add((id: id, task: t.toTask(id, now)));
  }

  doc.doc.runInTransaction(() {
    for (final (:id, :task) in onNote) {
      doc.insert(doc.ids.length, id,
          name: task.name,
          notes: task.notes,
          timerLengthSeconds: task.timerLengthSeconds,
          timerStartAt: task.timerStartAt,
          totalResetAt: task.totalResetAt,
          entries: task.entries);
      if (task.doneAt case final doneAt?) doc.setDoneAt(id, doneAt);
    }
    if (waiting.isNotEmpty) doc.addTornOffNote(newId(), now!, waiting);
  });

  return ImportResult(
      added: onNote.length,
      waiting: waiting.where((w) => !w.task.done).length,
      skipped: skipped);
}
