import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../category/categoriser.dart';
import '../ticker.dart';
import 'task_document.dart';

final Random _random = Random.secure();

/// A random 128-bit id, hex encoded. Unlike timestamps, ids made on different devices can't collide.
String newId() => List.generate(
    16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

int nowSeconds() =>
    DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

/// How many tasks fit on a note unless Settings says otherwise, done ones included. A small note
/// keeps the day focused: when it is full, finish or delete something before writing more.
const defaultNoteLines = 10;

/// The range Settings offers for the size of a note.
const minNoteLines = 3;
const maxNoteLines = 20;

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

  /// The id of the category the task is filed under, or null for none yet.
  final String? category;

  /// Whether the user chose [category] (or chose none), rather than the categoriser.
  final bool categoryByHand;

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
      this.carriedFrom,
      this.category,
      this.categoryByHand = false})
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

  /// Whether the document has loaded.
  final bool loaded;

  /// How many tasks fit on a note, set in Settings.
  final int noteLines;

  /// The categories tasks are filed under, set in Settings and synced. Deleted ones left out.
  final List<TaskCategory> categories;

  TasksState(
      {required this.tasks,
      this.muted = false,
      this.noteLines = defaultNoteLines,
      this.categories = const [],
      int? noteStartedAt,
      this.pending = const [],
      this.loaded = false})
      : noteStartedAt = noteStartedAt ?? nowSeconds();

  TasksState copyWith({List<TaskState>? tasks, bool? muted}) {
    return TasksState(
      tasks: tasks ?? this.tasks,
      muted: muted ?? this.muted,
      noteStartedAt: noteStartedAt,
      pending: pending,
      loaded: loaded,
      noteLines: noteLines,
      categories: categories,
    );
  }

  /// The category with [id], or null when there is none in the list.
  TaskCategory? category(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The index of the task being worked on: the first one not checked off, or -1.
  int get currentIndex => tasks.indexWhere((t) => !t.done);

  bool get full => tasks.length >= noteLines;

  bool get allDone => tasks.isNotEmpty && tasks.every((t) => t.done);

  /// Whether the note was started on an earlier day and has tasks on it: time to tear it off.
  bool needsTearOff([int? now]) =>
      tasks.isNotEmpty && dayOf(noteStartedAt) != dayOf(now ?? nowSeconds());
}

abstract class TasksEvent {}

/// What the user picked for a task's category.
class CategoryPick {
  /// The category, or null for none.
  final String? id;

  /// Whether the user chose it. When not, the categoriser picks one.
  final bool byHand;

  /// Let the categoriser pick.
  const CategoryPick.auto()
      : id = null,
        byHand = false;

  /// The user's own choice; [id] null for none.
  const CategoryPick.hand(this.id) : byHand = true;

  @override
  bool operator ==(Object other) =>
      other is CategoryPick && other.id == id && other.byHand == byHand;

  @override
  int get hashCode => Object.hash(id, byHand);
}

/// Writes a task on top of the note, as an interruption: it becomes the current task and its timer
/// runs.
class AddTaskOnTopEvent extends TasksEvent {
  final String name;
  final ValueKey<String> id;
  final int? timerLengthSeconds;

  final String notes;
  final CategoryPick category;

  AddTaskOnTopEvent(
      {required this.name,
      required this.id,
      this.timerLengthSeconds,
      this.notes = '',
      this.category = const CategoryPick.auto()});
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
  final CategoryPick category;

  InsertTaskEvent(
      {required this.index,
      required this.name,
      required this.id,
      this.timerLengthSeconds,
      this.notes = '',
      this.category = const CategoryPick.auto()});
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

  /// The category picked in the dialog, or null to leave it as it is.
  final CategoryPick? category;

  EditTaskEvent(
      {required this.id,
      required this.name,
      required this.timerLengthSeconds,
      this.notes,
      this.category});
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

/// Sets how many tasks fit on a note. Tasks already written stay when it shrinks; only writing more
/// waits until there is room.
class SetNoteLinesEvent extends TasksEvent {
  final int lines;

  SetNoteLinesEvent(this.lines);
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

/// Files a task under a category, from the task's category menu.
class SetTaskCategoryEvent extends TasksEvent {
  final String id;
  final CategoryPick category;

