import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class PomodoroState {
  final PomodoroSettings settings;
  final PomodoroPhase phase;
  final int remainingSeconds;
  final bool running;

  /// Work sessions finished since the focus view opened.
  final int completedSessions;

  const PomodoroState({
    required this.settings,
    required this.phase,
    required this.remainingSeconds,
    required this.running,
    required this.completedSessions,
  });

  factory PomodoroState.initial(PomodoroSettings settings) => PomodoroState(
        settings: settings,
        phase: PomodoroPhase.work,
        remainingSeconds: settings.secondsFor(PomodoroPhase.work),
        running: false,
        completedSessions: 0,
      );

  int get phaseSeconds => settings.secondsFor(phase);

  /// How much of the phase is done, from 0 to 1.
  double get progress =>
      phaseSeconds == 0 ? 0 : 1 - remainingSeconds / phaseSeconds;

  PomodoroState copyWith({
    PomodoroSettings? settings,
    PomodoroPhase? phase,
    int? remainingSeconds,
    bool? running,
    int? completedSessions,
  }) =>
      PomodoroState(
        settings: settings ?? this.settings,
        phase: phase ?? this.phase,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        running: running ?? this.running,
        completedSessions: completedSessions ?? this.completedSessions,
      );
}

/// The Pomodoro clock: focus, short break, focus, ... and a long break after every few sessions.
///
/// Time is measured against the clock, not counted in ticks, so a slow or sleeping device still
/// shows the right time. A phase that runs out moves on to the next one, which starts running.
class PomodoroCubit extends Cubit<PomodoroState> {
  final DateTime Function() _now;
  Timer? _tick;
  // When the running phase ends; null while paused.
  DateTime? _endsAt;
  final StreamController<PomodoroPhase> _phaseStarted =
      StreamController<PomodoroPhase>.broadcast();

  PomodoroCubit({
    PomodoroSettings settings = const PomodoroSettings(),
    DateTime Function()? now,
    bool startTicking = true,
  })  : _now = now ?? DateTime.now,
        super(PomodoroState.initial(settings)) {
    if (startTicking) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => tick());
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
    emit(state.copyWith(
      settings: settings,
      remainingSeconds: untouched ? settings.secondsFor(state.phase) : null,
    ));
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
    if (s.phase == PomodoroPhase.work) {
      completed++;
      next = completed % s.settings.sessionsBeforeLongBreak == 0
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
    } else {
      next = PomodoroPhase.work;
    }
    final seconds = s.settings.secondsFor(next);
    _endsAt = running ? _now().add(Duration(seconds: seconds)) : null;
    emit(PomodoroState(
      settings: s.settings,
      phase: next,
      remainingSeconds: seconds,
      running: running,
      completedSessions: completed,
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
