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

/// How many unfinished tasks the note holds before writing another one asks first, unless Settings
/// says otherwise. A short list keeps the day focused, so past it the app suggests the backlog
/// instead; the user can still write the task on the note. Done tasks don't count.
const defaultTaskLimit = 7;

/// The range Settings offers for the limit.
const minTaskLimit = 3;
const maxTaskLimit = 20;

/// A day starts at 4:00, so working past midnight still counts as the same day.
const dayStartHour = 4;

/// The day [seconds] falls on, as midnight of that date in local time.
DateTime dayOf(int seconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
      .subtract(const Duration(hours: dayStartHour));
  return DateTime(t.year, t.month, t.day);
}

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

  /// Longer details written under the name, free text over several lines.
  final String notes;
  final ValueKey<String> id;
  // Everything about the timer is derived from entries and timestamps, so any device holding the
  // same task state shows the same running state, countdown and total, and fires the same alerts.
  final List<TimeEntry> entries;
  final int timerLengthSeconds;
  final int timerStartAt;
  final int totalResetAt;
  final bool inFocus;

  /// When the task was checked off, or null while it isn't.
  final int? doneAt;

  /// The task of an earlier note this one was written again from.
  final String? carriedFrom;

  TaskState(
      {required this.name,
      this.notes = '',
      required this.id,
      this.timerLengthSeconds = 20 * 60,
      this.timerStartAt = 0,
      List<TimeEntry>? entries,
      this.totalResetAt = 0,
      this.inFocus = false,
      this.doneAt,
      this.carriedFrom})
      : entries = entries ?? [];

  bool get done => doneAt != null;

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
  /// The tasks written on the current note, in order, done ones included.
  final List<TaskState> tasks;
  final bool muted;

  /// When the current note was started.
  final int noteStartedAt;

  /// Unfinished tasks of torn-off notes, waiting to be written again or let go.
  final List<TaskState> pending;

  /// Tasks kept for later, off the note, oldest first.
  final List<TaskState> backlog;

  /// Whether the document has loaded.
  final bool loaded;

  /// How many unfinished tasks the note holds before writing another one asks first, set in
  /// Settings.
  final int taskLimit;

  TasksState(
      {required this.tasks,
      this.muted = false,
      this.taskLimit = defaultTaskLimit,
      int? noteStartedAt,
      this.pending = const [],
      this.backlog = const [],
      this.loaded = false})
      : noteStartedAt = noteStartedAt ?? nowSeconds();

  TasksState copyWith({List<TaskState>? tasks, bool? muted}) {
    return TasksState(
      tasks: tasks ?? this.tasks,
      muted: muted ?? this.muted,
      noteStartedAt: noteStartedAt,
      pending: pending,
      backlog: backlog,
      loaded: loaded,
      taskLimit: taskLimit,
    );
  }

  /// The index of the task being worked on: the first one not checked off, or -1.
  int get currentIndex => tasks.indexWhere((t) => !t.done);

  /// How many tasks on the note are not done yet.
  int get openCount => tasks.where((t) => !t.done).length;

  /// Whether writing one more task would go over the limit, so the app asks first.
  bool get atLimit => openCount >= taskLimit;

  bool get allDone => tasks.isNotEmpty && tasks.every((t) => t.done);

  /// Whether the note was started on an earlier day and has tasks on it: time to tear it off.
  bool needsTearOff([int? now]) =>
      tasks.isNotEmpty && dayOf(noteStartedAt) != dayOf(now ?? nowSeconds());
}

abstract class TasksEvent {}

/// Writes a task on top of the note, as an interruption: it becomes the current task and its timer
/// runs.
class AddTaskOnTopEvent extends TasksEvent {
  final String name;
  final ValueKey<String> id;
  final int? timerLengthSeconds;

  final String notes;

  AddTaskOnTopEvent(
      {required this.name, required this.id, this.timerLengthSeconds, this.notes = ''});
}

/// Writes a task right after the one at [index].
class AddNextTaskEvent extends TasksEvent {
  final int index;
  final String name;
  final ValueKey<String> id;
  final int? timerLengthSeconds;

  AddNextTaskEvent(
      {required this.index, required this.name, required this.id, this.timerLengthSeconds});
}

