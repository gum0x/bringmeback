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
  final bool muted;

  TasksState({required this.tasks, this.muted = false});

  TasksState copyWith({List<TaskState>? tasks, bool? muted}) {
    return TasksState(
      tasks: tasks ?? this.tasks,
      muted: muted ?? this.muted,
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

/// Takes a task off the list as done.
class DoneTaskEvent extends TasksEvent {
  final int index;

  DoneTaskEvent({required this.index});
}

/// Puts a removed or done task back, to undo [RemoveTaskEvent] or [DoneTaskEvent].
class RestoreTaskEvent extends TasksEvent {
  final int index;
  final ValueKey<String> id;

  RestoreTaskEvent({required this.index, required this.id});
}

/// Marks the task the user is working in, which keyboard shortcuts act on.
class FocusTaskEvent extends TasksEvent {
  final int index;

  FocusTaskEvent({required this.index});
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

/// Restarts the countdown with its current length.
class ResetTimerEvent extends TasksEvent {
  final int index;

  ResetTimerEvent({required this.index});
}

/// Clears the total time tracked on a task.
class ResetTotalEvent extends TasksEvent {
  final int index;

  ResetTotalEvent({required this.index});
}

class ToggleMuteEvent extends TasksEvent {}

class UpdateTimerEvent extends TasksEvent {
  UpdateTimerEvent();
}

/// Renames a task. It names the task by id, because a name is saved a moment after typing stops,
/// by which time the task may have moved.
class UpdateTaskNameEvent extends TasksEvent {
  final ValueKey<String> id;
  final String newName;

  UpdateTaskNameEvent({required this.id, required this.newName});
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
  bool _muted = false;
  final StreamController<String> _timeUp = StreamController<String>.broadcast();

  /// The name of each task whose countdown runs out, as it happens.
  Stream<String> get timeUp => _timeUp.stream;

  TasksBloc() : super(TasksState(tasks: [])) {
    on<AddTaskOnTopEvent>(_onAddTaskOnTop);
    on<AddNextTaskEvent>(_onAddNextTask);
    on<RemoveTaskEvent>(_onRemoveTask);
    on<DoneTaskEvent>(_onDoneTask);
    on<RestoreTaskEvent>(_onRestoreTask);
    on<FocusTaskEvent>(_onFocusTask);
    on<ResetTotalEvent>(_onResetTotal);
    on<ToggleMuteEvent>(_onToggleMute);
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

  TasksState _view() =>
      TasksState(tasks: _doc?.tasks(focusId: _focusId) ?? [], muted: _muted);

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

  /// Whether work is under way: the top task's timer runs, rather than a pause or nothing.
  bool _working(TaskDocument doc) => doc.ids.any((id) => doc.task(id).running);

  /// Only the top task is the one being worked on, so only its timer may run. Running it ends any
  /// pause being logged.
  void _runTop(TaskDocument doc, bool run) {
    for (final (i, id) in doc.ids.indexed) {
      doc.setRunning(id, run && i == 0);
    }
    if (run && doc.ids.isNotEmpty) doc.endPauses();
  }

  void _onAddTaskOnTop(AddTaskOnTopEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      doc.insert(0, event.id.value);
      _runTop(doc, true);
      _focusId = event.id.value;
    });
  }

  void _onAddNextTask(AddNextTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      final working = _working(doc);
      doc.insert(min(event.index + 1, doc.ids.length), event.id.value);
      _runTop(doc, working);
      _focusId = event.id.value;
    });
  }

  /// Takes the task at [index] off the list with [takeOff]. When it was being worked on, work
  /// carries on with the task that moves up.
  void _takeOff(Emitter<TasksState> emit, int index,
      void Function(TaskDocument doc, String id) takeOff) {
    final id = _idAt(index);
    if (id == null) return;
    _edit(emit, (doc) {
      final working = _working(doc);
      // A task taken off stays paused, so undoing doesn't count the time it was gone.
      doc.setRunning(id, false);
      takeOff(doc, id);
      _runTop(doc, working);
      if (_focusId == id) _focusId = _idAt(min(index, doc.ids.length - 1));
    });
  }

  void _onRemoveTask(RemoveTaskEvent event, Emitter<TasksState> emit) =>
      _takeOff(emit, event.index, (doc, id) => doc.removeAt(event.index));

  void _onDoneTask(DoneTaskEvent event, Emitter<TasksState> emit) =>
      _takeOff(emit, event.index, (doc, id) => doc.markDone(event.index, id));

  void _onRestoreTask(RestoreTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      if (doc.ids.contains(event.id.value)) return;
      final working = _working(doc);
      doc.restore(min(event.index, doc.ids.length), event.id.value);
      _runTop(doc, working);
      _focusId = event.id.value;
    });
  }

  void _onFocusTask(FocusTaskEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null || id == _focusId) return;
    _focusId = id;
    emit(_view());
    _saveState();
  }

  /// Moving a task to the top makes it the one being worked on.
  void _onMoveTask(MoveTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      final working = _working(doc);
      doc.move(event.fromIndex, event.toIndex);
      _runTop(doc, working);
    });
  }

  // Starting, pausing and resuming act on the top task, the only one with a running timer.

  void _onStartTimer(StartTimerEvent event, Emitter<TasksState> emit) {
    if (_idAt(0) == null) return;
    _edit(emit, (doc) => _runTop(doc, true));
  }

  /// Pauses the work and logs the pause, so the time between tasks is kept too.
  void _onStopTimer(StopTimerEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      if (!_working(doc)) return;
      _runTop(doc, false);
      doc.startPause(newId());
    });
  }

  void _onResumeTimer(ResumeTimerEvent event, Emitter<TasksState> emit) {
    if (_idAt(0) == null) return;
    _edit(emit, (doc) => _runTop(doc, true));
  }

  void _onResetTimer(ResetTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _lastRemaining.remove(id);
    _edit(emit,
        (doc) => doc.setTimer(id, doc.task(id).timerLengthSeconds, nowSeconds()));
  }

  void _onResetTotal(ResetTotalEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _edit(emit, (doc) => doc.setTotalResetAt(id, nowSeconds()));
  }

  void _onToggleMute(ToggleMuteEvent event, Emitter<TasksState> emit) {
    _muted = !_muted;
    emit(_view());
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('muted', _muted));
  }

  void _onUpdateTimer(UpdateTimerEvent event, Emitter<TasksState> emit) {
    final view = _view();
    final now = nowSeconds();
    for (final task in view.tasks) {
      final remaining = task.remainingSecondsAt(now);
      final previous = _lastRemaining[task.id.value];
      _lastRemaining[task.id.value] = remaining;
      if (previous == null || previous == remaining) continue;

      if (previous > 0 && remaining <= 0) {
        _timeUp.add(task.name);
        _playAlertSound();
      } else if ((previous / 1800).floor() != (remaining / 1800).floor()) {
        // Every 30 minutes of a running task.
        _playAlertSound(alertType: 'REMINDER');
      }
    }

    emit(view);
  }

  void _onUpdateTaskName(UpdateTaskNameEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) => doc.setName(event.id.value, event.newName));
  }

  void _onUpdateTaskTimer(
      UpdateTaskTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _lastRemaining.remove(id);
    _edit(emit, (doc) => doc.setTimer(id, event.seconds, nowSeconds()));
  }

  void _playAlertSound({String? alertType}) async {
    if (_muted) return;
    switch (alertType) {
      case 'REMINDER':
        await _audioPlayer.play(AssetSource('bmb-reminder.mp3'));

      default:
        await _audioPlayer.play(AssetSource('alert.mp3'));
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
    _muted = prefs.getBool('muted') ?? false;

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

    // Earlier versions let any task run; now only the top one may.
    _runTop(doc, _working(doc));
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
    _timeUp.close();
    return super.close();
  }
}
