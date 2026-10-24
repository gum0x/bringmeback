import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:bringmeback/timer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Random _random = Random.secure();

/// A random 128-bit id, hex encoded. Unlike timestamps, ids made on different devices can't collide.
String newId() => List.generate(
    16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

int nowSeconds() =>
    DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

/// One stretch of time a task's timer ran. `end` is null while it runs.
class TimeEntry {
  final int start;
  int? end;

  TimeEntry({required this.start, this.end});

  /// Seconds of this entry after `from`, counting an open entry up to `now`.
  int secondsSince(int from, int now) {
    final s = start > from ? start : from;
    final e = end ?? now;
    return e > s ? e - s : 0;
  }

  Map<String, dynamic> toJson() => {'s': start, 'e': end};

  factory TimeEntry.fromJson(Map<String, dynamic> json) =>
      TimeEntry(start: json['s'], end: json['e']);
}

class TaskState {
  final String name;
  final ValueKey<String> id;
  // Everything about the timer is derived from entries and timestamps, so any device holding the
  // same task state shows the same running state, countdown and total, and fires the same alerts.
  final List<TimeEntry> entries;
  int timerLengthSeconds;
  int timerStartAt;
  int totalResetAt;
  bool inFocus;

  TaskState(
      {required this.name,
      required this.id,
      this.timerLengthSeconds = 20 * 60,
      this.timerStartAt = 0,
      List<TimeEntry>? entries,
      this.totalResetAt = 0,
      this.inFocus = false,
      bool? running})
      : entries = entries ?? [] {
    if (running != null) this.running = running;
  }

  bool get running => entries.any((e) => e.end == null);

  set running(bool value) {
    final now = nowSeconds();
    if (value && !running) {
      entries.add(TimeEntry(start: now));
    } else if (!value) {
      for (final e in entries.where((e) => e.end == null)) {
        e.end = now;
      }
    }
  }

  /// Countdown left; negative once it has run out.
  int get taskTimerSeconds => remainingSecondsAt(nowSeconds());

  int remainingSecondsAt(int now) =>
      timerLengthSeconds - _secondsSince(timerStartAt, now);

  /// Time tracked since the last reset.
  int get totalTaskTimerSeconds => totalSecondsAt(nowSeconds());

  int totalSecondsAt(int now) => _secondsSince(totalResetAt, now);

  int _secondsSince(int from, int now) =>
      entries.fold(0, (sum, e) => sum + e.secondsSince(from, now));

  TaskState copyWith({
    String? name,
    ValueKey<String>? id,
    int? timerLengthSeconds,
    int? timerStartAt,
    List<TimeEntry>? entries,
    int? totalResetAt,
    bool? inFocus,
    bool? running,
  }) {
    return TaskState(
      name: name ?? this.name,
      id: id ?? this.id,
      timerLengthSeconds: timerLengthSeconds ?? this.timerLengthSeconds,
      timerStartAt: timerStartAt ?? this.timerStartAt,
      entries: entries ?? this.entries,
      totalResetAt: totalResetAt ?? this.totalResetAt,
      inFocus: inFocus ?? this.inFocus,
      running: running,
    );
  }
}

class TasksState {
  final List<TaskState> tasks;

  TasksState({required this.tasks});

  TasksState copyWith({List<TaskState>? tasks}) {
    return TasksState(
      tasks: tasks ?? this.tasks,
    );
  }
}

abstract class TasksEvent {}

class AddTaskOnTopEvent extends TasksEvent {
  final String name;
  final ValueKey<String> id;

  AddTaskOnTopEvent({required this.name, required this.id});
}

class AddNextTaskEvent extends TasksEvent {
  final int index;
  final String name;
  final ValueKey<String> id;

  AddNextTaskEvent({required this.index, required this.name, required this.id});
}

class RemoveTaskEvent extends TasksEvent {
  final int index;

  RemoveTaskEvent({required this.index});
}

class MoveTaskEvent extends TasksEvent {
  final int fromIndex;
  final int toIndex;

  MoveTaskEvent({required this.fromIndex, required this.toIndex});
}

class StartTimerEvent extends TasksEvent {
  final int index;

  StartTimerEvent({required this.index});
}

class StopTimerEvent extends TasksEvent {
  final int index;

  StopTimerEvent({required this.index});
}

class ResumeTimerEvent extends TasksEvent {
  final int index;

  ResumeTimerEvent({required this.index});
}

class ResetTimerEvent extends TasksEvent {
  final int index;

  ResetTimerEvent({required this.index});
}

class UpdateTimerEvent extends TasksEvent {
  UpdateTimerEvent();
}

class UpdateTaskNameEvent extends TasksEvent {
  final int index;
  final String newName;

  UpdateTaskNameEvent({required this.index, required this.newName});
}

class UpdateTaskTimerEvent extends TasksEvent {
  final int index;
  final int seconds;

  UpdateTaskTimerEvent({required this.index, required this.seconds});
}

class LoadStateEvent extends TasksEvent {}

class TasksBloc extends Bloc<TasksEvent, TasksState> {
  Timer? tick;
  final AudioPlayer _audioPlayer = AudioPlayer();
  // Countdown seen at the previous tick, per task, to detect when it crosses an alert point.
  final Map<String, int> _lastRemaining = {};

  TasksBloc() : super(TasksState(tasks: [])) {
    on<AddTaskOnTopEvent>(_onAddTaskOnTop);
    on<AddNextTaskEvent>(_onAddNextTask);
    on<RemoveTaskEvent>(_onRemoveTask);
    on<MoveTaskEvent>(_onMoveTask);
    on<StartTimerEvent>(_onStartTimer);
    on<StopTimerEvent>(_onStopTimer);
    on<ResetTimerEvent>(_onResetTimer);
    on<ResumeTimerEvent>(_onResumeTimer);
    on<UpdateTimerEvent>(_onUpdateTimer);
    on<UpdateTaskNameEvent>(_onUpdateTaskName);
    on<UpdateTaskTimerEvent>(_onUpdateTaskTimer);
    on<LoadStateEvent>(_onLoadState);

    add(LoadStateEvent());
    tick = Timer.periodic(Duration(seconds: 1), (_) {
      add(UpdateTimerEvent());
    });
  }

  void _onAddTaskOnTop(AddTaskOnTopEvent event, Emitter<TasksState> emit) {
    state.tasks.forEach((task) {
      task.inFocus = false;
    });

    final newTask =
        new TaskState(name: "", id: event.id, inFocus: true, running: true);
    final newTasks = [newTask, ...state.tasks];

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onAddNextTask(AddNextTaskEvent event, Emitter<TasksState> emit) {
    state.tasks.forEach((task) {
      task.inFocus = false;
    });

    final newTask =
        new TaskState(id: event.id, name: "", inFocus: true, running: false);
    final newTasks = [...state.tasks];
    newTasks.insert(event.index + 1, newTask);

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onRemoveTask(RemoveTaskEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    newTasks.removeAt(event.index);
    newTasks[0].inFocus = true;
    newTasks[0].running = true;

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onMoveTask(MoveTaskEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    final task = newTasks.removeAt(event.fromIndex);
    newTasks.insert(event.toIndex, task);

    newTasks.forEach((task) {
      task.inFocus = false;
    });
    newTasks[0].inFocus = true;
    newTasks[0].running = true;

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onStartTimer(StartTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    newTasks[event.index] =
        newTasks[event.index].copyWith(inFocus: true, running: true);

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onStopTimer(StopTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    final task = newTasks[event.index];
    task.running = false;

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onResumeTimer(ResumeTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    final task = newTasks[event.index];
    task.running = true;

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onResetTimer(ResetTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    final now = nowSeconds();
    _lastRemaining.remove(newTasks[event.index].id.value);
    newTasks[event.index] = newTasks[event.index].copyWith(
      timerLengthSeconds: 20 * 60,
      timerStartAt: now,
      totalResetAt: now,
    );

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onUpdateTimer(UpdateTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    final now = nowSeconds();
    for (int i = 0; i < newTasks.length; i++) {
      final task = newTasks[i];
      final remaining = task.remainingSecondsAt(now);
      final previous = _lastRemaining[task.id.value];
      _lastRemaining[task.id.value] = remaining;
      if (previous == null || previous == remaining) continue;

      // Check if timer has reached zero
      if (previous > 0 && remaining <= 0) {
        _playAlertSound();
      }
      if (i == 0 && (previous / 1800).floor() != (remaining / 1800).floor()) {
        _playAlertSound(alertType: 'REMINDER');
      }
    }

    if (newTasks.isNotEmpty && (newTasks[0].totalTaskTimerSeconds % 5) == 0) {
      _saveState();
    }
    emit(state.copyWith(tasks: newTasks));
  }

  void _onUpdateTaskName(UpdateTaskNameEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    newTasks[event.index] = newTasks[event.index].copyWith(name: event.newName);

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onUpdateTaskTimer(
      UpdateTaskTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    _lastRemaining.remove(newTasks[event.index].id.value);
    newTasks[event.index] = newTasks[event.index].copyWith(
        timerLengthSeconds: event.seconds, timerStartAt: nowSeconds());

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _playAlertSound({String? alertType}) async {
    switch (alertType) {
      case 'REMINDER':
        await _audioPlayer.play(AssetSource('alert.mp3'));

      default:
        await _audioPlayer.play(AssetSource('bmb-reminder.mp3'));
    }
  }

  /// Builds a task saved by an older version, which stored counters instead of entries.
  TaskState _migrateTask(Map<String, dynamic> task) {
    final now = nowSeconds();
    final int total = task['totalTaskTimerSeconds'] ?? 0;
    return TaskState(
      name: task['name'],
      id: ValueKey<String>(task['id']),
      timerLengthSeconds: task['taskTimerSeconds'] ?? 20 * 60,
      timerStartAt: now,
      entries: [if (total > 0) TimeEntry(start: now - total, end: now)],
      inFocus: task['inFocus'] ?? false,
      running: task['running'] ?? false,
    );
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final String tasksJson = jsonEncode(
      state.tasks
          .map((task) => {
                'name': task.name,
                'id': task.id.value,
                'timerLengthSeconds': task.timerLengthSeconds,
                'timerStartAt': task.timerStartAt,
                'entries': task.entries.map((e) => e.toJson()).toList(),
                'totalResetAt': task.totalResetAt,
                'inFocus': task.inFocus,
              })
          .toList(),
    );
    await prefs.setString('tasks', tasksJson);
  }

  void _onLoadState(LoadStateEvent event, Emitter<TasksState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksJson = prefs.getString('tasks');
    if (tasksJson != null) {
      final List<dynamic> decoded = jsonDecode(tasksJson);
      final List<TaskState> loadedTasks = decoded
          .map((task) => task['entries'] == null
              ? _migrateTask(task)
              : TaskState(
                  name: task['name'],
                  id: ValueKey<String>(task['id']),
                  timerLengthSeconds: task['timerLengthSeconds'],
                  timerStartAt: task['timerStartAt'],
                  entries: (task['entries'] as List)
                      .map((e) => TimeEntry.fromJson(e))
                      .toList(),
                  totalResetAt: task['totalResetAt'],
                  inFocus: task['inFocus'],
                ))
          .toList();

      emit(state.copyWith(tasks: loadedTasks));
    }
  }

  @override
  Future<void> close() {
    tick?.cancel();
    return super.close();
  }
}