/// Writes a task at [index], pushing the one there down.
class InsertTaskEvent extends TasksEvent {
  final int index;
  final String name;
  final ValueKey<String> id;
  final int? timerLengthSeconds;

  final String notes;

  InsertTaskEvent(
      {required this.index,
      required this.name,
      required this.id,
      this.timerLengthSeconds,
      this.notes = ''});
}

/// Checks a task off, or unchecks it. Either way it stays on the note.
class SetDoneEvent extends TasksEvent {
  final int index;
  final bool done;

  SetDoneEvent({required this.index, required this.done});
}

/// Renames a task and sets its countdown length, from the task dialog.
class EditTaskEvent extends TasksEvent {
  final ValueKey<String> id;
  final String name;
  final int timerLengthSeconds;

  final String? notes;

  EditTaskEvent(
      {required this.id, required this.name, required this.timerLengthSeconds, this.notes});
}

/// Tears off the current note and starts an empty one. Its unfinished tasks wait to be written again
/// or let go.
class TearOffNoteEvent extends TasksEvent {}

/// Writes an unfinished task of a torn-off note again, at the end of the current note.
class CarryTaskEvent extends TasksEvent {
  final String id;

  CarryTaskEvent({required this.id});
}

/// Lets go of an unfinished task of a torn-off note, or of all of them when [id] is null.
class LetGoEvent extends TasksEvent {
  final String? id;

  LetGoEvent({this.id});
}

class RemoveTaskEvent extends TasksEvent {
  final int index;

  RemoveTaskEvent({required this.index});
}

/// Checks a task off.
class DoneTaskEvent extends TasksEvent {
  final int index;

  DoneTaskEvent({required this.index});
}

/// Puts a deleted task back, to undo [RemoveTaskEvent].
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

/// Sets how many unfinished tasks the note holds before writing another one asks first. Nothing
/// already written moves when it shrinks.
class SetTaskLimitEvent extends TasksEvent {
  final int limit;

  SetTaskLimitEvent(this.limit);
}

/// Keeps a new task in the backlog, off the note.
class AddToBacklogEvent extends TasksEvent {
  final String name;
  final ValueKey<String> id;
  final int? timerLengthSeconds;
  final String notes;

  AddToBacklogEvent(
      {required this.name, required this.id, this.timerLengthSeconds, this.notes = ''});
}

/// Moves an unfinished task of a torn-off note to the backlog.
class MoveToBacklogEvent extends TasksEvent {
  final String id;

  MoveToBacklogEvent({required this.id});
}

/// Writes a backlog task at the end of the note.
class WriteFromBacklogEvent extends TasksEvent {
  final String id;

  WriteFromBacklogEvent({required this.id});
}

/// Takes a task out of the backlog without writing it.
class RemoveFromBacklogEvent extends TasksEvent {
  final String id;

  RemoveFromBacklogEvent({required this.id});
}

/// Says which task, if any, is open in the Pomodoro focus view. That task's own countdown stays
/// quiet there, with no "Time's up" or reminder, because the Pomodoro clock is the one that counts.
class SetFocusModeEvent extends TasksEvent {
  final String? taskId;

  SetFocusModeEvent({this.taskId});
}

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

/// Changes from another device reached the document.
class _RemoteChangesEvent extends TasksEvent {}

/// Deletes every task and the whole history on this device, see [TasksBloc.clearAll].
class _ClearAllEvent extends TasksEvent {
  final Completer<CRDTDocument> done;

  _ClearAllEvent(this.done);
}

class TasksBloc extends Bloc<TasksEvent, TasksState> {
  Timer? tick;
  // Made on the first sound, so a list that never rings needs no audio player.
  AudioPlayer? _audioPlayerOrNull;
  AudioPlayer get _audioPlayer => _audioPlayerOrNull ??= AudioPlayer();
  // Null until the saved document has been loaded; edits before that are ignored.
  TaskDocument? _doc;
  // Which task has the focus is local to this device.
  String? _focusId;
  // Countdown seen at the previous tick, per task, to detect when it crosses an alert point.
  final Map<String, int> _lastRemaining = {};
  bool _muted = false;
  int _taskLimit = defaultTaskLimit;
  // The task open in the Pomodoro focus view, whose countdown alerts are held back. Local to this
  // device.
  String? _focusModeId;
  final StreamController<String> _timeUp = StreamController<String>.broadcast();

