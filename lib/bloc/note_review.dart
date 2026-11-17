import 'tasks_bloc.dart';

/// A task rewritten this many times after it was written on the note is flagged when the note is
/// torn off: changing the same task again and again usually means it wasn't clear yet what it was.
const taskRewriteThreshold = 3;

/// This many rewrites on one note, across all its tasks, are flagged when the note is torn off even
/// when no single task reached [taskRewriteThreshold]: the plan as a whole kept changing.
const noteRewriteThreshold = 5;

/// What was observed on a note when it is torn off, worth telling the user about. For now it looks
/// at rewrites: tasks changed after they were written on the note, a sign of decisions changing
/// again and again, or of a plan made before it was clear what to do. More observations can join
/// it later.
class NoteReview {
  /// Tasks rewritten at least [taskRewriteThreshold] times, with how many times, most first.
  final List<(String name, int rewrites)> oftenRewritten;

  /// Rewrites on the note, across all its tasks.
  final int totalRewrites;

  const NoteReview({required this.oftenRewritten, required this.totalRewrites});

  /// Reviews the tasks on a note about to be torn off.
  factory NoteReview.of(Iterable<TaskState> tasks) {
    final often = [
      for (final t in tasks)
        if (t.rewrites >= taskRewriteThreshold) (t.name, t.rewrites)
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return NoteReview(
        oftenRewritten: often, totalRewrites: tasks.fold(0, (sum, t) => sum + t.rewrites));
  }

  /// Whether one task was rewritten again and again.
  bool get tasksKeptChanging => oftenRewritten.isNotEmpty;

  /// Whether the note as a whole was rewritten a lot.
  bool get planKeptChanging => totalRewrites >= noteRewriteThreshold;

  /// Whether anything was observed that is worth telling.
  bool get flagged => tasksKeptChanging || planKeptChanging;

  /// The observations, one sentence each, for the message shown at tear-off.
  List<String> get observations => [
        for (final (name, n) in oftenRewritten)
          '${name.isEmpty ? 'An untitled task' : '"$name"'} was rewritten $n times after you '
              'wrote it on the note.',
        // The total adds something only when tasks not named above were rewritten too.
        if (planKeptChanging && totalRewrites > oftenRewritten.fold(0, (sum, t) => sum + t.$2))
          'Tasks on this note were rewritten $totalRewrites times in all.',
      ];

  /// What the observations probably mean, and what to try.
  static const meaning = 'Changing tasks again and again after planning them usually means the '
      'plan was made before it was clear what to do, or decisions kept changing. Next time, try '
      'deciding what a task really is before writing it, or split a vague one into smaller steps.';
}
