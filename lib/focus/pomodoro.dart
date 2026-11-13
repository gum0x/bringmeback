import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ticker.dart';

/// The lengths of a Pomodoro cycle, in minutes. Kept on this device, like mute.
class PomodoroSettings {
  final int workMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// Work sessions before a long break.
  final int sessionsBeforeLongBreak;

  const PomodoroSettings({
    this.workMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.sessionsBeforeLongBreak = 4,
  });

  PomodoroSettings copyWith({
    int? workMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? sessionsBeforeLongBreak,
  }) =>
      PomodoroSettings(
        workMinutes: workMinutes ?? this.workMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        sessionsBeforeLongBreak:
            sessionsBeforeLongBreak ?? this.sessionsBeforeLongBreak,
      );

  int secondsFor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.work => workMinutes * 60,
        PomodoroPhase.shortBreak => shortBreakMinutes * 60,
        PomodoroPhase.longBreak => longBreakMinutes * 60,
      };

  /// A whole cycle, up to the end of its long break: every focus session, the short breaks between
  /// them, and the long break.
  int get cycleMinutes =>
      sessionsBeforeLongBreak * workMinutes +
      (sessionsBeforeLongBreak - 1) * shortBreakMinutes +
      longBreakMinutes;

  /// Of [cycleMinutes], the time spent in focus.
  int get cycleFocusMinutes => sessionsBeforeLongBreak * workMinutes;

  static const _prefix = 'pomodoro.';

  static Future<PomodoroSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = PomodoroSettings();
    int read(String key, int fallback) {
      final v = prefs.getInt('$_prefix$key');
      return v == null || v <= 0 ? fallback : v;
    }

    return PomodoroSettings(
      workMinutes: read('work', d.workMinutes),
      shortBreakMinutes: read('shortBreak', d.shortBreakMinutes),
      longBreakMinutes: read('longBreak', d.longBreakMinutes),
      sessionsBeforeLongBreak: read('sessions', d.sessionsBeforeLongBreak),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_prefix}work', workMinutes);
    await prefs.setInt('${_prefix}shortBreak', shortBreakMinutes);
    await prefs.setInt('${_prefix}longBreak', longBreakMinutes);
    await prefs.setInt('${_prefix}sessions', sessionsBeforeLongBreak);
  }

  @override
  bool operator ==(Object other) =>
      other is PomodoroSettings &&
      other.workMinutes == workMinutes &&
      other.shortBreakMinutes == shortBreakMinutes &&
      other.longBreakMinutes == longBreakMinutes &&
      other.sessionsBeforeLongBreak == sessionsBeforeLongBreak;

  @override
  int get hashCode => Object.hash(workMinutes, shortBreakMinutes,
      longBreakMinutes, sessionsBeforeLongBreak);
}

enum PomodoroPhase {
  work('Focus'),
  shortBreak('Short break'),
  longBreak('Long break');

  final String label;
  const PomodoroPhase(this.label);

  bool get isBreak => this != PomodoroPhase.work;
}

/// The focus sessions that fit [taskSeconds]: full sessions of [workSeconds], and the rest in a
/// shorter last one. A rest of 5 minutes or less joins the session before it rather than making a
/// slice too short to start on.
List<int> sliceTask(int taskSeconds, int workSeconds) {
  final slices = <int>[];
  var left = taskSeconds;
  while (left > 0) {
    final slice = left - workSeconds <= _smallestSlice ? left : workSeconds;
    slices.add(slice);
    left -= slice;
  }
  return slices;
}

const _smallestSlice = 5 * 60;

/// How long the session should be after [focusedSeconds] of focus on a task with [taskSeconds]
/// given: the next slice of [sliceTask], or a full session when there is no task time, or it is
/// used up.
int workSecondsFor(PomodoroSettings settings, int? taskSeconds, int focusedSeconds) {
  final work = settings.secondsFor(PomodoroPhase.work);
  if (taskSeconds == null) return work;
  final left = taskSeconds - focusedSeconds;
  if (left <= 0) return work;
  return sliceTask(left, work).first;
}

class PomodoroState {
  final PomodoroSettings settings;
  final PomodoroPhase phase;
  final int remainingSeconds;
  final bool running;