  /// The name of each task whose countdown runs out, as it happens.
  Stream<String> get timeUp => _timeUp.stream;

  final _document = Completer<CRDTDocument>();
  bool _loading = false;
  StreamSubscription<CRDTDocumentEvent>? _remote;

  /// The task document, once loaded, for syncing with the group's other devices.
  Future<CRDTDocument> get document => _document.future;

  TasksBloc() : super(TasksState(tasks: [])) {
    on<AddTaskOnTopEvent>(_onAddTaskOnTop);
    on<AddNextTaskEvent>((e, emit) => _insert(emit, e.index + 1, e.id.value,
        e.name, e.timerLengthSeconds));
    on<InsertTaskEvent>((e, emit) => _insert(
        emit, e.index, e.id.value, e.name, e.timerLengthSeconds,
        notes: e.notes));
    on<SetDoneEvent>((e, emit) => _setDone(emit, e.index, e.done));
    on<EditTaskEvent>(_onEditTask);
    on<TearOffNoteEvent>(_onTearOff);
    on<CarryTaskEvent>(_onCarry);
    on<LetGoEvent>(_onLetGo);
    on<RemoveTaskEvent>(_onRemoveTask);
    on<DoneTaskEvent>(_onDoneTask);
    on<RestoreTaskEvent>(_onRestoreTask);
    on<FocusTaskEvent>(_onFocusTask);
    on<ResetTotalEvent>(_onResetTotal);
    on<ToggleMuteEvent>(_onToggleMute);
    on<SetTaskLimitEvent>(_onSetTaskLimit);
    on<AddToBacklogEvent>((e, emit) => _edit(
        emit,
        (doc) => doc.addToBacklog(e.id.value,
            name: e.name, notes: e.notes, timerLengthSeconds: e.timerLengthSeconds ?? 20 * 60)));
    on<MoveToBacklogEvent>((e, emit) => _edit(emit, (doc) {
          if (doc.pendingIds.contains(e.id)) doc.moveToBacklog(e.id);
        }));
    on<WriteFromBacklogEvent>(_onWriteFromBacklog);
    on<RemoveFromBacklogEvent>((e, emit) => _edit(emit, (doc) {
          if (doc.backlogIds.contains(e.id)) doc.removeFromBacklog(e.id);
        }));
    on<SetFocusModeEvent>((event, emit) => _focusModeId = event.taskId);
    on<MoveTaskEvent>(_onMoveTask);
    on<StartTimerEvent>(_onStartTimer);
    on<StopTimerEvent>(_onStopTimer);
    on<ResetTimerEvent>(_onResetTimer);
    on<ResumeTimerEvent>(_onResumeTimer);
    on<UpdateTimerEvent>(_onUpdateTimer);
    on<UpdateTaskNameEvent>(_onUpdateTaskName);
    on<UpdateTaskTimerEvent>(_onUpdateTaskTimer);
    on<LoadStateEvent>(_onLoadState);
    on<_ClearAllEvent>(_onClearAll);
    on<_RemoteChangesEvent>((event, emit) {
      emit(_view());
      _saveState();
    });

    add(LoadStateEvent());
    tick = Timer.periodic(Duration(seconds: 1), (_) {
      add(UpdateTimerEvent());
    });
  }

  TasksState _view() {
    final doc = _doc;
    if (doc == null) {
      return TasksState(tasks: [], muted: _muted, taskLimit: _taskLimit);
    }
    return TasksState(
      tasks: doc.tasks(focusId: _focusId),
      muted: _muted,
      taskLimit: _taskLimit,
      noteStartedAt: doc.noteStartedAt,
      pending: [for (final id in doc.pendingIds) doc.task(id)],
      backlog: [for (final id in doc.backlogIds) doc.task(id)],
      loaded: true,
    );
  }

  /// The task document, for reading the history. Null until loaded.
  TaskDocument? get taskDocument => _doc;

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

  /// Whether work is under way: the current task's timer runs, rather than a pause or nothing.
  bool _working(TaskDocument doc) => doc.ids.any((id) => doc.task(id).running);

