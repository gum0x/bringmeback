import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';
import '../focus/focus_page.dart';
import '../timer.dart';
import 'paper.dart';
import 'task_dialog.dart';

/// Asks for a new task in the dialog and writes it at [index]; on top as an interruption when
/// [onTop].
Future<void> writeTask(BuildContext context,
    {int index = 0, bool onTop = false}) async {
  final tasksBloc = context.read<TasksBloc>();
  if (tasksBloc.state.full) {
    showNoteFull(context);
    return;
  }
  final details = await showTaskDialog(context);
  if (details == null) return;
  final id = ValueKey<String>(newId());
  tasksBloc.add(onTop
      ? AddTaskOnTopEvent(
          name: details.name,
          id: id,
          timerLengthSeconds: details.timerLengthSeconds)
      : InsertTaskEvent(
          index: index,
          name: details.name,
          id: id,
          timerLengthSeconds: details.timerLengthSeconds));
}

/// Edits the name and countdown of the task at [index] in the dialog.
Future<void> editTask(BuildContext context, int index) async {
  final tasksBloc = context.read<TasksBloc>();
  final tasks = tasksBloc.state.tasks;
  if (index < 0 || index >= tasks.length) return;
  final task = tasks[index];
  final details = await showTaskDialog(context,
      name: task.name,
      timerLengthSeconds: task.timerLengthSeconds,
      editing: true);
  if (details == null) return;
  tasksBloc.add(EditTaskEvent(
      id: task.id,
      name: details.name,
      timerLengthSeconds: details.timerLengthSeconds));
}

void showNoteFull(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(const SnackBar(
    content: Text(
        'This note is full. Finish or delete a task, or start a fresh note.'),
  ));
}

/// Deletes the task at [index] from the note and offers to bring it back.
void removeTask(BuildContext context, int index) {
  final tasksBloc = context.read<TasksBloc>();
  final tasks = tasksBloc.state.tasks;
  if (index < 0 || index >= tasks.length) return;
  final task = tasks[index];
  tasksBloc.add(RemoveTaskEvent(index: index));
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(task.name.isEmpty ? 'Task deleted' : 'Deleted: ${task.name}'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () =>
          tasksBloc.add(RestoreTaskEvent(index: index, id: task.id)),
    ),
  ));
}

enum _LineAction { focus, edit, restartCountdown, resetTotal, delete }

/// One task written on the note: its number, a checkbox to strike it through, and its name. The
/// current task, the first one not checked off, also shows its clocks and a play/pause button.
///
/// Pointing at a task, or tapping it to select it, shows small (+) buttons above and below it to
/// write a new task right there, plus edit and more actions.
class TaskLine extends StatefulWidget {
  final TaskState task;
  final int index;
  final bool current;

  /// Whether new tasks can still be written on the note.
  final bool canInsert;

  const TaskLine({
    super.key,
    required this.task,
    required this.index,
    required this.current,
    required this.canInsert,
  });

  @override
  State<TaskLine> createState() => _TaskLineState();
}

class _TaskLineState extends State<TaskLine> {
  bool _hovered = false;
  int _bursts = 0;

  TasksBloc get _bloc => context.read<TasksBloc>();

  void _setDone(bool done) {
    if (done) {
      HapticFeedback.lightImpact();
      setState(() => _bursts++);
    }
    _bloc.add(SetDoneEvent(index: widget.index, done: done));
  }

