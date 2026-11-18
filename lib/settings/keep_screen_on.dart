import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../bloc/tasks_bloc.dart';

/// Turns the system's "keep the screen on" hold on or off. The default asks the platform: a wake
/// lock in the browser, the idle timer on iOS, the window flag on Android, and the system's
/// sleep inhibitor on macOS, Windows and Linux.
typedef ScreenAwakeSetter = Future<void> Function(bool awake);

Future<void> _platformSetter(bool awake) => WakelockPlus.toggle(enable: awake);

class KeepScreenOnState {
  /// Whether the setting is on. On by default.
  final bool enabled;

  /// Whether a task's timer is running, on this device or (through sync) another one.
  final bool taskRunning;

  /// Whether a focus view's Pomodoro clock is running, a break included.
  final bool focusRunning;

  const KeepScreenOnState(
      {this.enabled = true, this.taskRunning = false, this.focusRunning = false});

  /// Whether the screen should stay on now.
  bool get awake => enabled && (taskRunning || focusRunning);

  KeepScreenOnState copyWith({bool? enabled, bool? taskRunning, bool? focusRunning}) =>
      KeepScreenOnState(
        enabled: enabled ?? this.enabled,
        taskRunning: taskRunning ?? this.taskRunning,
        focusRunning: focusRunning ?? this.focusRunning,
      );
}

/// Keeps the screen from dimming and locking while a timer runs, so the clock stays in view. The
/// setting is saved on this device and is not synced. The system lets the screen go when the app
/// is in the background; the hold comes back when the app does.
class KeepScreenOnCubit extends Cubit<KeepScreenOnState> {
  static const _key = 'keepScreenOn';

  final ScreenAwakeSetter _set;
  StreamSubscription<TasksState>? _tasks;

  /// What was last asked of the platform, so it's asked again only on a change.
  bool? _applied;

  KeepScreenOnCubit({TasksBloc? tasks, ScreenAwakeSetter? setAwake})
      : _set = setAwake ?? _platformSetter,
        super(const KeepScreenOnState()) {
    if (tasks != null) {
      _onTasks(tasks.state);
      _tasks = tasks.stream.listen(_onTasks);
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (isClosed) return;
    emit(state.copyWith(enabled: prefs.getBool(_key) ?? true));
  }

  Future<void> setEnabled(bool on) async {
    emit(state.copyWith(enabled: on));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }

  /// Called by the focus view while its clock runs or stops.
  void setFocusRunning(bool running) {
    if (isClosed) return;
    emit(state.copyWith(focusRunning: running));
  }

  /// Asks the platform again, as when the app comes back to the foreground: some browsers drop
  /// the wake lock when the tab is hidden.
  void reapply() {
    _applied = null;
    _apply(state);
  }

  void _onTasks(TasksState tasks) {
    final running = tasks.tasks.any((t) => t.running);
    if (running != state.taskRunning) emit(state.copyWith(taskRunning: running));
  }

  @override
  void onChange(Change<KeepScreenOnState> change) {
    super.onChange(change);
    _apply(change.nextState);
  }

  void _apply(KeepScreenOnState state) {
    final awake = state.awake;
    if (awake == _applied) return;
    _applied = awake;
    // A platform without a wake lock (an old browser, a desktop without the service) just lets
    // the screen sleep as before.
    _set(awake).catchError((Object _) {});
  }

  @override
  Future<void> close() async {
    await _tasks?.cancel();
    if (_applied == true) {
      _applied = false;
      await _set(false).catchError((Object _) {});
    }
    return super.close();
  }
}