  /// The task being worked on: the first one on the note not checked off.
  String? _currentId(TaskDocument doc) {
    for (final id in doc.ids) {
      if (doc.doneAt(id) == null) return id;
    }
    return null;
  }

  /// Only the current task is the one being worked on, so only its timer may run. Running it ends
  /// any pause being logged.
  void _runTop(TaskDocument doc, bool run) {
    final current = _currentId(doc);
    for (final id in doc.ids) {
      doc.setRunning(id, run && id == current);
    }
    if (run && current != null) doc.endPauses();
  }

  void _onAddTaskOnTop(AddTaskOnTopEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      doc.insert(0, event.id.value,
          name: event.name,
          notes: event.notes,
          timerLengthSeconds: event.timerLengthSeconds ?? 20 * 60);
      _runTop(doc, true);
      _focusId = event.id.value;
    });
  }

  void _insert(Emitter<TasksState> emit, int index, String id, String name,
      int? timerLengthSeconds,
      {String notes = ''}) {
    _edit(emit, (doc) {
      final working = _working(doc);
      doc.insert(index.clamp(0, doc.ids.length), id,
          name: name,
          notes: notes,
          timerLengthSeconds: timerLengthSeconds ?? 20 * 60);
      _runTop(doc, working);
      _focusId = id;
    });
  }

  /// Checking off the current task hands the timer on to the next unchecked one; unchecking a task
  /// above it takes the timer back.
  void _setDone(Emitter<TasksState> emit, int index, bool done) {
    final id = _idAt(index);
    if (id == null) return;
    _edit(emit, (doc) {
      if ((doc.doneAt(id) != null) == done) return;
      final working = _working(doc);
      doc.setRunning(id, false);
      doc.setDone(id, done);
      _runTop(doc, working);
    });
  }

  void _onEditTask(EditTaskEvent event, Emitter<TasksState> emit) {
    final id = event.id.value;
    _edit(emit, (doc) {
      final task = doc.task(id);
      if (task.name != event.name) doc.setName(id, event.name);
      final notes = event.notes;
      if (notes != null && task.notes != notes) doc.setNotes(id, notes);
      if (task.timerLengthSeconds != event.timerLengthSeconds) {
        _lastRemaining.remove(id);
        doc.setTimer(id, event.timerLengthSeconds, nowSeconds());
      }
    });
  }

  void _onTearOff(TearOffNoteEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      if (doc.ids.isEmpty) {
        doc.setNoteStartedAt(nowSeconds());
        return;
      }
      // Tearing off ends the work under way, and logs the break until the next task starts.
      final working = _working(doc);
      doc.tearOff(newId(), nowSeconds());
      if (working) doc.startPause(newId());
      _focusId = null;
    });
  }

  void _onCarry(CarryTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      if (!doc.pendingIds.contains(event.id)) return;
      final working = _working(doc);
      final newTaskId = newId();
      doc.carry(event.id, newTaskId, doc.ids.length);
      _runTop(doc, working);
    });
  }

  void _onWriteFromBacklog(WriteFromBacklogEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      if (!doc.backlogIds.contains(event.id)) return;
      final working = _working(doc);
      doc.writeFromBacklog(event.id, newId(), doc.ids.length);
      _runTop(doc, working);
    });
  }

  void _onLetGo(LetGoEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      for (final id in doc.pendingIds) {
        if (event.id == null || event.id == id) doc.letGo(id);
      }
    });
  }

  /// Takes the task at [index] off the note with [takeOff]. When it was being worked on, work
  /// carries on with the next unchecked task.
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
      _takeOff(emit, event.index, (doc, id) => doc.removeAt(event.index, id));

  void _onDoneTask(DoneTaskEvent event, Emitter<TasksState> emit) =>
      _setDone(emit, event.index, true);

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

  /// Moving an unchecked task above the current one makes it the one being worked on.
  void _onMoveTask(MoveTaskEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) {
      final working = _working(doc);
      doc.move(event.fromIndex, event.toIndex);
      _runTop(doc, working);
    });
  }

  // Starting, pausing and resuming act on the current task, the only one with a running timer.

  void _onStartTimer(StartTimerEvent event, Emitter<TasksState> emit) {
    if (_doc == null || _currentId(_doc!) == null) return;
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
    if (_doc == null || _currentId(_doc!) == null) return;
    _edit(emit, (doc) => _runTop(doc, true));
  }

  void _onResetTimer(ResetTimerEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _lastRemaining.remove(id);
    _edit(
        emit,
        (doc) =>
            doc.setTimer(id, doc.task(id).timerLengthSeconds, nowSeconds()));
  }

  void _onResetTotal(ResetTotalEvent event, Emitter<TasksState> emit) {
    final id = _idAt(event.index);
    if (id == null) return;
    _edit(emit, (doc) => doc.setTotalResetAt(id, nowSeconds()));
  }

  void _onSetTaskLimit(SetTaskLimitEvent event, Emitter<TasksState> emit) {
    _taskLimit = event.limit.clamp(minTaskLimit, maxTaskLimit);
    emit(_view());
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt('taskLimit', _taskLimit));
  }

  void _onToggleMute(ToggleMuteEvent event, Emitter<TasksState> emit) {
    _muted = !_muted;
    emit(_view());
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('muted', _muted));
  }

  void _onUpdateTimer(UpdateTimerEvent event, Emitter<TasksState> emit) {
    // An empty note left from an earlier day becomes today's, with nothing to tear off.
    final doc = _doc;
    final started = doc?.noteStartedAt;
    if (doc != null &&
        doc.ids.isEmpty &&
        (started == null || dayOf(started) != dayOf(nowSeconds()))) {
      doc.setNoteStartedAt(nowSeconds());
      _saveState();
    }
    final view = _view();
    final now = nowSeconds();
    for (final task in view.tasks) {
      final remaining = task.remainingSecondsAt(now);
      final previous = _lastRemaining[task.id.value];
      _lastRemaining[task.id.value] = remaining;
      if (previous == null || previous == remaining) continue;
      if (task.id.value == _focusModeId) continue;

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

  /// Deletes every task, note and logged time on this device and starts over with an empty
  /// document, written under a new peer id so it shares no change ids with the old one. Returns
  /// the new document, for sync to use instead of the old one. Settings stay as they are.
  Future<CRDTDocument> clearAll() {
    final done = Completer<CRDTDocument>();
    add(_ClearAllEvent(done));
    return done.future;
  }

  Future<void> _onClearAll(_ClearAllEvent event, Emitter<TasksState> emit) async {
    // Wait for the saved document to load, so it can't come back over the empty one.
    await document;
    final prefs = await SharedPreferences.getInstance();
    final peerId = PeerId.generate().toString();
    await prefs.setString('peerId', peerId);
    await prefs.remove('focusId');
    await _remote?.cancel();
    final doc = TaskDocument(
        CRDTDocument(peerId: PeerId.parse(peerId), documentId: 'tasks'));
    doc.setNoteStartedAt(nowSeconds());
    _doc = doc;
    _focusId = null;
    _focusModeId = null;
    _lastRemaining.clear();
    _listenForRemote(doc);
    emit(_view());
    await _saveState();
    event.done.complete(doc.doc);
  }

  void _listenForRemote(TaskDocument doc) {
    _remote = doc.doc.events.listen((e) {
      if (e is DocumentChangesApplied && e.source == ChangeSource.ingested) {
        add(_RemoteChangesEvent());
      }
    });
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
    // LoadStateEvent can arrive twice (the app adds one too); only the first one loads.
    if (_loading) return;
    _loading = true;
    final prefs = await SharedPreferences.getInstance();
    _muted = prefs.getBool('muted') ?? false;
    // A new key: the old 'noteLines' was a hard cap counting done tasks too, so it doesn't carry
    // over.
    _taskLimit = (prefs.getInt('taskLimit') ?? defaultTaskLimit)
        .clamp(minTaskLimit, maxTaskLimit);

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

    // Earlier versions let any task run; now only the current one may.
    _runTop(doc, _working(doc));
    // Documents from before notes: the tasks on the list make up today's note.
    if (doc.noteStartedAt == null) doc.setNoteStartedAt(nowSeconds());
    _doc = doc;
    _listenForRemote(doc);
    _document.complete(doc.doc);
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
    _remote?.cancel();
    _timeUp.close();
    return super.close();
  }
}
