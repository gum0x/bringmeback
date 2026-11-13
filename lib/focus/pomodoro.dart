import 'dart:async';
import 'dart:convert';

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

  /// Work sessions finished on this task, since its focus began.
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

  /// Starts from [resumeFrom] when given, paused, else from a fresh focus session of [settings].
  PomodoroCubit({
    PomodoroSettings settings = const PomodoroSettings(),
    PomodoroState? resumeFrom,
    DateTime Function()? now,
    bool startTicking = true,
  })  : _now = now ?? DateTime.now,
        super(resumeFrom?.copyWith(running: false) ??
            PomodoroState.initial(settings)) {
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

/// Where each task's Pomodoro was left, so its focus view picks up there after the view was closed,
/// the app was quit or crashed, or the page was reloaded. Kept on this device, like the lengths.
///
/// A saved clock comes back paused, at the time it showed when it was saved: time away is an
/// interruption, not focus. One left alone for longer than [maxAge] is forgotten, and the next
/// focus on that task starts fresh.
class PomodoroMemory {
  // Not under "pomodoro.": PomodoroSettings keeps its lengths there, "pomodoro.sessions" among them.
  static const _sessionsKey = 'focusClocks';
  static const _openKey = 'focusOpen';
  static const maxAge = Duration(hours: 12);

  static Map<String, dynamic> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_sessionsKey);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static bool _fresh(Object? saved, DateTime now) {
    if (saved is! Map) return false;
    final at = saved['savedAt'];
    return at is int &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(at)) < maxAge;
  }

  /// The clock of the task with [taskId] as it was left, paused, or null when there is none, or it
  /// is too old.
  static Future<PomodoroState?> load(String taskId, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = _read(prefs)[taskId];
    if (!_fresh(saved, now ?? DateTime.now())) return null;
    try {
      final m = saved as Map;
      final settings = PomodoroSettings(
        workMinutes: m['work'] as int,
        shortBreakMinutes: m['shortBreak'] as int,
        longBreakMinutes: m['longBreak'] as int,
        sessionsBeforeLongBreak: m['sessions'] as int,
      );
      final phase = PomodoroPhase.values.byName(m['phase'] as String);
      final remaining = m['remaining'] as int;
      final completed = m['completed'] as int;
      if ([
        settings.workMinutes,
        settings.shortBreakMinutes,
        settings.longBreakMinutes,
        settings.sessionsBeforeLongBreak
      ].any((v) => v <= 0)) {
        return null;
      }
      return PomodoroState(
        settings: settings,
        phase: phase,
        remainingSeconds: remaining.clamp(1, settings.secondsFor(phase)),
        running: false,
        completedSessions: completed < 0 ? 0 : completed,
      );
    } catch (_) {
      return null;
    }
  }

  /// Keeps [state] as where the task with [taskId] was left. Clocks gone stale are dropped.
  static Future<void> save(String taskId, PomodoroState state,
      {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final at = now ?? DateTime.now();
    final sessions = _read(prefs)..removeWhere((_, v) => !_fresh(v, at));
    sessions[taskId] = {
      'phase': state.phase.name,
      'remaining': state.remainingSeconds,
      'completed': state.completedSessions,
      'work': state.settings.workMinutes,
      'shortBreak': state.settings.shortBreakMinutes,
      'longBreak': state.settings.longBreakMinutes,
      'sessions': state.settings.sessionsBeforeLongBreak,
      'savedAt': at.millisecondsSinceEpoch,
    };
    await prefs.setString(_sessionsKey, jsonEncode(sessions));
  }

  /// Drops the saved clock of the task with [taskId], so its next focus starts fresh.
  static Future<void> forget(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = _read(prefs);
    if (sessions.remove(taskId) == null) return;
    await prefs.setString(_sessionsKey, jsonEncode(sessions));
  }

  /// Notes which task's focus view is open, or null once it is closed on purpose. One still noted
  /// when the app starts was cut short, and opens again.
  static Future<void> setOpen(String? taskId) async {
    final prefs = await SharedPreferences.getInstance();
    if (taskId == null) {
      await prefs.remove(_openKey);
    } else {
      await prefs.setString(_openKey, taskId);
    }
  }

  /// The task whose focus view was open when the app last stopped, if it was not closed.
  static Future<String?> openTask() async =>
      (await SharedPreferences.getInstance()).getString(_openKey);
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
