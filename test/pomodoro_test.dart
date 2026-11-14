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

  group('fitting a task', () {
    test('the task time is cut into full sessions and a shorter last one', () {
      expect(sliceTask(60 * 60, 25 * 60), [25 * 60, 25 * 60, 10 * 60]);
      expect(sliceTask(20 * 60, 25 * 60), [20 * 60]);
      expect(sliceTask(50 * 60, 25 * 60), [25 * 60, 25 * 60]);
      // A rest of 5 minutes or less joins the session before it.
      expect(sliceTask(28 * 60, 25 * 60), [28 * 60]);
      expect(sliceTask(55 * 60, 25 * 60), [25 * 60, 30 * 60]);
    });

    test('sessions follow the slices, breaks stay as they are', () {
      final c = PomodoroCubit(
          settings: settings,
          taskSeconds: 60 * 60,
          now: () => now,
          startTicking: false);
      addTearDown(c.close);
      void go(Duration d) {
        now = now.add(d);
        c.tick();
      }

      expect(c.state.remainingSeconds, 25 * 60);
      expect(describeTaskPlan(c.state),
          "Fits the task's 1 h: 25 + 25 + 10 min of focus, 1 h 20 min with breaks");
      c.start();
      go(const Duration(minutes: 25));
      expect(c.state.phase, PomodoroPhase.shortBreak);
      expect(c.state.remainingSeconds, 5 * 60);
      go(const Duration(minutes: 5));
      expect(c.state.remainingSeconds, 25 * 60);
      go(const Duration(minutes: 25));
      // Second session done: the long break, since it comes every 2 here.
      expect(c.state.phase, PomodoroPhase.longBreak);
      go(const Duration(minutes: 15));
      expect(c.state.phase, PomodoroPhase.work);
      expect(c.state.remainingSeconds, 10 * 60, reason: 'the last slice');
      expect(c.state.taskTimeUsed, isFalse);
      go(const Duration(minutes: 10));
      go(const Duration(minutes: 5));
      // The task's time is used up: on past it, sessions are full length again.
      expect(c.state.phase, PomodoroPhase.work);
      expect(c.state.taskTimeUsed, isTrue);
      expect(c.state.remainingSeconds, 25 * 60);
    });

    test('a session skipped early counts only the time worked', () {
      final c = PomodoroCubit(
          settings: settings,
          taskSeconds: 30 * 60,
          now: () => now,
          startTicking: false);
      addTearDown(c.close);
      expect(c.state.taskSlices, [30 * 60], reason: 'a 5 min rest joins');
      c.start();
      now = now.add(const Duration(minutes: 10));
      c.skip();
      c.skip();
      expect(c.state.phase, PomodoroPhase.work);
      expect(c.state.focusedSeconds, 10 * 60);
      expect(c.state.remainingSeconds, 20 * 60);
    });

    test('a task with no time left gets full sessions', () {
      final c = PomodoroCubit(
          settings: settings, taskSeconds: -60, now: () => now, startTicking: false);
      addTearDown(c.close);
      expect(c.state.taskSeconds, isNull);
      expect(c.state.remainingSeconds, 25 * 60);
      expect(describeTaskPlan(c.state), isNull);
    });
  });
}