  /// Work sessions finished since the focus view opened.
  final int completedSessions;

  /// The time the task has left, when focus started; the sessions are cut to fit it. Null when the
  /// task has no time left to fit.
  final int? taskSeconds;

  /// Focus time from sessions already over, counted against [taskSeconds].
  final int focusedSeconds;

  /// The length of the current focus session: a full one, or a slice of the task's time.
  final int workSeconds;

  const PomodoroState({
    required this.settings,
    required this.phase,
    required this.remainingSeconds,
    required this.running,
    required this.completedSessions,
    this.taskSeconds,
    this.focusedSeconds = 0,
    required this.workSeconds,
  });

  factory PomodoroState.initial(PomodoroSettings settings, {int? taskSeconds}) {
    final work = workSecondsFor(settings, taskSeconds, 0);
    return PomodoroState(
      settings: settings,
      phase: PomodoroPhase.work,
      remainingSeconds: work,
      running: false,
      completedSessions: 0,
      taskSeconds: taskSeconds,
      workSeconds: work,
    );
  }

  int get phaseSeconds =>
      phase == PomodoroPhase.work ? workSeconds : settings.secondsFor(phase);

  /// The focus sessions planned for the task's time, from the start: e.g. 25, 25 and 10 minutes for
  /// an hour. Empty when there is no task time to fit.
  List<int> get taskSlices {
    final task = taskSeconds;
    return task == null ? const [] : sliceTask(task, settings.secondsFor(PomodoroPhase.work));
  }

  /// Whether the focus time already covers all the task's time.
  bool get taskTimeUsed {
    final task = taskSeconds;
    return task != null && focusedSeconds >= task;
  }

  /// How much of the phase is done, from 0 to 1.
  double get progress =>
      phaseSeconds == 0 ? 0 : 1 - remainingSeconds / phaseSeconds;

  PomodoroState copyWith({
    PomodoroSettings? settings,
    PomodoroPhase? phase,
    int? remainingSeconds,
    bool? running,
    int? completedSessions,
    int? workSeconds,
  }) =>
      PomodoroState(
        settings: settings ?? this.settings,
        phase: phase ?? this.phase,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        running: running ?? this.running,
        completedSessions: completedSessions ?? this.completedSessions,
        taskSeconds: taskSeconds,
        focusedSeconds: focusedSeconds,
        workSeconds: workSeconds ?? this.workSeconds,
      );
}

/// The Pomodoro clock: focus, short break, focus, ... and a long break after every few sessions.
///
/// Time is measured against the clock, not counted in ticks, so a slow or sleeping device still
/// shows the right time. A phase that runs out moves on to the next one, which starts running.
class PomodoroCubit extends Cubit<PomodoroState> {
  final DateTime Function() _now;
  SecondTicker? _tick;
  // When the running phase ends; null while paused.
  DateTime? _endsAt;
  final StreamController<PomodoroPhase> _phaseStarted =
      StreamController<PomodoroPhase>.broadcast();

  /// [taskSeconds] is the time the task has left: focus sessions are cut to fit it.
  PomodoroCubit({
    PomodoroSettings settings = const PomodoroSettings(),
    int? taskSeconds,
    DateTime Function()? now,
    bool startTicking = true,
  })  : _now = now ?? DateTime.now,
        super(PomodoroState.initial(settings,
            taskSeconds: taskSeconds == null || taskSeconds <= 0 ? null : taskSeconds)) {
    if (startTicking) {
      // The countdown turns over at the end time's milliseconds, not the wall clock's.
      _tick = SecondTicker(tick,
          turnoverMs: () => (_endsAt?.millisecondsSinceEpoch ?? 0) % 1000);
    }
  }

  /// Each phase the clock moves into when the previous one runs out or is skipped, after the
  /// state has changed. Starting, pausing and resetting within a phase don't count.
  Stream<PomodoroPhase> get phaseStarted => _phaseStarted.stream;

  void start() {
    if (state.running) return;
    _endsAt = _now().add(Duration(seconds: state.remainingSeconds));
    emit(state.copyWith(running: true));
  }

  void pause() {
    if (!state.running) return;
    final remaining = _remaining();
    _endsAt = null;
    emit(state.copyWith(running: false, remainingSeconds: remaining));
  }

