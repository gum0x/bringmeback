import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_document.dart';

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

/// A task as the UI sees it, read from the [TaskDocument].
class TaskState {
  final String name;
  final ValueKey<String> id;
  // Everything about the timer is derived from entries and timestamps, so any device holding the
  // same task state shows the same running state, countdown and total, and fires the same alerts.
  final List<TimeEntry> entries;
  final int timerLengthSeconds;
  final int timerStartAt;
  final int totalResetAt;
  final bool inFocus;

  TaskState(
      {required this.name,
      required this.id,
      this.timerLengthSeconds = 20 * 60,
      this.timerStartAt = 0,
      List<TimeEntry>? entries,
      this.totalResetAt = 0,
      this.inFocus = false})
      : entries = entries ?? [];

  bool get running => entries.any((e) => e.end == null);

  /// Countdown left; negative once it has run out.
  int get taskTimerSeconds => remainingSecondsAt(nowSeconds());

  int remainingSecondsAt(int now) =>
      timerLengthSeconds - _secondsSince(timerStartAt, now);

  /// Time tracked since the last reset.
  int get totalTaskTimerSeconds => totalSecondsAt(nowSeconds());

  int totalSecondsAt(int now) => _secondsSince(totalResetAt, now);

  int _secondsSince(int from, int now) =>
      entries.fold(0, (sum, e) => sum + e.secondsSince(from, now));
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
  // Null until the saved document has been loaded; edits before that are ignored.
  TaskDocument? _doc;
  // Which task has the focus is local to this device.
  String? _focusId;
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

  TasksState _view() => TasksState(tasks: _doc?.tasks(focusId: _focusId) ?? []);

  /// Applies [change] to the document, then shows and saves the result.
  void _edit(Emitter<TasksState> emit, void Function(TaskDocument doc) change) {
    final doc = _doc;
    if (doc == null) return;
    change(doc);
    emit(_view());
    _saveState();
  }

  /// The id of the task at [index], or null when there is none.
  String? _idAt(int index) {
    final ids = _doc?.ids ?? const [];
    return index >= 0 && index < ids.length ? ids[index] : null;
  }

  /// Focuses the first task and starts its timer, as removing or moving a task does.
  void _focusFirst(TaskDocument doc) {
    final first = _idAt(0);
    if (first == null) return;
    _focusId = first;
    doc.setRunning(first, true);
  }

  void _onAddTaskOnTop(AddTaskOnTopEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      doc.insert(0, event.id.value, running: true);
      _focusId = event.id.value;
    });
  }

  void _onAddNextTask(AddNextTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      doc.insert(min(event.index + 1, doc.ids.length), event.id.value);
      _focusId = event.id.value;
    });
  }

  void _onRemoveTask(RemoveTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      doc.removeAt(event.index);
      _focusFirst(doc);
    });
  }

  void _onMoveTask(MoveTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      doc.move(event.fromIndex, event.toIndex);
      _focusFirst(doc);
    });
  }

  void _onStartTimer(StartTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _edit(emit, (doc) {
      _focusId = id;
      doc.setRunning(id, true);
    });
  }

  void _onStopTimer(StopTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _edit(emit, (doc) => doc.setRunning(id, false));
  }

  void _onResumeTimer(ResumeTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _edit(emit, (doc) => doc.setRunning(id, true));
  }

  void _onResetTimer(ResetTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    final now = nowSeconds();
    _lastRemaining.remove(id);
    _edit(emit, (doc) {
      doc.setTimer(id, 20 * 60, now);
      doc.setTotalResetAt(id, now);
    });
  }

  void _onUpdateTimer(UpdateTimerEvent event, Emitter<TasksState> emit) {
    final view = _view();
    final now = nowSeconds();
    for (int i = 0; i < view.tasks.length; i++) {
      final task = view.tasks[i];
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

    emit(view);
  }

  void _onUpdateTaskName(UpdateTaskNameEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _edit(emit, (doc) => doc.setName(id, event.newName));
  }

  void _onUpdateTaskTimer(
      UpdateTaskTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _lastRemaining.remove(id);
    _edit(emit, (doc) => doc.setTimer(id, event.seconds, nowSeconds()));
  }

  void _playAlertSound({String? alertType}) async {
    switch (alertType) {
      case 'REMINDER':
        await _audioPlayer.play(AssetSource('alert.mp3'));

      default:
        await _audioPlayer.play(AssetSource('bmb-reminder.mp3'));
    }
  }

  Future<void> _saveState() async {
    final doc = _doc;
    if (doc == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('taskDocument', doc.encodeChanges());
    final focusId = _focusId;
    if (focusId != null) await prefs.setString('focusId', focusId);
  }

  Future<void> _onLoadState(
      LoadStateEvent event, Emitter<TasksState> emit) async {
    if (_doc != null) return;
    final prefs = await SharedPreferences.getInstance();
    if (_doc != null) return;

    // The peer id names this install as the author of its changes; it must stay the same.
    var peerId = prefs.getString('peerId');
    if (peerId == null) {
      peerId = PeerId.generate().toString();
      await prefs.setString('peerId', peerId);
    }
    final doc = TaskDocument(
        CRDTDocument(peerId: PeerId.parse(peerId), documentId: 'tasks'));

    final saved = prefs.getString('taskDocument');
    final legacy = prefs.getString('tasks');
    if (saved != null) {
      doc.importEncodedChanges(saved);
      _focusId = prefs.getString('focusId');
    } else if (legacy != null) {
      // Tasks saved before the document existed. The old key is left in place.
      final tasks = (jsonDecode(legacy) as List)
          .map((t) => _legacyTask(t as Map<String, dynamic>))
          .toList();
      for (final (i, t) in tasks.indexed) {
        doc.insert(i, t.task.id.value,
            name: t.task.name,
            timerLengthSeconds: t.task.timerLengthSeconds,
            timerStartAt: t.task.timerStartAt,
            totalResetAt: t.task.totalResetAt,
            entries: t.task.entries,
            running: t.running);
        if (t.task.inFocus) _focusId = t.task.id.value;
      }
    }

    _doc = doc;
    emit(_view());
    await _saveState();
  }

  /// Reads a task saved as JSON by an earlier version, with or without time entries.
  ({TaskState task, bool running}) _legacyTask(Map<String, dynamic> t) {
    final now = nowSeconds();
    final id = ValueKey<String>(t['id']);
    if (t['entries'] != null) {
      final entries = [
        for (final e in t['entries'] as List) TimeEntry.fromJson(e)
      ];
      return (
        task: TaskState(
          name: t['name'] ?? '',
          id: id,
          timerLengthSeconds: t['timerLengthSeconds'] ?? 20 * 60,
          timerStartAt: t['timerStartAt'] ?? now,
          totalResetAt: t['totalResetAt'] ?? 0,
          entries: entries,
          inFocus: t['inFocus'] ?? false,
        ),
        running: false,
      );
    }
    final int total = t['totalTaskTimerSeconds'] ?? 0;
    return (
      task: TaskState(
        name: t['name'] ?? '',
        id: id,
        timerLengthSeconds: t['taskTimerSeconds'] ?? 20 * 60,
        timerStartAt: now,
        entries: [if (total > 0) TimeEntry(start: now - total, end: now)],
        inFocus: t['inFocus'] ?? false,
      ),
      running: t['running'] ?? false,
    );
  }

  @override
  Future<void> close() {
    tick?.cancel();
    return super.close();
  }
}