  SetTaskCategoryEvent({required this.id, required this.category});
}

/// Adds a category to the list in Settings.
class AddCategoryEvent extends TasksEvent {
  final String name;
  final String keywords;

  AddCategoryEvent({required this.name, this.keywords = ''});
}

/// Renames a category or changes its keywords.
class EditCategoryEvent extends TasksEvent {
  final String id;
  final String name;
  final String keywords;

  EditCategoryEvent({required this.id, required this.name, required this.keywords});
}

class RemoveCategoryEvent extends TasksEvent {
  final String id;

  RemoveCategoryEvent({required this.id});
}

/// Fills an empty category list with [suggestedCategories], as a start to edit.
class AddSuggestedCategoriesEvent extends TasksEvent {}

/// The categoriser is ready to file the tasks [ids].
class _CategoriseEvent extends TasksEvent {
  final List<String> ids;
  final Categoriser categoriser;

  _CategoriseEvent(this.ids, this.categoriser);
}

/// Changes from another device reached the document.
class _RemoteChangesEvent extends TasksEvent {}

/// Deletes every task and the whole history on this device, see [TasksBloc.clearAll].
class _ClearAllEvent extends TasksEvent {
  final Completer<CRDTDocument> done;

  _ClearAllEvent(this.done);
}

class TasksBloc extends Bloc<TasksEvent, TasksState> {
  SecondTicker? tick;
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
  int _noteLines = defaultNoteLines;
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

  // Loads the categoriser, on first use; tests pass their own.
  final Future<Categoriser> Function() _categoriser;

  TasksBloc({Future<Categoriser> Function()? categoriser})
      : _categoriser = categoriser ?? Categoriser.bundled,
        super(TasksState(tasks: [])) {
    on<AddTaskOnTopEvent>(_onAddTaskOnTop);
    on<AddNextTaskEvent>((e, emit) => _insert(emit, e.index + 1, e.id.value,
        e.name, e.timerLengthSeconds));
    on<InsertTaskEvent>((e, emit) => _insert(
        emit, e.index, e.id.value, e.name, e.timerLengthSeconds,
        notes: e.notes, category: e.category));
    on<SetTaskCategoryEvent>(_onSetTaskCategory);
    on<AddCategoryEvent>((e, emit) => _editCategories(
        emit, (doc) => doc.addCategory(newId(), e.name.trim(), keywords: e.keywords.trim())));
    on<EditCategoryEvent>((e, emit) => _editCategories(emit, (doc) {
          doc.setCategoryName(e.id, e.name.trim());
          doc.setCategoryKeywords(e.id, e.keywords.trim());
        }));
    on<RemoveCategoryEvent>((e, emit) => _editCategories(emit, (doc) => doc.removeCategory(e.id)));
    on<AddSuggestedCategoriesEvent>((e, emit) => _editCategories(emit, (doc) {
          if (doc.categories().isNotEmpty) return;
          final at = DateTime.now().millisecondsSinceEpoch;
          for (final (i, c) in suggestedCategories.indexed) {
            doc.addCategory(newId(), c.name, keywords: c.keywords, at: at + i);
          }
        }));
    on<_CategoriseEvent>(_onCategorise);
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
    on<SetNoteLinesEvent>(_onSetNoteLines);
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
    tick = SecondTicker(() => add(UpdateTimerEvent()));
  }

  TasksState _view() {
    final doc = _doc;
    if (doc == null) {
      return TasksState(tasks: [], muted: _muted, noteLines: _noteLines);
    }
    return TasksState(
      tasks: doc.tasks(focusId: _focusId),
      muted: _muted,
      noteLines: _noteLines,
      categories: doc.categories(),
      noteStartedAt: doc.noteStartedAt,
      pending: [for (final id in doc.pendingIds) doc.task(id)],
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
      if (doc.ids.length >= _noteLines) return;
      doc.insert(0, event.id.value,
          name: event.name,
          notes: event.notes,
          category: event.category.id,
          categoryByHand: event.category.byHand,
          timerLengthSeconds: event.timerLengthSeconds ?? 20 * 60);
      _runTop(doc, true);
      _focusId = event.id.value;
    });
    if (!event.category.byHand) _categorise([event.id.value]);
  }

