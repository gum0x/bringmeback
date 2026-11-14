import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';
import '../focus/focus_page.dart';
import '../timer.dart';
import 'paper.dart';
import 'task_dialog.dart';

/// Asks for a new task in the dialog and writes it at [index]; on top as an interruption when
/// [onTop]. When the note already holds as many unfinished tasks as the limit, it asks first and
/// suggests the backlog.
Future<void> writeTask(BuildContext context,
    {int index = 0, bool onTop = false}) async {
  final tasksBloc = context.read<TasksBloc>();
  final details = await showTaskDialog(context);
  if (details == null || !context.mounted) return;
  final id = ValueKey<String>(newId());
  if (tasksBloc.state.atLimit) {
    final choice = await askOverLimit(context, name: details.name);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case OverLimitChoice.backlog:
        tasksBloc.add(AddToBacklogEvent(
            name: details.name,
            notes: details.notes,
            id: id,
            timerLengthSeconds: details.timerLengthSeconds));
        showSavedToBacklog(context, details.name);
        return;
      case OverLimitChoice.letGo:
        tasksBloc.add(LetGoNewTaskEvent(name: details.name, notes: details.notes, id: id));
        showLetGo(context, details.name);
        return;
      case OverLimitChoice.note:
    }
  }
  tasksBloc.add(onTop
      ? AddTaskOnTopEvent(
          name: details.name,
          notes: details.notes,
          id: id,
          timerLengthSeconds: details.timerLengthSeconds)
      : InsertTaskEvent(
          index: index,
          name: details.name,
          notes: details.notes,
          id: id,
          timerLengthSeconds: details.timerLengthSeconds));
}

/// Edits the name, details and countdown of the task at [index] in the dialog.
Future<void> editTask(BuildContext context, int index) async {
  final tasksBloc = context.read<TasksBloc>();
  final tasks = tasksBloc.state.tasks;
  if (index < 0 || index >= tasks.length) return;
  final task = tasks[index];
  final details = await showTaskDialog(context,
      name: task.name,
      notes: task.notes,
      timerLengthSeconds: task.timerLengthSeconds,
      editing: true);
  if (details == null) return;
  tasksBloc.add(EditTaskEvent(
      id: task.id,
      name: details.name,
      notes: details.notes,
      timerLengthSeconds: details.timerLengthSeconds));
}

/// What to do with a task that would take the note over its limit.
enum OverLimitChoice {
  /// Keep it for later, off the note (experimental).
  backlog,

  /// Write it on the note anyway.
  note,

  /// Don't do it: drop it on purpose. Not everything can be done, and choosing what not to do is
  /// part of keeping the day focused. History keeps it as let go.
  letGo,
}

/// Asks whether a task goes on the note even though it already holds as many unfinished tasks as
/// the limit, is let go on purpose, or, with the experimental backlog on, kept there for later.
/// Null when cancelled. [fromBacklog] is for a task already in the backlog, which then stays
/// there unless let go.
Future<OverLimitChoice?> askOverLimit(BuildContext context,
    {required String name, bool fromBacklog = false}) {
  final state = context.read<TasksBloc>().state;
  final open = state.openCount;
  final title = name.trim().isEmpty ? 'This task' : '"${name.trim()}"';
  final offerBacklog = state.backlogEnabled && !fromBacklog;
  final question = fromBacklog
      ? '$title can stay in the backlog until you have room. Or write it on the note anyway, '
          'or let it go: not everything has to be done.'
      : offerBacklog
          ? 'Save $title to the backlog for later, write it on the note anyway, or let it go? '
              'Not everything has to be done.'
          : 'Write $title on the note anyway, or let it go? Not everything has to be done.';
  return showDialog<OverLimitChoice>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.playlist_add_check),
      title: Text(open > state.taskLimit
          ? 'Your note is over its limit'
          : 'Your note is at its limit'),
      content: Text(
          'You have $open ${open == 1 ? 'task' : 'tasks'} not done yet, and your limit is '
          '${state.taskLimit}. A short list keeps the day focused.\n\n$question'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton.icon(
            onPressed: () => Navigator.pop(context, OverLimitChoice.letGo),
            icon: const Icon(Icons.do_not_disturb_on_outlined),
            label: const Text('Let it go')),
        TextButton(
            onPressed: () => Navigator.pop(context, OverLimitChoice.note),
            child: const Text('Write on note anyway')),
        if (offerBacklog)
          FilledButton.icon(
              onPressed: () => Navigator.pop(context, OverLimitChoice.backlog),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Save to backlog')),
      ],
    ),
  );
}

