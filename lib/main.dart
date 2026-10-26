import 'package:flutter/material.dart';
import 'package:bringmeback/timer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/tasks_bloc.dart';
import 'dart:async';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
        create: (_) => TasksBloc()..add(LoadStateEvent()),
        child: MaterialApp(
          title: 'bringmeback',
          theme: ThemeData(colorSchemeSeed: Colors.blue),
          darkTheme: ThemeData(
              colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
          home: const TasksStack(),
        ));
  }
}

/// Keyboard shortcuts, with the Alt variants for browsers, which keep Ctrl+N and Ctrl+D to
/// themselves.
const _shortcutHelp = [
  ('Ctrl+N or Alt+N', 'New task on top, with its timer running'),
  ('Ctrl+Shift+N or Alt+Shift+N', 'New task after the selected one'),
  ('Ctrl+D or Alt+D', 'Delete the selected task'),
  ('Enter', 'Finish editing a task name or timer'),
];

class TasksStack extends StatefulWidget {
  const TasksStack({super.key});

  @override
  State<TasksStack> createState() => _TasksStackState();
}

class _TasksStackState extends State<TasksStack> {
  StreamSubscription<String>? _timeUp;

  @override
  void initState() {
    super.initState();
    _timeUp = context.read<TasksBloc>().timeUp.listen((name) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(name.isEmpty ? "Time's up" : "Time's up: $name"),
        duration: const Duration(seconds: 10),
        showCloseIcon: true,
      ));
    });
  }

  @override
  void dispose() {
    _timeUp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksBloc = BlocProvider.of<TasksBloc>(context);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            AddNewTaskIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, alt: true): AddNewTaskIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, control: true):
            RemoveCurrentTaskIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, alt: true):
            RemoveCurrentTaskIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
            AddNewTaskNextIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, alt: true, shift: true):
            AddNewTaskNextIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AddNewTaskIntent: CallbackAction<AddNewTaskIntent>(
            onInvoke: (AddNewTaskIntent intent) => _addNewTask(tasksBloc),
          ),
          RemoveCurrentTaskIntent: CallbackAction<RemoveCurrentTaskIntent>(
            onInvoke: (RemoveCurrentTaskIntent intent) {
              final index = _focusedIndex(tasksBloc);
              if (index != null) removeTask(context, index);
              return null;
            },
          ),
          AddNewTaskNextIntent: CallbackAction<AddNewTaskNextIntent>(
            onInvoke: (AddNewTaskNextIntent intent) => _addNextTask(tasksBloc),
          )
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('bringmeback'),
              actions: [
                BlocBuilder<TasksBloc, TasksState>(
                  buildWhen: (a, b) => a.muted != b.muted,
                  builder: (context, state) => IconButton(
                    tooltip: state.muted ? 'Turn sounds on' : 'Mute sounds',
                    icon: Icon(
                        state.muted ? Icons.volume_off : Icons.volume_up),
                    onPressed: () => tasksBloc.add(ToggleMuteEvent()),
                  ),
                ),
                IconButton(
                  tooltip: 'Keyboard shortcuts',
                  icon: const Icon(Icons.keyboard_outlined),
                  onPressed: () => _showShortcuts(context),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              tooltip: 'New task on top (Ctrl+N)',
              onPressed: () => _addNewTask(tasksBloc),
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            ),
            body: BlocBuilder<TasksBloc, TasksState>(
                builder: (context, state) {
              if (state.tasks.isEmpty) return const _EmptyState();
              return ReorderableListView.builder(
                buildDefaultDragHandles: false,
                // Room for the floating button below the last task.
                padding: const EdgeInsets.only(top: 8, bottom: 88),
                itemCount: state.tasks.length,
                itemBuilder: (context, index) {
                  final task = state.tasks[index];
                  return Task(key: task.id, task: task, index: index);
                },
                onReorderItem: (int oldIndex, int newIndex) => tasksBloc
                    .add(MoveTaskEvent(fromIndex: oldIndex, toIndex: newIndex)),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// The task the shortcuts act on: the selected one, or the top one when none is.
  int? _focusedIndex(TasksBloc tasksBloc) {
    final tasks = tasksBloc.state.tasks;
    if (tasks.isEmpty) return null;
    final index = tasks.indexWhere((t) => t.inFocus);
    return index < 0 ? 0 : index;
  }

  void _addNewTask(TasksBloc taskBloc) {
    final taskId = newId();
    taskBloc.add(AddTaskOnTopEvent(
      name: "",
      id: ValueKey<String>(taskId),
    ));
  }

  void _addNextTask(TasksBloc tasksBloc) {
    final taskId = newId();
    tasksBloc.add(AddNextTaskEvent(
        id: ValueKey<String>(taskId),
        name: "",
        index: _focusedIndex(tasksBloc) ?? -1));
  }

  void _showShortcuts(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (keys, action) in _shortcutHelp)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '$keys  ',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: action),
                ])),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