  void toggle() => state.running ? pause() : start();

  /// Ends the current phase now and moves to the next one, keeping it running or paused.
  void skip() => _advance(running: state.running);

  /// Puts the current phase back to its full length.
  void restartPhase() {
    final seconds = state.phaseSeconds;
    if (state.running) _endsAt = _now().add(Duration(seconds: seconds));
    emit(state.copyWith(remainingSeconds: seconds));
  }

  /// Applies new lengths. A phase not yet started takes the new length; one under way keeps going.
  void updateSettings(PomodoroSettings settings) {
    final untouched =
        !state.running && state.remainingSeconds == state.phaseSeconds;
    final work =
        workSecondsFor(settings, state.taskSeconds, state.focusedSeconds);
    final next = state.copyWith(
        settings: settings, workSeconds: untouched ? work : null);
    emit(next.copyWith(
        remainingSeconds: untouched ? next.phaseSeconds : null));
  }

  /// Brings the shown time up to date, and moves on when the phase has run out.
  void tick() {
    if (!state.running) return;
    final remaining = _remaining();
    if (remaining <= 0) {
      _advance(running: true);
    } else if (remaining != state.remainingSeconds) {
      emit(state.copyWith(remainingSeconds: remaining));
    }
  }

  int _remaining() {
    final endsAt = _endsAt;
    if (endsAt == null) return state.remainingSeconds;
    final ms = endsAt.difference(_now()).inMilliseconds;
    // Round up, so the clock shows 00:01 until the last second is over.
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  /// The phase after the current one. A skipped work session counts as done too: skipping says
  /// "I'm finished with this one".
  void _advance({required bool running}) {
    final s = state;
    PomodoroPhase next;
    var completed = s.completedSessions;
    var focused = s.focusedSeconds;
    if (s.phase == PomodoroPhase.work) {
      completed++;
      // What was worked of the session, all of it unless skipped early.
      focused += s.workSeconds - _remaining();
      next = completed % s.settings.sessionsBeforeLongBreak == 0
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
    } else {
      next = PomodoroPhase.work;
    }
    final work = workSecondsFor(s.settings, s.taskSeconds, focused);
    final seconds = next == PomodoroPhase.work ? work : s.settings.secondsFor(next);
    _endsAt = running ? _now().add(Duration(seconds: seconds)) : null;
    emit(PomodoroState(
      settings: s.settings,
      phase: next,
      remainingSeconds: seconds,
      running: running,
      completedSessions: completed,
      taskSeconds: s.taskSeconds,
      focusedSeconds: focused,
      workSeconds: work,
    ));
    _phaseStarted.add(next);
  }

  @override
  Future<void> close() {
    _tick?.cancel();
    _phaseStarted.close();
    return super.close();
  }
}

/// Minutes as "45 min", "2 h" or "2 h 10 min".
String formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// What a whole cycle of [settings] adds up to, e.g. "Full cycle 2 h 10 min: 1 h 40 min of focus in
/// 4 sessions".
String describeCycle(PomodoroSettings settings) {
  final sessions = settings.sessionsBeforeLongBreak;
  return 'Full cycle ${formatMinutes(settings.cycleMinutes)}: '
      '${formatMinutes(settings.cycleFocusMinutes)} of focus in $sessions '
      '${sessions == 1 ? 'session' : 'sessions'}';
}

/// The plan for a task's time, e.g. "Fits the task's 1 h: 25 + 25 + 10 min of focus, 1 h 10 min
/// with breaks". Null when there is no task time to fit.
String? describeTaskPlan(PomodoroState state) {
  final task = state.taskSeconds;
  if (task == null) return null;
  final slices = [for (final s in state.taskSlices) (s / 60).round()];
  final settings = state.settings;
  var breaks = 0;
  for (var i = 1; i < slices.length; i++) {
    breaks += i % settings.sessionsBeforeLongBreak == 0
        ? settings.longBreakMinutes
        : settings.shortBreakMinutes;
  }
  final focus = slices.fold(0, (a, b) => a + b);
  return "Fits the task's ${formatMinutes((task / 60).round())}: "
      '${slices.join(' + ')} min of focus'
      '${breaks == 0 ? '' : ', ${formatMinutes(focus + breaks)} with breaks'}';
}
