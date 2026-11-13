import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';
import '../timer.dart';
import 'pomodoro.dart';

/// Opens the focus view for the task with [taskId], with its Pomodoro where it was, on this device or
/// another, if it has one.
///
/// A paused clock starts right away when [autoStart] is set (the person chose to focus); otherwise
/// it waits for Resume, as when the app reopens a focus view that was cut short. A clock still
/// running elsewhere carries on either way.
Future<void> openFocus(BuildContext context, String taskId,
    {bool autoStart = true}) async {
  final settings = await PomodoroSettings.load();
  if (!context.mounted) return;
  final task = context
      .read<TasksBloc>()
      .state
      .tasks
      .where((t) => t.id.value == taskId)
      .firstOrNull;
  final record = PomodoroRecord.decode(task?.pomodoro);
  final (resumeFrom, endsAt) = record?.at(DateTime.now()) ?? (null, null);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BlocProvider(
      // A fresh focus cuts its sessions to fit the time the task has left.
      create: (_) => PomodoroCubit(
          settings: settings,
          taskSeconds: task?.taskTimerSeconds,
          resumeFrom: resumeFrom,
          endsAt: endsAt),
      child: FocusPage(
          taskId: taskId, autoStart: autoStart, resumed: record != null),
    ),
  ));
}

/// Pomodoro focus on one task: a big clock, the task's name, and the rest of the list as a quiet
/// reminder of what comes next.
///
/// Focusing on a task makes it the current one (it moves to the top). Its own timer runs while a
/// focus session runs, and pauses, logging a break, during Pomodoro breaks or when the clock is
/// paused. So History later shows the same work and breaks as the Pomodoro did.
///
/// The clock is kept in the task, as a [PomodoroRecord], whenever it starts, pauses or changes
/// phase, so it syncs: leaving the view, a crash or another device picks up where it was. Leaving
/// on purpose pauses it. A change made on another device while both show the view shows here too.
class FocusPage extends StatefulWidget {
  final String taskId;

  /// Whether the clock starts as the view opens.
  final bool autoStart;

  /// Whether the clock was picked up from where it was left, which the view says.
  final bool resumed;