/// Removes the task at [index] and offers to bring it back.
void removeTask(BuildContext context, int index) {
  final tasksBloc = context.read<TasksBloc>();
  final tasks = tasksBloc.state.tasks;
  if (index < 0 || index >= tasks.length) return;
  final task = tasks[index];
  tasksBloc.add(RemoveTaskEvent(index: index));
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(task.name.isEmpty ? 'Task deleted' : 'Deleted "${task.name}"'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () =>
          tasksBloc.add(RestoreTaskEvent(index: index, id: task.id)),
    ),
  ));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No tasks yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Add what you are working on with New task. '
              'Its timer starts right away.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class Task extends StatefulWidget {
  final TaskState task;
  final int index;

  const Task({
    super.key,
    required this.task,
    required this.index,
  });

  @override
  State<Task> createState() => _TaskState();
}

enum _TaskAction { restartCountdown, resetTotal, delete }

class _TaskState extends State<Task> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _debounce;
  late TextEditingController _minutesController;
  late FocusNode _minutesFocusNode;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.name);
    _focusNode = FocusNode()..addListener(_onNameFocusChange);
    _minutesController = TextEditingController(text: _lengthMinutes());
    _minutesFocusNode = FocusNode()
      ..addListener(() {
        if (!_minutesFocusNode.hasFocus) _commitMinutes();
      });
    // Save a name still waiting for the typing pause when the app goes to the background or the
    // tab closes.
    _lifecycle = AppLifecycleListener(onHide: _saveName, onPause: _saveName);

    if (widget.task.inFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(Task oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_minutesFocusNode.hasFocus &&
        oldWidget.task.timerLengthSeconds != widget.task.timerLengthSeconds) {
      _minutesController.text = _lengthMinutes();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _minutesController.dispose();
    _minutesFocusNode.dispose();
    super.dispose();
  }

  String _lengthMinutes() => (widget.task.timerLengthSeconds ~/ 60).toString();

  void _onNameFocusChange() {
    if (_focusNode.hasFocus) {
      context.read<TasksBloc>().add(FocusTaskEvent(index: widget.index));
    } else {
      _saveName();
    }
  }

  /// Saves the name now if a save is waiting for the typing pause.
  void _saveName() {
    if (!(_debounce?.isActive ?? false)) return;
    _debounce?.cancel();
    context
        .read<TasksBloc>()
        .add(UpdateTaskNameEvent(id: widget.task.id, newName: _controller.text));
  }

  /// Applies the minutes typed, or puts back the current length when they aren't a valid number.
  void _commitMinutes() {
    final minutes = int.tryParse(_minutesController.text);
    if (minutes == null || minutes <= 0) {
      _minutesController.text = _lengthMinutes();
      return;
    }
    if (minutes * 60 == widget.task.timerLengthSeconds) return;
    context
        .read<TasksBloc>()
        .add(UpdateTaskTimerEvent(index: widget.index, seconds: minutes * 60));
  }

  Widget _buildMinutesField() {
    return SizedBox(
      width: 96,
      child: TextField(
        controller: _minutesController,
        focusNode: _minutesFocusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
        decoration: const InputDecoration(
          labelText: 'Minutes',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (_) => _commitMinutes(),
      ),
    );
  }

  Widget _buildNameField(TasksBloc tasksBloc) {
    return TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 18),
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        maxLines: null,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: "What are you working on?",
        ),
        onSubmitted: (_) => _saveName(),
        onChanged: (value) {
          if (_debounce?.isActive ?? false) _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 500), () {
            tasksBloc.add(
                UpdateTaskNameEvent(id: widget.task.id, newName: value));
          });
        });
  }

  Widget _buildActions(TasksBloc tasksBloc) {
    final running = widget.task.running;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: running ? 'Pause timer' : 'Start timer',
          onPressed: () {
            if (running) {
              tasksBloc.add(StopTimerEvent(index: widget.index));
            } else {
              tasksBloc.add(ResumeTimerEvent(index: widget.index));
            }
          },
          icon: Icon(running ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Add task after this (Ctrl+Shift+N)',
          onPressed: () {
            final taskId = newId();
            tasksBloc.add(AddNextTaskEvent(
                index: widget.index, name: "", id: ValueKey<String>(taskId)));
          },
          icon: const Icon(Icons.playlist_add),
        ),
        PopupMenuButton<_TaskAction>(
          tooltip: 'More actions',
          onSelected: (action) {
            switch (action) {
              case _TaskAction.restartCountdown:
                tasksBloc.add(ResetTimerEvent(index: widget.index));
              case _TaskAction.resetTotal:
                tasksBloc.add(ResetTotalEvent(index: widget.index));
              case _TaskAction.delete:
                removeTask(context, widget.index);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _TaskAction.restartCountdown,
              child: ListTile(
                  leading: Icon(Icons.restart_alt),
                  title: Text('Restart countdown')),
            ),
            const PopupMenuItem(
              value: _TaskAction.resetTotal,
              child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Reset total time')),
            ),
            PopupMenuItem(
              value: _TaskAction.delete,
              child: ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: const Text('Delete task')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksBloc = context.read<TasksBloc>();
    final scheme = Theme.of(context).colorScheme;
    final task = widget.task;

    final dragHandle = ReorderableDragStartListener(
      index: widget.index,
      child: const Tooltip(
        message: 'Drag to reorder',
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.drag_indicator),
          ),
        ),
      ),
    );
    final clocks = TaskClock(
      remainingSeconds: task.taskTimerSeconds,
      totalSeconds: task.totalTaskTimerSeconds,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: task.running ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: task.inFocus
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, constraints) {
          // On a phone the name gets the full width, with the timer and actions below it.
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                Row(children: [
                  dragHandle,
                  const SizedBox(width: 8),
                  Expanded(child: _buildNameField(tasksBloc)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _buildMinutesField(),
                  const SizedBox(width: 12),
                  Expanded(child: clocks),
                  _buildActions(tasksBloc),
                ]),
              ],
            );
          }
          return Row(
            children: [
              dragHandle,
              const SizedBox(width: 8),
              Expanded(child: _buildNameField(tasksBloc)),
              const SizedBox(width: 16),
              _buildMinutesField(),
              const SizedBox(width: 16),
              SizedBox(width: 132, child: clocks),
              const SizedBox(width: 8),
              _buildActions(tasksBloc),
            ],
          );
        }),
      ),
    );
  }
}

/// The countdown left, or the time over it, and the total time tracked on a task.
class TaskClock extends StatelessWidget {
  final int remainingSeconds;
  final int totalSeconds;

  const TaskClock({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final over = remainingSeconds < 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          over
              ? '+${formatClock(remainingSeconds)} over'
              : 'Left ${formatClock(remainingSeconds)}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: tabular,
            color: over ? theme.colorScheme.error : null,
            fontWeight: over ? FontWeight.bold : null,
          ),
        ),
        Text(
          'Total ${formatClock(totalSeconds)}',
          style: theme.textTheme.bodySmall?.copyWith(fontFeatures: tabular),
        ),
      ],
    );
  }
}

class AddNewTaskIntent extends Intent {
  const AddNewTaskIntent();
}

class RemoveCurrentTaskIntent extends Intent {
  const RemoveCurrentTaskIntent();
}

class AddNewTaskNextIntent extends Intent {
  const AddNewTaskNextIntent();
}
