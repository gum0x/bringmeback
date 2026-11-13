import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/tasks_bloc.dart';
import 'history/history_page.dart';
import 'note/note_view.dart';
import 'note/task_line.dart';
import 'settings/settings_page.dart';
import 'sync/sync_cubit.dart';
import 'sync/sync_page.dart';
import 'version/build_info.dart';
import 'version/platform.dart' as platform;
import 'version/update_cubit.dart';
import 'dart:async';

export 'note/note_view.dart' show NoteView, CarryOverPanel, TearOffView;
export 'note/paper.dart' show StrikeText;
export 'note/task_line.dart' show TaskLine, TaskClock;

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => TasksBloc()..add(LoadStateEvent())),
          // Not lazy: sync starts with the app, not when the Devices page first opens.
          BlocProvider(
              lazy: false,
              create: (context) =>
                  SyncCubit(document: context.read<TasksBloc>().document)
                    ..load()),
          BlocProvider(lazy: false, create: (_) => UpdateCubit()..load()),
        ],
        child: _AppLifecycle(
            child: MaterialApp(
          title: 'bringmeback',
          scaffoldMessengerKey: _messenger,
          theme: ThemeData(colorSchemeSeed: Colors.blue),
          darkTheme: ThemeData(
              colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
          // The app is laid out for portrait: on a wide window it stays a column in the middle.
          builder: (context, child) => _PortraitFrame(child: child!),
          home: const TasksStack(),
        )));
  }
}

final _messenger = GlobalKey<ScaffoldMessengerState>();

/// Tells sync when the app goes to the background and comes back, so it reconnects right away
/// after a phone kept the app (or a browser kept the tab) asleep, and checks for a newer version
/// then. Shows a banner when a newer version is out.
class _AppLifecycle extends StatefulWidget {
  final Widget child;

  const _AppLifecycle({required this.child});

  @override
  State<_AppLifecycle> createState() => _AppLifecycleState();
}

class _AppLifecycleState extends State<_AppLifecycle> {
  late final AppLifecycleListener _listener;

  /// The newer build the banner was shown for, so it shows once per build.
  BuildInfo? _announced;

  @override
  void initState() {
    super.initState();
    final sync = context.read<SyncCubit>();
    final updates = context.read<UpdateCubit>();
    _listener = AppLifecycleListener(
      onHide: sync.paused,
      onShow: () {
        sync.resumed();
        updates.check();
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _updated(UpdateState state) {
    final latest = state.latest;
    final messenger = _messenger.currentState;
    if (!state.newer || latest == null || messenger == null) return;
    if (_announced != null && _announced!.sameAs(latest)) return;
    _announced = latest;
    messenger.showMaterialBanner(MaterialBanner(
      leading: const Icon(Icons.system_update),
      content: Text(platform.canReload
          ? 'A newer version of bringmeback is out (${latest.label}). '
              'This one is ${BuildInfo.current.label}.'
          : 'bringmeback ${latest.label} is out. This is ${BuildInfo.current.label}.'),
      actions: [
        TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Later')),
        if (platform.canReload)
          TextButton(onPressed: platform.reloadApp, child: const Text('Reload')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) => BlocListener<UpdateCubit, UpdateState>(
      listener: (context, state) => _updated(state), child: widget.child);
}

/// Keyboard shortcuts, with the Alt variants for browsers, which keep Ctrl+N and Ctrl+D to
/// themselves.
const _shortcutHelp = [
  ('Ctrl+N or Alt+N', 'New task on top, with its timer running'),
  ('Ctrl+Shift+N or Alt+Shift+N', 'New task after the selected one'),
  ('Ctrl+Enter or Alt+Enter', 'Check off the selected task, or uncheck it'),
  ('Ctrl+D or Alt+D', 'Delete the selected task'),
  ('Enter', 'Save the task in the task dialog'),
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
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            ToggleDoneIntent(),
        SingleActivator(LogicalKeyboardKey.enter, alt: true):
            ToggleDoneIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AddNewTaskIntent: CallbackAction<AddNewTaskIntent>(
            onInvoke: (AddNewTaskIntent intent) =>
                writeTask(context, onTop: true),
          ),
          ToggleDoneIntent: CallbackAction<ToggleDoneIntent>(
            onInvoke: (ToggleDoneIntent intent) {
              final index = _focusedIndex(tasksBloc);
              if (index == null) return null;
              tasksBloc.add(SetDoneEvent(
                  index: index, done: !tasksBloc.state.tasks[index].done));
              return null;
            },
          ),
          RemoveCurrentTaskIntent: CallbackAction<RemoveCurrentTaskIntent>(
            onInvoke: (RemoveCurrentTaskIntent intent) {
              final index = _focusedIndex(tasksBloc);
              if (index != null) removeTask(context, index);
              return null;
            },
          ),
          AddNewTaskNextIntent: CallbackAction<AddNewTaskNextIntent>(
            onInvoke: (AddNewTaskNextIntent intent) => writeTask(context,
                index: (_focusedIndex(tasksBloc) ?? -1) + 1),
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
                    icon:
                        Icon(state.muted ? Icons.volume_off : Icons.volume_up),
                    onPressed: () => tasksBloc.add(ToggleMuteEvent()),
                  ),
                ),
                IconButton(
                  tooltip: 'History',
                  icon: const Icon(Icons.history),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HistoryPage())),
                ),
                IconButton(
                  tooltip: 'Devices',
                  icon: const Icon(Icons.devices),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SyncPage())),
                ),
                IconButton(
                  tooltip: 'Keyboard shortcuts',
                  icon: const Icon(Icons.keyboard_outlined),
                  onPressed: () => _showShortcuts(context),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage())),
                ),
              ],
            ),
            floatingActionButton: BlocBuilder<TasksBloc, TasksState>(
              builder: (context, state) => !state.loaded || state.needsTearOff()
                  ? const SizedBox.shrink()
                  : FloatingActionButton.extended(
                      tooltip: 'New task on top (Ctrl+N)',
                      elevation: 0,
                      onPressed: () => writeTask(context, onTop: true),
                      icon: const Icon(Icons.add),
                      label: const Text('New task'),
                    ),
            ),
            // New task sits at the end of the bottom bar, with the task actions.
            floatingActionButtonLocation:
                FloatingActionButtonLocation.endContained,
            bottomNavigationBar: BlocBuilder<TasksBloc, TasksState>(
              buildWhen: (a, b) =>
                  a.needsTearOff() != b.needsTearOff() || a.loaded != b.loaded,
              builder: (context, state) => !state.loaded || state.needsTearOff()
                  ? const SizedBox.shrink()
                  : const NoteToolbar(),
            ),
            body: const NoteView(),
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

class AddNewTaskIntent extends Intent {
  const AddNewTaskIntent();
}

class RemoveCurrentTaskIntent extends Intent {
  const RemoveCurrentTaskIntent();
}

class AddNewTaskNextIntent extends Intent {
  const AddNewTaskNextIntent();
}

class ToggleDoneIntent extends Intent {
  const ToggleDoneIntent();
}

/// Keeps the app portrait-shaped on wide windows: a column of phone-like width in the middle, with
/// a quiet margin on both sides.
class _PortraitFrame extends StatelessWidget {
  final Widget child;

  const _PortraitFrame({required this.child});

  static const maxWidth = 520.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.12), blurRadius: 16),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
