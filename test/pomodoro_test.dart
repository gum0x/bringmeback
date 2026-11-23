import 'dart:convert';

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

  group('F1 changing the lengths while focusing', () {
    test('F1.1 a session under way takes the new length, counting the time worked',
        () {
      cubit.start();
      advance(const Duration(minutes: 5));
      cubit.updateSettings(settings.copyWith(workMinutes: 50));
      expect(cubit.state.settings.workMinutes, 50);
      expect(cubit.state.workSeconds, 50 * 60);
      expect(cubit.state.remainingSeconds, 45 * 60);
      expect(cubit.state.running, isTrue);
      advance(const Duration(minutes: 45));
      expect(cubit.state.phase, PomodoroPhase.shortBreak,
          reason: 'it ends at the new length, not the old one');

      // Paused, the same: the time left changes, the clock stays paused.
      final c = PomodoroCubit(
          settings: settings, now: () => now, startTicking: false);
      addTearDown(c.close);
      c.start();
      now = now.add(const Duration(minutes: 10));
      c.pause();
      c.updateSettings(settings.copyWith(workMinutes: 30));
      expect(c.state.remainingSeconds, 20 * 60);
      expect(c.state.running, isFalse);
      now = now.add(const Duration(minutes: 30));
      c.tick();
      expect(c.state.remainingSeconds, 20 * 60);
    });

    test('F1.2 a new length shorter than the time worked ends the session',
        () async {
      final phases = <PomodoroPhase>[];
      final sub = cubit.phaseStarted.listen(phases.add);
      addTearDown(sub.cancel);
      cubit.start();
      advance(const Duration(minutes: 20));
      cubit.updateSettings(settings.copyWith(workMinutes: 15));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, PomodoroPhase.shortBreak);
      expect(cubit.state.completedSessions, 1);
      expect(cubit.state.focusedSeconds, 20 * 60,
          reason: 'what was worked counts');
      expect(cubit.state.remainingSeconds, 5 * 60);
      expect(cubit.state.running, isTrue);
      expect(phases, [PomodoroPhase.shortBreak], reason: 'the break sound');
    });

    test('F1.3 a break under way takes the new break length', () {
      cubit.start();
      advance(const Duration(minutes: 25));
      advance(const Duration(minutes: 2));
      expect(cubit.state.phase, PomodoroPhase.shortBreak);
      cubit.updateSettings(settings.copyWith(shortBreakMinutes: 10));
      expect(cubit.state.remainingSeconds, 8 * 60);
      cubit.updateSettings(settings.copyWith(shortBreakMinutes: 1));
      expect(cubit.state.phase, PomodoroPhase.work,
          reason: 'already on the break longer than that');
      expect(cubit.state.remainingSeconds, 25 * 60);
      expect(cubit.state.running, isTrue);
    });

    test('F1.4 with a task time, the session is cut from the time left at the new length',
        () {
      final c = PomodoroCubit(
          settings: settings,
          taskSeconds: 60 * 60,
          now: () => now,
          startTicking: false);
      addTearDown(c.close);
      c.start();
      now = now.add(const Duration(minutes: 5));
      c.tick();
      c.updateSettings(settings.copyWith(workMinutes: 50));
      expect(c.state.workSeconds, 50 * 60);
      expect(c.state.remainingSeconds, 45 * 60);
      expect(c.state.taskSlices, [50 * 60, 10 * 60]);
      expect(describeTaskPlan(c.state),
          "Fits the task's 1 h: 50 + 10 min of focus, 1 h 5 min with breaks");

      // F1.5: a focus length longer than the task's time left gives only that time.
      final short = PomodoroCubit(
          settings: settings,
          taskSeconds: 20 * 60,
          now: () => now,
          startTicking: false);
      addTearDown(short.close);
      short.start();
      now = now.add(const Duration(minutes: 5));
      short.tick();
      short.updateSettings(settings.copyWith(workMinutes: 50));
      expect(short.state.workSeconds, 20 * 60);
      expect(short.state.remainingSeconds, 15 * 60);
    });

    test('F1.6 one skip after a change goes to the new break, the next to the new focus length',
        () {
      cubit.start();
      advance(const Duration(minutes: 3));
      cubit.updateSettings(
          settings.copyWith(workMinutes: 40, shortBreakMinutes: 8));
      expect(cubit.state.remainingSeconds, 37 * 60);
      cubit.skip();
      expect(cubit.state.phase, PomodoroPhase.shortBreak);
      expect(cubit.state.remainingSeconds, 8 * 60);
      cubit.skip();
      expect(cubit.state.phase, PomodoroPhase.work);
      expect(cubit.state.remainingSeconds, 40 * 60);
    });
  });

  group('F2 changing the task time with a Pomodoro under way', () {
    PomodoroCubit taskClock(int taskSeconds, {String mark = '3600@0'}) {
      final c = PomodoroCubit(
          settings: settings,
          taskSeconds: taskSeconds,
          taskTimer: mark,
          now: () => now,
          startTicking: false);
      addTearDown(c.close);
      return c;
    }

    void go(PomodoroCubit c, Duration d) {
      now = now.add(d);
      c.tick();
    }

    test('F2.2 a new task time refits the session under way', () {
      final c = taskClock(60 * 60);
      c.start();
      go(c, const Duration(minutes: 10));
      // Set to 30 min from now: with the 10 worked, this session has 40 to fit.
      c.retime(30 * 60, '1800@600');
      expect(c.state.taskSeconds, 40 * 60);
      expect(c.state.taskTimer, '1800@600');
      expect(c.state.workSeconds, 25 * 60);
      expect(c.state.remainingSeconds, 15 * 60);
      expect(c.state.running, isTrue);
      go(c, const Duration(minutes: 15));
      go(c, const Duration(minutes: 5));
      expect(c.state.phase, PomodoroPhase.work);
      expect(c.state.remainingSeconds, 15 * 60, reason: 'the 15 min left');

      // A longer time: the session grows to the next full slice.
      final d = taskClock(20 * 60);
      d.start();
      go(d, const Duration(minutes: 5));
      expect(d.state.remainingSeconds, 15 * 60);
      d.retime(60 * 60, '3600@300');
      expect(d.state.workSeconds, 25 * 60);
      expect(d.state.remainingSeconds, 20 * 60);
    });

    test('F2.3 a task time set below what this session has worked counts from now',
        () {
      final c = taskClock(60 * 60);
      c.start();
      go(c, const Duration(minutes: 10));
      // 10 min worked, and the task set to 5 min: 5 min from now, not "already over".
      c.retime(5 * 60, '300@600');
      expect(c.state.taskSeconds, 15 * 60);
      expect(c.state.remainingSeconds, 5 * 60);
      go(c, const Duration(minutes: 5));
      expect(c.state.phase, PomodoroPhase.shortBreak);
      expect(c.state.focusedSeconds, 15 * 60);
      expect(c.state.taskTimeUsed, isTrue);
    });

    test('F2.4 a task with no time left after the change gets full sessions', () {
      final c = taskClock(30 * 60);
      c.start();
      go(c, const Duration(minutes: 10));
      c.retime(0, '0@600');
      expect(c.state.taskSeconds, isNull);
      expect(describeTaskPlan(c.state), isNull);
      expect(c.state.workSeconds, 25 * 60);
      expect(c.state.remainingSeconds, 15 * 60);
      c.retime(-120, '600@0');
      expect(c.state.taskSeconds, isNull);
    });

    test('F2.5 a task time changed on a break refits the next session', () {
      final c = taskClock(60 * 60);
      c.start();
      go(c, const Duration(minutes: 25));
      go(c, const Duration(minutes: 2));
      expect(c.state.phase, PomodoroPhase.shortBreak);
      c.retime(12 * 60, '720@1620');
      expect(c.state.phase, PomodoroPhase.shortBreak);
      expect(c.state.remainingSeconds, 3 * 60, reason: 'the break carries on');
      go(c, const Duration(minutes: 3));
      expect(c.state.phase, PomodoroPhase.work);
      expect(c.state.remainingSeconds, 12 * 60);
      expect(c.state.completedSessions, 1);
    });

    test('F2.6 the same task time does not cut a new plan', () {
      final c = taskClock(60 * 60);
      c.start();
      go(c, const Duration(minutes: 10));
      final before = c.state;
      // The task's countdown ran down meanwhile, but its time wasn't set again.
      c.retime(45 * 60, '3600@0');
      expect(c.state, same(before));
    });

    test('F2.7 a clock from an older version keeps its plan until the task time changes',
        () {
      final old = PomodoroRecord.decode(jsonEncode({
        'phase': 'work',
        'completed': 0,
        'work': 25,
        'shortBreak': 5,
        'longBreak': 15,
        'sessions': 2,
        'taskSeconds': 3600,
        'focused': 0,
        'workSeconds': 1500,
        'remaining': 1200,
        'open': false,
        'savedAt': now.millisecondsSinceEpoch,
      }), now: now)!;
      expect(old.state.taskTimer, isNull);
      final c = PomodoroCubit(
          resumeFrom: old.state, now: () => now, startTicking: false);
      addTearDown(c.close);
      c.retime(50 * 60, '3600@0');
      expect(c.state.taskSeconds, 60 * 60, reason: 'kept on its plan');
      expect(c.state.remainingSeconds, 20 * 60);
      expect(c.state.taskTimer, '3600@0');
      c.retime(30 * 60, '1800@900');
      expect(c.state.taskSeconds, 35 * 60, reason: '5 worked + 30 left');
      expect(c.state.remainingSeconds, 20 * 60);
    });

    test('the task time it was cut from is kept in the record', () {
      final c = taskClock(60 * 60, mark: '3600@42');
      final r = PomodoroRecord(
          state: c.state, endsAt: null, open: true, savedAt: now);
      expect(PomodoroRecord.decode(r.encode(), now: now)!.state.taskTimer,
          '3600@42');
    });
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
