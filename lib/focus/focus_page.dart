import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';
import '../timer.dart';
import 'pomodoro.dart';

/// Opens the focus view for the task with [taskId].
Future<void> openFocus(BuildContext context, String taskId) async {
  final settings = await PomodoroSettings.load();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BlocProvider(
      create: (_) => PomodoroCubit(settings: settings),
      child: FocusPage(taskId: taskId),
    ),
  ));
}

/// Pomodoro focus on one task: a big clock, the task's name, and the rest of the list as a quiet
/// reminder of what comes next.
///
/// Focusing on a task makes it the current one (it moves to the top). Its own timer runs while a
/// focus session runs, and pauses, logging a break, during Pomodoro breaks or when the clock is
/// paused. So History later shows the same work and breaks as the Pomodoro did.
class FocusPage extends StatefulWidget {
  final String taskId;

  const FocusPage({super.key, required this.taskId});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  StreamSubscription<PomodoroPhase>? _phases;
  AudioPlayer? _player;
  late final TasksBloc _tasks;

  @override
  void initState() {
    super.initState();
    final tasks = _tasks = context.read<TasksBloc>();
    final index = _indexIn(tasks.state);
    if (index > 0) tasks.add(MoveTaskEvent(fromIndex: index, toIndex: 0));
    // The Pomodoro clock replaces the task's own countdown while this view is open.
    tasks.add(SetFocusModeEvent(taskId: widget.taskId));
    final pomodoro = context.read<PomodoroCubit>();
    _phases = pomodoro.phaseStarted.listen(_onPhase);
    // Opening the focus view is the decision to focus: the first session starts right away. After
    // the first frame, so the task has moved on top and the listener below sees the start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !pomodoro.isClosed) pomodoro.start();
    });
  }

  @override
  void dispose() {
    if (!_tasks.isClosed) _tasks.add(SetFocusModeEvent());
    _phases?.cancel();
    _player?.dispose();
    super.dispose();
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
                p.phase == PomodoroPhase.work
                    ? 'Session $session of ${p.settings.sessionsBeforeLongBreak}'
                    : '${p.completedSessions} done',
                style: theme.textTheme.bodyMedium,
              ),
              TextButton.icon(
                key: const Key('pomodoroLengths'),
                onPressed: onEditLengths,
                icon: const Icon(Icons.tune, size: 18),
                label: Text('${p.settings.workMinutes} min focus · '
                    '${p.settings.shortBreakMinutes} min break'),
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
              ? () => Navigator.pop(context, (
                    PomodoroSettings(
                      workMinutes: _read(_work)!,
                      shortBreakMinutes: _read(_short)!,
                      longBreakMinutes: _read(_long)!,
                      sessionsBeforeLongBreak: _read(_sessions)!,
                    ),
                    _asDefault
                  ))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
