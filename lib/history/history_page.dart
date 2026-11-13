import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/history.dart';
import '../bloc/task_document.dart';
import '../bloc/tasks_bloc.dart';
import '../note/note_view.dart';
import '../note/paper.dart';
import '../timer.dart';

enum _HistoryMode { notes, list }

/// Earlier notes, one per day, or every task written as a list with what became of it and when.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  _HistoryMode _mode = _HistoryMode.notes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: BlocBuilder<TasksBloc, TasksState>(
        // The clock ticks every second; the history only needs reading when the note changes.
        buildWhen: (a, b) => a.tasks != b.tasks || a.pending != b.pending,
        builder: (context, state) {
          final doc = context.read<TasksBloc>().taskDocument;
          final history = doc == null ? History.empty : buildHistory(doc);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<_HistoryMode>(
                  segments: const [
                    ButtonSegment(
                        value: _HistoryMode.notes,
                        icon: Icon(Icons.sticky_note_2_outlined),
                        label: Text('Notes')),
                    ButtonSegment(
                        value: _HistoryMode.list,
                        icon: Icon(Icons.list),
                        label: Text('Tasks')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              Expanded(
                child: switch (_mode) {
                  _ when history.tasks.isEmpty => const _Empty(),
                  _HistoryMode.notes => _NotesHistory(history: history),
                  _HistoryMode.list => _TaskHistory(history: history),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Nothing written yet. Your notes and tasks will show up here.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

String _time(BuildContext context, int seconds) =>
    TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(seconds * 1000))
        .format(context);

class _NotesHistory extends StatelessWidget {
  final History history;

  const _NotesHistory({required this.history});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: history.notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 28),
      itemBuilder: (context, index) {
        final note = history.notes[index];
        final day = formatDay(context, note.day);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: NoteSheet(
              title: note.closedAt == null ? '$day · in use' : day,
              subtitle: '${note.doneCount} of ${note.tasks.length} done',
              lines: [
                for (final t in note.tasks)
                  NoteSheetLine(
                    name: t.name,
                    status: t.status,
                    trailing: switch (t.status) {
                      TaskStatus.done when t.doneAt != null => _time(context, t.doneAt!),
                      TaskStatus.carried => 'written again',
                      TaskStatus.letGo => 'let go',
                      TaskStatus.pending => 'waiting',
                      _ => null,
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TaskHistory extends StatelessWidget {
  final History history;

  const _TaskHistory({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    DateTime? day;
    for (final task in history.tasks) {
      if (task.day != day) {
        day = task.day;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(formatDay(context, task.day),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      final status = switch (task.status) {
        TaskStatus.done when task.doneAt != null => 'Done at ${_time(context, task.doneAt!)}',
        TaskStatus.done => 'Done',
        TaskStatus.open => 'Not done yet',
        TaskStatus.pending => 'Waiting to be written again',
        TaskStatus.carried => 'Not finished, written again on a later note',
        TaskStatus.letGo => 'Not finished, let go',
        TaskStatus.deleted => 'Deleted',
      };
      rows.add(ListTile(
        leading: Icon(statusIcon(task.status)),
        title: StrikeText(
          task.name.isEmpty ? 'Untitled task' : task.name,
          struck: task.status == TaskStatus.done,
          animate: false,
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Text([
          status,
          if (task.workedSeconds > 0) 'worked ${formatClock(task.workedSeconds)}',
        ].join(' · ')),
      ));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: rows),
      ),
    );
  }
}