  const FocusPage(
      {super.key,
      required this.taskId,
      this.autoStart = true,
      this.resumed = false});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  StreamSubscription<PomodoroPhase>? _phases;
  AudioPlayer? _player;
  StreamSubscription<PomodoroState>? _saves;
  StreamSubscription<TasksState>? _remote;
  late final TasksBloc _tasks;
  late final PomodoroCubit _pomodoro;
  // What the task's record last said, written here or read from another device.
  String? _lastKey;
  // Records this view wrote, recent ones first. The task list catches up with them a moment later,
  // possibly after a newer one was written, so they are never taken as another device's.
  final _written = <String>[];
  // Set once the task is marked done, so its clock is forgotten rather than kept.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final tasks = _tasks = context.read<TasksBloc>();
    final index = _indexIn(tasks.state);
    if (index > 0) tasks.add(MoveTaskEvent(fromIndex: index, toIndex: 0));
    // The Pomodoro clock replaces the task's own countdown while this view is open.
    tasks.add(SetFocusModeEvent(taskId: widget.taskId));
    final pomodoro = _pomodoro = context.read<PomodoroCubit>();
    _phases = pomodoro.phaseStarted.listen(_onPhase);
    _lastKey = PomodoroRecord.decode(_task(tasks.state)?.pomodoro)?.key;
    _keep(pomodoro.state);
    _saves = pomodoro.stream.listen(_keep);
    _remote = tasks.stream.listen(_onTasks);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || pomodoro.isClosed) return;
      // Opening the focus view is the decision to focus: the session starts right away. After
      // the first frame, so the task has moved on top and the listener below sees the start.
      if (widget.autoStart) {
        pomodoro.start();
      } else {
        // Waiting for Resume (or running on): the task's timer follows.
        _syncTaskTimer(pomodoro.state);
      }
      if (widget.resumed) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Picked up where you left off'),
            duration: Duration(seconds: 4),
          ));
      }
    });
  }

  @override
  void dispose() {
    _saves?.cancel();
    _remote?.cancel();
    if (!_tasks.isClosed) {
      _tasks.add(SetFocusModeEvent());
      if (_finished) {
        _tasks.add(SetPomodoroEvent(taskId: widget.taskId));
      } else {
        // Left on purpose: paused, and no longer open, for the next focus on this task.
        if (_pomodoro.state.running) _pomodoro.pause();
        _keep(_pomodoro.state, open: false);
      }
    }
    _phases?.cancel();
    _player?.dispose();
    super.dispose();
  }

  TaskState? _task(TasksState state) =>
      state.tasks.where((t) => t.id.value == widget.taskId).firstOrNull;

  /// Writes the clock into the task when it says something new; a running clock ticking down
  /// doesn't.
  void _keep(PomodoroState state, {bool open = true}) {
    if (_finished || _tasks.isClosed) return;
    final record = PomodoroRecord(
        state: state,
        endsAt: state.running ? _pomodoro.endsAt : null,
        open: open,
        savedAt: DateTime.now());
    if (record.key == _lastKey) return;
    _lastKey = record.key;
    final encoded = record.encode();
    _written.insert(0, encoded);
    if (_written.length > 20) _written.removeLast();
    _tasks.add(SetPomodoroEvent(taskId: widget.taskId, record: encoded));
  }

  /// Takes on the clock as another device left it.
  void _onTasks(TasksState state) {
    if (_finished || _pomodoro.isClosed) return;
    final encoded = _task(state)?.pomodoro;
    if (encoded == null || _written.contains(encoded)) return;
    final record = PomodoroRecord.decode(encoded);
    if (record == null || record.key == _lastKey) return;
    _lastKey = record.key;
    final (clock, endsAt) = record.at(DateTime.now());
    _pomodoro.apply(clock, endsAt);
  }

  int _indexIn(TasksState state) =>
      state.tasks.indexWhere((t) => t.id.value == widget.taskId);

  void _onPhase(PomodoroPhase phase) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(phase.isBreak
          ? '${phase.label}: step away for a moment'
          : 'Back to focus'),
      duration: const Duration(seconds: 6),
    ));
    if (!context.read<TasksBloc>().state.muted) _playSound();
  }

  Future<void> _playSound() async {
    try {
      _player ??= AudioPlayer();
      await _player!.play(AssetSource('alert.mp3'));
    } catch (_) {
      // No audio on this platform, or in tests: the message is enough.
    }
  }

  /// Keeps the task's own timer in step with the Pomodoro: running during focus, paused (and
  /// logging a break) otherwise. Only acts when the task is the top one, the only one timed.
  void _syncTaskTimer(PomodoroState pomodoro) {
    final tasks = context.read<TasksBloc>();
    if (_indexIn(tasks.state) != 0) return;
    final shouldRun = pomodoro.running && pomodoro.phase == PomodoroPhase.work;
    final running = tasks.state.tasks.first.running;
    if (shouldRun && !running) tasks.add(ResumeTimerEvent(index: 0));
    if (!shouldRun && running) tasks.add(StopTimerEvent(index: 0));
  }

  Future<void> _editSettings() async {
    final cubit = context.read<PomodoroCubit>();
    final result = await showDialog<(PomodoroSettings, bool)>(
      context: context,
      builder: (_) => PomodoroSettingsDialog(settings: cubit.state.settings),
    );
    if (result == null) return;
    final (updated, asDefault) = result;
    cubit.updateSettings(updated);
    if (asDefault) await updated.save();
  }

  void _markDone() {
    final tasks = context.read<TasksBloc>();
    final index = _indexIn(tasks.state);
    if (index < 0) return;
    final name = tasks.state.tasks[index].name;
    _finished = true;
    tasks.add(DoneTaskEvent(index: index));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(name.isEmpty ? 'Task done' : 'Done: $name'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => tasks.add(SetDoneEvent(index: index, done: false)),
      ),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PomodoroCubit>();
    return BlocListener<PomodoroCubit, PomodoroState>(
      listenWhen: (a, b) => a.running != b.running || a.phase != b.phase,
      listener: (context, state) => _syncTaskTimer(state),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): cubit.toggle,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Focus'),
              leading: BackButton(onPressed: () => Navigator.of(context).pop()),
              actions: [
                IconButton(
                  tooltip: 'Pomodoro settings',
                  icon: const Icon(Icons.tune),
                  onPressed: _editSettings,
                ),
              ],
            ),
            body: BlocBuilder<TasksBloc, TasksState>(
              builder: (context, tasks) {
                final index = _indexIn(tasks);
                if (index < 0) return const _TaskGone();
                final task = tasks.tasks[index];
                final others = [
                  for (final (i, t) in tasks.tasks.indexed)
                    // Done tasks stay on the note, struck through; only what is left is next.
                    if (i != index && !t.done) t
                ];
                return LayoutBuilder(builder: (context, constraints) {
                  final clock = _ClockPanel(
                    taskName: task.name,
                    onDone: _markDone,
                    onEditLengths: _editSettings,
                  );
                  final list = _UpNext(tasks: others);
                  if (constraints.maxWidth >= 840) {
                    return Row(children: [
                      Expanded(flex: 3, child: Center(child: clock)),
                      const VerticalDivider(width: 1),
                      SizedBox(
                          width: 320,
                          child:
                              Align(alignment: Alignment.topLeft, child: list)),
                    ]);
                  }
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [clock, const SizedBox(height: 24), list],
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The phase, the clock with its progress ring, and the controls.
class _ClockPanel extends StatelessWidget {
  final String taskName;
  final VoidCallback onDone;
  final VoidCallback onEditLengths;

  const _ClockPanel(
      {required this.taskName,
      required this.onDone,
      required this.onEditLengths});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cubit = context.read<PomodoroCubit>();
    return BlocBuilder<PomodoroCubit, PomodoroState>(
      builder: (context, p) {
        final color = p.phase.isBreak ? scheme.tertiary : scheme.primary;
        final session =
            p.completedSessions % p.settings.sessionsBeforeLongBreak +
                (p.phase == PomodoroPhase.work ? 1 : 0);
        final slices = p.taskSlices;
        final plan = describeTaskPlan(p);
        final sessionText = switch (p.phase) {
          PomodoroPhase.work when p.taskTimeUsed =>
            "Past the task's time: session ${p.completedSessions + 1}",
          PomodoroPhase.work when slices.isNotEmpty =>
            'Session ${p.completedSessions + 1} of ${slices.length} for this task',
          PomodoroPhase.work =>
            'Session $session of ${p.settings.sessionsBeforeLongBreak}',
          _ => '${p.completedSessions} done',
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                avatar: Icon(
                    p.phase.isBreak ? Icons.coffee_outlined : Icons.timer,
                    color: color,
                    size: 18),
                label: Text(p.phase.label),
              ),
              const SizedBox(height: 12),
              Text(
                taskName.isEmpty ? 'Unnamed task' : taskName,
                key: const Key('focusTaskName'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontStyle: taskName.isEmpty ? FontStyle.italic : null,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: p.progress,
                      strokeWidth: 10,
                      color: color,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    Center(
                      child: Text(
                        formatClock(p.remainingSeconds),
                        key: const Key('pomodoroClock'),
                        style: theme.textTheme.displayMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                sessionText,
                key: const Key('pomodoroSession'),
                style: theme.textTheme.bodyMedium,
              ),
              TextButton.icon(
                key: const Key('pomodoroLengths'),
                onPressed: onEditLengths,
                icon: const Icon(Icons.tune, size: 18),
                label: Text('${p.settings.workMinutes} min focus · '
                    '${p.settings.shortBreakMinutes} min break'),
              ),
              Text(
                plan ?? describeCycle(p.settings),
                key: const Key('pomodoroCycle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip:
                        'Restart this ${p.phase.isBreak ? 'break' : 'session'}',
                    onPressed: cubit.restartPhase,
                    icon: const Icon(Icons.restart_alt),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: cubit.toggle,
                    icon: Icon(p.running ? Icons.pause : Icons.play_arrow),
                    label: Text(p.running
                        ? 'Pause'
                        : (p.remainingSeconds == p.phaseSeconds
                            ? 'Start'
                            : 'Resume')),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: p.phase.isBreak ? 'Skip break' : 'Skip to break',
                    onPressed: cubit.skip,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark task done'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The rest of the list, read only, so what comes next stays in view without pulling attention.
class _UpNext extends StatelessWidget {
  final List<TaskState> tasks;

  const _UpNext({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Up next', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Text('Nothing else on the list.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          for (final (i, t) in tasks.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${i + 1}. ${t.name.isEmpty ? 'Unnamed task' : t.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskGone extends StatelessWidget {
  const _TaskGone();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This task is no longer on the list.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to the list'),
          ),
        ],
      ),
    );
  }
}

/// Edits the Pomodoro lengths. Returns the new settings and whether to keep them as the default for
/// the next focus, or null when cancelled.
class PomodoroSettingsDialog extends StatefulWidget {
  final PomodoroSettings settings;

  const PomodoroSettingsDialog({super.key, required this.settings});

  @override
  State<PomodoroSettingsDialog> createState() => _PomodoroSettingsDialogState();
}

class _PomodoroSettingsDialogState extends State<PomodoroSettingsDialog> {
  late final _work =
      TextEditingController(text: '${widget.settings.workMinutes}');
  late final _short =
      TextEditingController(text: '${widget.settings.shortBreakMinutes}');
  late final _long =
      TextEditingController(text: '${widget.settings.longBreakMinutes}');
  late final _sessions =
      TextEditingController(text: '${widget.settings.sessionsBeforeLongBreak}');
  bool _asDefault = true;

  @override
  void dispose() {
    for (final c in [_work, _short, _long, _sessions]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _read(TextEditingController c) {
    final v = int.tryParse(c.text);
    return v == null || v <= 0 ? null : v;
  }

  PomodoroSettings get _current => PomodoroSettings(
        workMinutes: _read(_work)!,
        shortBreakMinutes: _read(_short)!,
        longBreakMinutes: _read(_long)!,
        sessionsBeforeLongBreak: _read(_sessions)!,
      );

  bool get _valid =>
      [_work, _short, _long, _sessions].every((c) => _read(c) != null);

  Widget _field(String label, TextEditingController c, String suffix) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: _read(c) == null ? 'Enter a number above 0' : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pomodoro settings'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('Focus', _work, 'min'),
            _field('Short break', _short, 'min'),
            _field('Long break', _long, 'min'),
            _field('Long break every', _sessions, 'sessions'),
            if (_valid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  describeCycle(_current),
                  key: const Key('pomodoroDialogCycle'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _asDefault,
              onChanged: (v) => setState(() => _asDefault = v ?? false),
              title: const Text('Use these lengths from now on'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, (_current, _asDefault))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
