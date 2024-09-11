import 'dart:async';
import 'dart:convert';
import 'package:bringmeback/timer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskState {
  final String name;
  final ValueKey<String> id;
  int taskTimerSeconds;
  int totalTaskTimerSeconds;
  bool inFocus;
  bool running;
  int lastTimerUpdate;

  TaskState(
      {required this.name,
      required this.id,
      this.taskTimerSeconds = 20 * 60,
      this.totalTaskTimerSeconds = 0,
      this.inFocus = false,
      this.running = false,
      this.lastTimerUpdate = 0});

  TaskState copyWith({
    String? name,
    ValueKey<String>? id,
    int? taskTimerSeconds,
    int? totalTaskTimerSeconds,
    bool? inFocus,
    Timer? timer,
    bool? running,
    int? lastTimerUpdate,
  }) {
    return TaskState(
      name: name ?? this.name,
      id: id ?? this.id,
      taskTimerSeconds: taskTimerSeconds ?? this.taskTimerSeconds,
      totalTaskTimerSeconds:
          totalTaskTimerSeconds ?? this.totalTaskTimerSeconds,
      inFocus: inFocus ?? this.inFocus,
      running: running ?? this.running,
      lastTimerUpdate: lastTimerUpdate ?? this.lastTimerUpdate,
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

  TasksBloc() : super(TasksState(tasks: [])) {
    on<AddTaskOnTopEvent>(_onAddTaskOnTop);
    on<AddNextTaskEvent>(_onAddNextTask);
    on<RemoveTaskEvent>(_onRemoveTask);
    on<MoveTaskEvent>(_onMoveTask);
    on<StartTimerEvent>(_onStartTimer);
    on<StopTimerEvent>(_onStopTimer);
    on<ResetTimerEvent>(_onResetTimer);
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
    task.lastTimerUpdate = 0;

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onResetTimer(ResetTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    newTasks[event.index] = newTasks[event.index].copyWith(
      taskTimerSeconds: 20 * 60,
      totalTaskTimerSeconds: 0,
    );

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _onUpdateTimer(UpdateTimerEvent event, Emitter<TasksState> emit) {
    final newTasks = [...state.tasks];
    for (int i = 0; i < newTasks.length; i++) {
      TaskState task = newTasks[i];
      if (task.running) {
        int diff;
        final int now = DateTime.now().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;

        if (task.lastTimerUpdate == 0) {
          diff = 1;
          task.lastTimerUpdate = now;
        } else {
          diff = now - task.lastTimerUpdate;
          task.lastTimerUpdate = now;
        }

        task.taskTimerSeconds -= diff;
        task.totalTaskTimerSeconds += diff;

        // Check if timer has reached zero
        if (task.taskTimerSeconds == 0) {
          _playAlertSound();
        }
        if ((i == 0 && task.taskTimerSeconds % (15 * 60) == 0)) {
          _playAlertSound(alertType: 'REMINDER');
        }
      } else {
        task.lastTimerUpdate = 0;
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
    newTasks[event.index] =
        newTasks[event.index].copyWith(taskTimerSeconds: event.seconds);

    _saveState();
    emit(state.copyWith(tasks: newTasks));
  }

  void _playAlertSound({String? alertType}) async {
    switch (alertType) {
      case 'REMINDER':
        await _audioPlayer.play(AssetSource('alert.mp3'));

      default:
        await _audioPlayer.play(AssetSource('alert.mp3'));
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final String tasksJson = jsonEncode(
      state.tasks
          .map((task) => {
                'name': task.name,
                'id': task.id.value,
                'taskTimerSeconds': task.taskTimerSeconds,
                'totalTaskTimerSeconds': task.totalTaskTimerSeconds,
                'inFocus': task.inFocus,
                'running': task.running,
                'lastTimerUpdate': task.lastTimerUpdate,
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
          .map((task) => TaskState(
                name: task['name'],
                id: ValueKey<String>(task['id']),
                taskTimerSeconds: task['taskTimerSeconds'],
                totalTaskTimerSeconds: task['totalTaskTimerSeconds'],
                inFocus: task['inFocus'],
                running: task['running'],
                lastTimerUpdate: task['lastTimerUpdate'],
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
