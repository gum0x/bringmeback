import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

TaskState task(String name, int rewrites) =>
    TaskState(name: name, id: ValueKey(name), rewrites: rewrites);

void main() {
  test('a note with a few rewrites here and there is not flagged', () {
    final review = NoteReview.of([task('a', 2), task('b', 1), task('c', 1), task('d', 0)]);
    expect(review.totalRewrites, 4);
    expect(review.flagged, isFalse);
    expect(review.observations, isEmpty);
  });

  test('a task rewritten again and again is flagged by name', () {
    final review = NoteReview.of([task('Write report', taskRewriteThreshold), task('b', 1)]);
    expect(review.tasksKeptChanging, isTrue);
    expect(review.planKeptChanging, isFalse);
    expect(review.observations,
        ['"Write report" was rewritten 3 times after you wrote it on the note.']);
  });

  test('many rewrites across the note are flagged even when no task reached the threshold', () {
    final review = NoteReview.of([task('a', 2), task('b', 2), task('c', 1)]);
    expect(review.tasksKeptChanging, isFalse);
    expect(review.planKeptChanging, isTrue);
    expect(review.observations, ['Tasks on this note were rewritten 5 times in all.']);
  });

  test('the total is told only when it adds to the tasks named', () {
    expect(NoteReview.of([task('a', 5)]).observations, hasLength(1));
    final review = NoteReview.of([task('a', 4), task('b', 3), task('', 1)]);
    expect(review.observations, [
      '"a" was rewritten 4 times after you wrote it on the note.',
      '"b" was rewritten 3 times after you wrote it on the note.',
      'Tasks on this note were rewritten 8 times in all.',
    ]);
    expect(NoteReview.of([task('', 3)]).observations.single,
        startsWith('An untitled task was rewritten 3 times'));
  });
}