void showLetGo(BuildContext context, String name) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(name.trim().isEmpty
        ? 'Let go. Not everything has to be done.'
        : 'Let go: ${name.trim()}. Not everything has to be done.'),
  ));
}

void showSavedToBacklog(BuildContext context, String name) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(name.trim().isEmpty ? 'Saved to backlog' : 'Saved to backlog: ${name.trim()}'),
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

/// The task the bottom bar and the shortcuts act on: the selected one, or else the current one.
/// -1 when the note is empty.
int targetIndex(TasksState state) {
  final selected = state.tasks.indexWhere((t) => t.inFocus);
  if (selected >= 0) return selected;
  final current = state.currentIndex;
  return current >= 0 ? current : (state.tasks.isEmpty ? -1 : 0);
}

enum _BarAction { edit, resetTotal, delete }

/// The bar at the bottom of today's note: play/pause for the current task; focus, restart and more
/// actions for the selected task (or the current one when none is selected). New task sits at its
/// end.
class NoteToolbar extends StatelessWidget {
  const NoteToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    final theme = Theme.of(context);
    return BlocBuilder<TasksBloc, TasksState>(builder: (context, state) {
      final current = state.currentIndex;
      final running = current >= 0 && state.tasks[current].running;
      final target = targetIndex(state);
      final task = target >= 0 ? state.tasks[target] : null;
      final open = task != null && !task.done;
      return BottomAppBar(
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: running ? 'Pause (logs a break)' : 'Resume work',
              onPressed: current < 0
                  ? null
                  : () => bloc.add(running
                      ? StopTimerEvent(index: current)
                      : ResumeTimerEvent(index: current)),
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Focus with Pomodoro',
              onPressed: open ? () => openFocus(context, task.id.value) : null,
              icon: const Icon(Icons.center_focus_strong),
            ),
            IconButton(
              tooltip: 'Restart countdown',
              onPressed:
                  open ? () => bloc.add(ResetTimerEvent(index: target)) : null,
              icon: const Icon(Icons.restart_alt),
            ),
            PopupMenuButton<_BarAction>(
              tooltip: 'More actions',
              enabled: task != null,
              onSelected: (action) {
                switch (action) {
                  case _BarAction.edit:
                    editTask(context, target);
                  case _BarAction.resetTotal:
                    bloc.add(ResetTotalEvent(index: target));
                  case _BarAction.delete:
                    removeTask(context, target);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _BarAction.edit,
                  child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit task')),
                ),
                const PopupMenuItem(
                  value: _BarAction.resetTotal,
                  child: ListTile(
                      leading: Icon(Icons.history),
                      title: Text('Reset total time')),
                ),
                PopupMenuItem(
                  value: _BarAction.delete,
                  child: ListTile(
                      leading: Icon(Icons.delete_outline,
                          color: theme.colorScheme.error),
                      title: const Text('Delete task')),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

/// One task written on the note: its number, a checkbox to strike it through, its name and details.
/// The current task, the first one not checked off, also shows its clocks.
///
/// Tap a task to select it; the bottom bar then acts on it. Double tap or double click edits it.
/// Pointing at a task, or selecting it, shows small (+) buttons on its top and bottom edges to
/// write a new task right there.
class TaskLine extends StatefulWidget {
  final TaskState task;
  final int index;
  final bool current;

  /// Whether new tasks can still be written on the note.
  const TaskLine({
    super.key,
    required this.task,
    required this.index,
    required this.current,
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

  void _select() => _bloc.add(FocusTaskEvent(index: widget.index));

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final colors = NoteColors.of(context);
    final theme = Theme.of(context);
    final active = _hovered || task.inFocus;
    final showInsert = active;

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

    final details = <Widget>[
      StrikeText(
        task.name.isEmpty ? 'Untitled task' : task.name,
        struck: task.done,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colors.ink,
          fontWeight: widget.current ? FontWeight.w600 : FontWeight.w400,
          fontStyle: task.name.isEmpty ? FontStyle.italic : null,
        ),
      ),
      if (task.notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            task.notes,
            maxLines: task.inFocus ? 6 : 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.faded),
          ),
        ),
      if (widget.current)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TaskClock(
            remainingSeconds: task.taskTimerSeconds,
            lengthSeconds: task.timerLengthSeconds,
            totalSeconds: task.totalTaskTimerSeconds,
            paused: !task.running,
          ),
        )
      else if (!task.done)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: PlannedTime(
            remainingSeconds: task.taskTimerSeconds,
            lengthSeconds: task.timerLengthSeconds,
          ),
        )
      else if (task.doneAt != null)
        Text(
          'Done ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(task.doneAt! * 1000)).format(context)}',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.faded),
        ),
    ];

    final dragHandle = ReorderableDragStartListener(
      index: widget.index,
      child: Tooltip(
        message: 'Drag to reorder',
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.drag_indicator,
                size: 20,
                color: colors.faded.withValues(alpha: active ? 1 : 0.4)),
          ),
        ),
      ),
    );

    final line = Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        // The current task is tinted; the selected one a shade deeper.
        color: switch ((task.inFocus, widget.current)) {
          (true, _) => colors.highlight.withValues(
              alpha: colors.highlight.a * (widget.current ? 2 : 1.4)),
          (false, true) => colors.highlight,
          _ => null,
        },
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      // Room above and below for the (+) buttons on the edges.
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          number,
          const SizedBox(width: 4),
          checkbox,
          const SizedBox(width: 2),
          Expanded(
            // Tapping the text selects the task, double tapping edits it. The checkbox and the drag
            // handle stay outside, so a double tap never holds back a check off.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _select,
              onDoubleTap: () => editTask(context, widget.index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details,
                ),
              ),
            ),
          ),
          dragHandle,
        ],
      ),
    );

    // Each task is its own semantics node, so its parts move with it when tasks reorder. Without it
    // the web engine's semantics tree goes out of step when a reorder also changes a task's parts.
    return Semantics(
      container: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          children: [
            line,
            if (showInsert) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: _InsertButton(
                    tooltip: 'Add a task above',
                    onPressed: () => writeTask(context, index: widget.index),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: _InsertButton(
                    tooltip: 'Add a task below',
                    onPressed: () =>
                        writeTask(context, index: widget.index + 1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small (+) tab on the edge of a task, drawn like the note's own ink, to write a new task right
/// there.
class _InsertButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;

  const _InsertButton({required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = NoteColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.paper,
        shape: StadiumBorder(
            side: BorderSide(color: colors.faded.withValues(alpha: 0.6))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.add,
                size: 14, color: colors.ink, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }
}

/// How long a task waiting its turn is expected to take, and how much of that is left when it has
/// already been worked on.
class PlannedTime extends StatelessWidget {
  final int remainingSeconds;
  final int lengthSeconds;

  const PlannedTime(
      {super.key, required this.remainingSeconds, required this.lengthSeconds});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: NoteColors.of(context).faded,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final planned = formatClock(lengthSeconds);
    final text = switch (remainingSeconds) {
      final r when r == lengthSeconds => 'Expected $planned',
      final r when r < 0 => 'Expected $planned · +${formatClock(r)} over',
      final r => 'Left ${formatClock(r)} of $planned',
    };
    return Text(text, style: style);
  }
}

/// The countdown left, or the time over it, the time expected, and the total time tracked on the
/// current task.
class TaskClock extends StatelessWidget {
  final int remainingSeconds;
  final int totalSeconds;

  /// How long the task is expected to take; left out when 0.
  final int lengthSeconds;
  // Work on the task is paused.
  final bool paused;

  const TaskClock({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
    this.lengthSeconds = 0,
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
              : 'Left ${formatClock(remainingSeconds)}'
                  '${lengthSeconds > 0 ? ' of ${formatClock(lengthSeconds)}' : ''}',
          style: small?.copyWith(
            color: over ? theme.colorScheme.error : colors.ink,
            fontWeight: over ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          'Total ${formatClock(totalSeconds)}',
          style: small,
        ),
        if (paused)
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.pause,
                    size: 16, color: theme.colorScheme.tertiary),
              ),
              const TextSpan(text: 'Paused, not counting'),
            ]),
            style: small?.copyWith(
                color: theme.colorScheme.tertiary, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

/// Shown on top of the note while on a break: how long the break has lasted, and that no task's
/// clock is running. It goes away when work resumes, from here or the pause button, or when another
/// task is put first.
class BreakLine extends StatelessWidget {
  final TasksState state;

  const BreakLine({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NoteColors.of(context);
    final current = state.currentIndex;
    final seconds = state.breakSecondsAt(nowSeconds());
    final small = theme.textTheme.bodyMedium?.copyWith(
      color: colors.faded,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'On a break. No task clock is running.',
      child: Container(
        key: const ValueKey('break-line'),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Icon(Icons.coffee_outlined,
                  size: 20, color: theme.colorScheme.onTertiaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'On a break · ${formatClock(seconds)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text('No task clock is running', style: small),
                ],
              ),
            ),
            if (current >= 0)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: () => context
                      .read<TasksBloc>()
                      .add(ResumeTimerEvent(index: current)),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Back to work'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
