import 'package:bringmeback/focus/pomodoro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late PomodoroCubit cubit;

  const settings = PomodoroSettings(
      workMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
      sessionsBeforeLongBreak: 2);

  setUp(() {
    now = DateTime(2026, 11, 9, 9);
    cubit =
        PomodoroCubit(settings: settings, now: () => now, startTicking: false);
  });

  tearDown(() => cubit.close());

  void advance(Duration d) {
    now = now.add(d);
    cubit.tick();
  }

  test('starts as a focus session at full length, not running', () {
    expect(cubit.state.phase, PomodoroPhase.work);
    expect(cubit.state.remainingSeconds, 25 * 60);
    expect(cubit.state.running, isFalse);
  });

  test('counts down against the clock while running', () {
    cubit.start();
    advance(const Duration(minutes: 3, seconds: 20));
    expect(cubit.state.remainingSeconds, 25 * 60 - 200);
  });

  test('pausing keeps the time left; time while paused does not count', () {
    cubit.start();
    advance(const Duration(minutes: 5));
    cubit.pause();
    advance(const Duration(hours: 1));
    expect(cubit.state.remainingSeconds, 20 * 60);
    cubit.start();
    advance(const Duration(minutes: 1));
    expect(cubit.state.remainingSeconds, 19 * 60);
  });

  test('a finished session moves to a short break, then back to focus',
      () async {
    final phases = <PomodoroPhase>[];
    cubit.phaseStarted.listen(phases.add);
    cubit.start();
    advance(const Duration(minutes: 25));
    expect(cubit.state.phase, PomodoroPhase.shortBreak);
    expect(cubit.state.remainingSeconds, 5 * 60);
    expect(cubit.state.running, isTrue);
    expect(cubit.state.completedSessions, 1);
    advance(const Duration(minutes: 5));
    expect(cubit.state.phase, PomodoroPhase.work);
    await Future<void>.delayed(Duration.zero);
    expect(phases, [PomodoroPhase.shortBreak, PomodoroPhase.work]);
  });

  test('a long break comes after the set number of sessions', () {
    cubit.start();
    advance(const Duration(minutes: 25)); // session 1 done
    advance(const Duration(minutes: 5)); // short break done
    advance(const Duration(minutes: 25)); // session 2 done
    expect(cubit.state.phase, PomodoroPhase.longBreak);
    expect(cubit.state.remainingSeconds, 15 * 60);
    expect(cubit.state.completedSessions, 2);
  });

  test('skip moves on and keeps the clock paused when it was paused', () {
    cubit.skip();
    expect(cubit.state.phase, PomodoroPhase.shortBreak);
    expect(cubit.state.running, isFalse);
    expect(cubit.state.completedSessions, 1);
    cubit.skip();
    expect(cubit.state.phase, PomodoroPhase.work);
  });

  test('restart puts the phase back to its full length', () {
    cubit.start();
    advance(const Duration(minutes: 10));
    cubit.restartPhase();
    expect(cubit.state.remainingSeconds, 25 * 60);
    advance(const Duration(minutes: 1));
    expect(cubit.state.remainingSeconds, 24 * 60);
  });

  test('new lengths apply to a phase not yet started', () {
    cubit.updateSettings(settings.copyWith(workMinutes: 50));
    expect(cubit.state.remainingSeconds, 50 * 60);
  });

  test('new lengths leave a phase under way as it is', () {
    cubit.start();
    advance(const Duration(minutes: 5));
    cubit.updateSettings(settings.copyWith(workMinutes: 50));
    expect(cubit.state.remainingSeconds, 20 * 60);
    expect(cubit.state.settings.workMinutes, 50);
  });

  test('settings are saved and loaded on this device', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PomodoroSettings.load(), const PomodoroSettings());
    await settings.save();
    expect(await PomodoroSettings.load(), settings);
  });
}