  void _insert(Emitter<TasksState> emit, int index, String id, String name,
      int? timerLengthSeconds,
      {String notes = '', CategoryPick category = const CategoryPick.auto()}) {
    _edit(emit, (doc) {
      if (doc.ids.length >= _noteLines) return;
      final working = _working(doc);
      doc.insert(index.clamp(0, doc.ids.length), id,
          name: name,
          notes: notes,
          category: category.id,
          categoryByHand: category.byHand,
          timerLengthSeconds: timerLengthSeconds ?? 20 * 60);
      _runTop(doc, working);
      _focusId = id;
    });
    if (!category.byHand) _categorise([id]);
  }

  /// Files the tasks [ids] whose category the user hasn't chosen, once the categoriser has loaded.
  /// Only the device where the task was written or changed does it; the result syncs like any edit.
  Future<void> _categorise(List<String> ids) async {
    final doc = _doc;
    if (ids.isEmpty || doc == null) return;
    // With no categories there is nothing to choose from, and no need to load the vectors.
    if (doc.categories().isEmpty && ids.every((id) => doc.task(id).category == null)) return;
    final Categoriser categoriser;
    try {
      categoriser = await _categoriser();
    } on Object catch (e) {
      // Tasks then simply stay without a category; the user can still pick one.
      debugPrint('Categoriser unavailable: $e');
      return;
    }
    if (!isClosed) add(_CategoriseEvent(ids, categoriser));
  }

  void _onCategorise(_CategoriseEvent event, Emitter<TasksState> emit) {
    final doc = _doc;
    if (doc == null) return;
    final categories = doc.categories();
    final examples = [
      for (final e in doc.categoryExamples()) (text: e.name, category: e.category)
    ];
    var changed = false;
    for (final id in event.ids) {
      final task = doc.task(id);
      // Gone, or the user chose since: their choice stands.
      if (task.categoryByHand || doc.fieldInt('$id/timerStartAt') == null) continue;
      final pick = event.categoriser.categorise(task.name, categories, examples: examples);
      if (pick == task.category) continue;
      doc.setTaskCategory(id, pick, byHand: false);
      changed = true;
    }
    if (!changed) return;
    emit(_view());
    _saveState();
  }

  void _onSetTaskCategory(SetTaskCategoryEvent event, Emitter<TasksState> emit) {
    _edit(emit, (doc) => _pickCategory(doc, event.id, event.category));
  }

  /// Files task [id] as the user picked: under their choice, or back to the categoriser.
  void _pickCategory(TaskDocument doc, String id, CategoryPick pick) {
    final task = doc.task(id);
    if (pick.byHand) {
      if (!task.categoryByHand || task.category != pick.id) {
        doc.setTaskCategory(id, pick.id, byHand: true);
      }
    } else if (task.categoryByHand) {
      doc.clearTaskCategory(id);
      _categorise([id]);
    }
  }

  /// Changes the category list, then files again the tasks on the note the user hasn't filed.
  void _editCategories(Emitter<TasksState> emit, void Function(TaskDocument doc) change) {
    _edit(emit, change);
    final doc = _doc;
    if (doc == null) return;
    _categorise([for (final id in doc.ids) if (!doc.task(id).categoryByHand) id]);
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
      if (event.category case final pick?) _pickCategory(doc, id, pick);
      // A new name may belong somewhere else.
      if (task.name != event.name && !doc.task(id).categoryByHand) _categorise([id]);
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
      if (doc.ids.length >= _noteLines) return;
      if (!doc.pendingIds.contains(event.id)) return;
      final working = _working(doc);
      final newTaskId = newId();
      doc.carry(event.id, newTaskId, doc.ids.length);
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

  void _onSetNoteLines(SetNoteLinesEvent event, Emitter<TasksState> emit) {
    _noteLines = event.lines.clamp(minNoteLines, maxNoteLines);
    emit(_view());
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt('noteLines', _noteLines));
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
    final task = _doc?.task(event.id.value);
    if (task != null && !task.categoryByHand) _categorise([event.id.value]);
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
    _noteLines = (prefs.getInt('noteLines') ?? defaultNoteLines)
        .clamp(minNoteLines, maxNoteLines);

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
