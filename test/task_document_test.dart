import 'package:bringmeback/bloc/task_document.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

TaskDocument newDoc([PeerId? peer]) =>
    TaskDocument(CRDTDocument(peerId: peer ?? PeerId.generate(), documentId: 'tasks'));

/// Sends each side the changes it is missing.
void exchange(TaskDocument a, TaskDocument b) {
  b.doc.importChanges(a.doc.exportChanges(fromVersionVector: b.doc.getVersionVector()));
  a.doc.importChanges(b.doc.exportChanges(fromVersionVector: a.doc.getVersionVector()));
}

void main() {
  test('insert, rename, move and remove', () {
    final d = newDoc();
    d.insert(0, 'a', name: 'first');
    d.insert(1, 'b');
    d.setName('b', 'second');
    expect(d.tasks().map((t) => t.name), ['first', 'second']);
    d.move(1, 0);
    expect(d.ids, ['b', 'a']);
    d.removeAt(0);
    expect(d.ids, ['a']);
  });

  test('a task marked done leaves the list and comes back on restore', () {
    final d = newDoc()
      ..insert(0, 'a')
      ..insert(1, 'b');
    d.markDone(0, 'a');
    expect(d.ids, ['b']);
    expect(d.doneAt('a'), isNotNull);
    d.restore(0, 'a');
    expect(d.ids, ['a', 'b']);
    expect(d.doneAt('a'), isNull);
  });

  test('pauses are logged as hidden tasks with one time entry', () {
    final d = newDoc()..insert(0, 'a');
    d.startPause('p1');
    expect(d.ids, ['a']);
    expect(d.pauseIds, ['p1']);
    expect(d.task('p1').running, isTrue);
    d.endPauses();
    expect(d.task('p1').running, isFalse);
    expect(d.task('p1').entries, hasLength(1));
  });

  test('starting and stopping opens and closes a time entry', () {
    final d = newDoc()..insert(0, 'a', running: true);
    expect(d.task('a').running, isTrue);
    d.setRunning('a', true);
    expect(d.task('a').entries, hasLength(1));
    d.setRunning('a', false);
    expect(d.task('a').running, isFalse);
    expect(d.task('a').entries.single.end, isNotNull);
  });

  test('marks the focused task', () {
    final d = newDoc()
      ..insert(0, 'a')
      ..insert(1, 'b');
    expect(d.tasks(focusId: 'b').map((t) => t.inFocus), [false, true]);
  });

  test('survives a save and reload, and later edits still win', () {
    final peer = PeerId.generate();
    final d = newDoc(peer)..insert(0, 'a', name: 'old', running: true);
    final reloaded = newDoc(peer)..importEncodedChanges(d.encodeChanges());
    expect(reloaded.task('a').name, 'old');
    expect(reloaded.task('a').running, isTrue);
    reloaded.setName('a', 'new');
    expect(reloaded.task('a').name, 'new');
  });

  test('two devices converge after exchanging changes', () {
    final laptop = newDoc()..insert(0, 'a', name: 'write report', running: true);
    final phone = newDoc();
    exchange(laptop, phone);
    expect(phone.task('a').running, isTrue);

    // The phone stops the timer the laptop started, and the laptop adds a task meanwhile.
    phone.setRunning('a', false);
    laptop.insert(1, 'b', name: 'call bank');
    exchange(laptop, phone);

    for (final d in [laptop, phone]) {
      expect(d.ids, ['a', 'b']);
      expect(d.task('a').running, isFalse);
      expect(d.task('b').name, 'call bank');
    }
  });
}