  void _select() {
    if (widget.task.inFocus) {
      editTask(context, widget.index);
    } else {
      _bloc.add(FocusTaskEvent(index: widget.index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final colors = NoteColors.of(context);
    final theme = Theme.of(context);
    final active = _hovered || task.inFocus;
    final showInsert = active && widget.canInsert;

    final number = SizedBox(
      width: 30,
      child: Text(
        '${widget.index + 1}.',
        textAlign: TextAlign.right,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colors.faded,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    final checkbox = Burst(
      trigger: _bursts,
      child: Checkbox(
        value: task.done,
        semanticLabel: task.done ? 'Mark as not done' : 'Mark as done',
        side: BorderSide(color: colors.faded, width: 1.6),
        onChanged: (value) => _setDone(value ?? false),
      ),
    );

    final name = StrikeText(
      task.name.isEmpty ? 'Untitled task' : task.name,
      struck: task.done,
      style: theme.textTheme.titleMedium?.copyWith(
        color: colors.ink,
        fontWeight: widget.current ? FontWeight.w600 : FontWeight.w400,
        fontStyle: task.name.isEmpty ? FontStyle.italic : null,
      ),
    );

    final details = <Widget>[
      if (widget.current)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TaskClock(
            remainingSeconds: task.taskTimerSeconds,
            totalSeconds: task.totalTaskTimerSeconds,
            paused: !task.running,
          ),
        )
      else if (task.done && task.doneAt != null)
        Text(
          'Done ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(task.doneAt! * 1000)).format(context)}',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.faded),
        ),
    ];

    final playPause = widget.current
        ? IconButton.filledTonal(
            tooltip: task.running ? 'Pause (logs a break)' : 'Resume work',
            onPressed: () => _bloc.add(task.running
                ? StopTimerEvent(index: widget.index)
                : ResumeTimerEvent(index: widget.index)),
            icon: Icon(task.running ? Icons.pause : Icons.play_arrow),
          )
        : null;

    final menu = PopupMenuButton<_LineAction>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (action) {
        switch (action) {
          case _LineAction.focus:
            openFocus(context, widget.task.id.value);
          case _LineAction.edit:
            editTask(context, widget.index);
          case _LineAction.restartCountdown:
            _bloc.add(ResetTimerEvent(index: widget.index));
          case _LineAction.resetTotal:
            _bloc.add(ResetTotalEvent(index: widget.index));
          case _LineAction.delete:
            removeTask(context, widget.index);
        }
      },
      itemBuilder: (context) => [
        if (!task.done)
          const PopupMenuItem(
            value: _LineAction.focus,
            child: ListTile(
                leading: Icon(Icons.center_focus_strong),
                title: Text('Focus with Pomodoro')),
          ),
        const PopupMenuItem(
          value: _LineAction.edit,
          child: ListTile(
              leading: Icon(Icons.edit_outlined), title: Text('Edit task')),
        ),
        const PopupMenuItem(
          value: _LineAction.restartCountdown,
          child: ListTile(
              leading: Icon(Icons.restart_alt),
              title: Text('Restart countdown')),
        ),
        const PopupMenuItem(
          value: _LineAction.resetTotal,
          child: ListTile(
              leading: Icon(Icons.history), title: Text('Reset total time')),
        ),
        PopupMenuItem(
          value: _LineAction.delete,
          child: ListTile(
              leading:
                  Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: const Text('Delete task')),
        ),
      ],
    );

    /// Edit and more actions, shown while the task is pointed at or selected. On a phone only the
    /// menu shows, and only then, to leave the name room; tapping a selected task edits it too.
    Widget tools(bool compact) {
      if (compact) return active ? menu : const SizedBox.shrink();
      return Visibility(
        visible: active,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Edit task',
            visualDensity: VisualDensity.compact,
            onPressed: () => editTask(context, widget.index),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          menu,
        ]),
      );
    }

    final dragHandle = ReorderableDragStartListener(
      index: widget.index,
      child: Tooltip(
        message: 'Drag to reorder',
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.drag_indicator,
                size: 20,
                color: colors.faded.withValues(alpha: active ? 1 : 0.45)),
          ),
        ),
      ),
    );

    final line = Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: widget.current
            ? colors.highlight
            : (task.inFocus ? colors.highlight.withValues(alpha: 0.08) : null),
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
          builder: (context, constraints) => Row(
                children: [
                  number,
                  const SizedBox(width: 4),
                  checkbox,
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, ...details],
                    ),
                  ),
                  if (playPause != null) ...[
                    const SizedBox(width: 4),
                    playPause
                  ],
                  tools(constraints.maxWidth < 480),
                  dragHandle,
                ],
              )),
    );

    // Each task is its own semantics node, so its buttons move with it when tasks reorder. Without
    // it the web engine's semantics tree goes out of step when a reorder also hides a button.
    return Semantics(
        container: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _select,
            child: Stack(
              children: [
                line,
                if (showInsert) ...[
                  Positioned(
                    top: 1,
                    left: 14,
                    child: _InsertButton(
                      tooltip: 'Add a task above',
                      onPressed: () => writeTask(context, index: widget.index),
                    ),
                  ),
                  Positioned(
                    bottom: 1,
                    left: 14,
                    child: _InsertButton(
                      tooltip: 'Add a task below',
                      onPressed: () =>
                          writeTask(context, index: widget.index + 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ));
  }
}

/// A small round (+) at the edge of a task, to write a new task right there.
class _InsertButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;

  const _InsertButton({required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Icon(Icons.add,
                size: 16, color: scheme.onPrimary, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }
}

/// The countdown left, or the time over it, and the total time tracked on the current task.
class TaskClock extends StatelessWidget {
  final int remainingSeconds;
  final int totalSeconds;
  // Work on the task is paused.
  final bool paused;

  const TaskClock({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
    this.paused = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NoteColors.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final over = remainingSeconds < 0;
    final small = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: tabular,
      color: colors.faded,
    );
    return Wrap(
      spacing: 12,
      children: [
        Text(
          over
              ? '+${formatClock(remainingSeconds)} over'
              : 'Left ${formatClock(remainingSeconds)}',
          style: small?.copyWith(
            color: over ? theme.colorScheme.error : colors.ink,
            fontWeight: over ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          'Total ${formatClock(totalSeconds)}${paused ? ' · Paused' : ''}',
          style: small,
        ),
      ],
    );
  }
}
