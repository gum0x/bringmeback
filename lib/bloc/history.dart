import 'task_document.dart';
import 'tasks_bloc.dart';

/// A task as the history shows it: what became of it, when, and how long it was worked on.
class HistoryTask {
  final String id;
  final String name;
  final TaskStatus status;

  /// The day the task was written on, as [dayOf] gives it.
  final DateTime day;
  final int? doneAt;
  final int workedSeconds;

  /// Whether this task was written again from an earlier note.
  final bool carriedFrom;

  const HistoryTask(
      {required this.id,
      required this.name,
      required this.status,
      required this.day,
      this.doneAt,
      this.workedSeconds = 0,
      this.carriedFrom = false});
}

/// One note as it was written, the current one included.
class HistoryNote {
  final DateTime day;
  final int startedAt;

  /// When it was torn off, or null for the note in use.
  final int? closedAt;
  final List<HistoryTask> tasks;

  const HistoryNote(
      {required this.day, required this.startedAt, this.closedAt, required this.tasks});

  int get doneCount => tasks.where((t) => t.status == TaskStatus.done).length;
}

class History {
  /// Every note, newest first; the one in use comes first.
  final List<HistoryNote> notes;

  /// Every task written, deleted ones left out, newest day first and in note order within a day.
  final List<HistoryTask> tasks;

  const History({required this.notes, required this.tasks});

  static const empty = History(notes: [], tasks: []);
}

/// Reads the history of notes and tasks out of [doc].
History buildHistory(TaskDocument doc, {int? now}) {
  now ??= nowSeconds();
  final notes = doc.notes;
  final currentIds = doc.ids;
  final allIds = doc.allTaskIds;
  final statuses = doc.statuses({...allIds, for (final n in notes) ...n.taskIds});

  HistoryTask read(String id, DateTime? day) {
    final task = doc.task(id);
    final firstWorked = task.entries.isEmpty ? null : task.entries.first.start;
    return HistoryTask(
      id: id,
      name: task.name,
      status: statuses[id] ?? TaskStatus.deleted,
      day: day ?? dayOf(task.doneAt ?? firstWorked ?? 0),
      doneAt: task.doneAt,
      workedSeconds: task.totalSecondsAt(now!),
      carriedFrom: task.carriedFrom != null,
    );
  }

  final current = HistoryNote(
    day: dayOf(doc.noteStartedAt ?? now),
    startedAt: doc.noteStartedAt ?? now,
    tasks: [for (final id in currentIds) read(id, dayOf(doc.noteStartedAt ?? now))],
  );
  final torn = [
    for (final note in notes.reversed)
      HistoryNote(
        day: dayOf(note.startedAt),
        startedAt: note.startedAt,
        closedAt: note.closedAt,
        tasks: [
          for (final id in note.taskIds)
            if (statuses[id] != TaskStatus.deleted) read(id, dayOf(note.startedAt))
        ],
      ),
  ];

  // Tasks on a note take that note's day. Tasks done before notes existed take the day they were
  // done.
  final onNotes = {...currentIds, for (final n in notes) ...n.taskIds};
  final loose = [
    for (final id in allIds)
      if (!onNotes.contains(id) &&
          statuses[id] != TaskStatus.deleted &&
          statuses[id] != TaskStatus.backlog)
        read(
            id,
            statuses[id] == TaskStatus.letGo
                ? dayOf(doc.fieldInt('$id/letGoAt') ?? 0)
                : null)
  ]..sort((a, b) => (b.doneAt ?? 0).compareTo(a.doneAt ?? 0));

  final tasks = <HistoryTask>[
    ...current.tasks,
    for (final note in torn) ...note.tasks,
    ...loose,
  ];
  // Stable sort by day, newest first, keeping note order within a day.
  final indexed = tasks.indexed.toList()
    ..sort((a, b) {
      final byDay = b.$2.day.compareTo(a.$2.day);
      return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
    });

  return History(
    notes: [if (current.tasks.isNotEmpty) current, ...torn],
    tasks: [for (final (_, t) in indexed) t],
  );
}
