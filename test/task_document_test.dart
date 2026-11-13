import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/category/default_categories.dart';
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
    d.removeAt(0, 'b');
    expect(d.ids, ['a']);
    expect(d.status('b'), TaskStatus.deleted);
    d.restore(1, 'b');
    expect(d.ids, ['a', 'b']);
    expect(d.status('b'), TaskStatus.open);
  });

  test('a task checked off stays on the note, struck through, until unchecked', () {
    final d = newDoc()
      ..insert(0, 'a')
      ..insert(1, 'b');
    d.setDone('a', true);
    expect(d.ids, ['a', 'b']);
    expect(d.task('a').done, isTrue);
    expect(d.status('a'), TaskStatus.done);
    d.setDone('a', false);
    expect(d.task('a').done, isFalse);
    expect(d.status('a'), TaskStatus.open);
  });

  test('tearing off a note keeps it and leaves its unfinished tasks pending', () {
    final d = newDoc()
      ..setNoteStartedAt(100)
      ..insert(0, 'a', name: 'write report')
      ..insert(1, 'b', name: 'call bank', timerLengthSeconds: 600)
      ..insert(2, 'c', name: 'buy milk');
    d.setDone('a', true);
    d.tearOff('n1', 200);

    expect(d.ids, isEmpty);
    expect(d.noteStartedAt, 200);
    final note = d.notes.single;
    expect((note.startedAt, note.closedAt), (100, 200));
    expect(note.taskIds, ['a', 'b', 'c']);
    expect(d.pendingIds, ['b', 'c']);

    d.carry('b', 'b2', 0);
    d.letGo('c');
    expect(d.pendingIds, isEmpty);
    expect(d.ids, ['b2']);
    expect(d.task('b2').name, 'call bank');
    expect(d.task('b2').timerLengthSeconds, 600);
    expect(d.task('b2').carriedFrom, 'b');
    expect(d.statuses(['a', 'b', 'c', 'b2']), {
      'a': TaskStatus.done,
      'b': TaskStatus.carried,
      'c': TaskStatus.letGo,
      'b2': TaskStatus.open,
    });
  });

  test('every task written is listed, pauses left out', () {
    final d = newDoc()
      ..insert(0, 'a')
      ..setNoteStartedAt(5);
    d.startPause('p');
    d.tearOff('n1', 10);
    expect(d.allTaskIds, ['a']);
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

  group('categories', () {
    test('are added, renamed, ordered and deleted, and a deleted one still reads', () {
      final d = newDoc()
        ..addCategory('w', 'Work', keywords: 'office', at: 2)
        ..addCategory('h', 'Health', at: 1);
      expect(d.categories().map((c) => c.name).skip(defaultCategories.length), ['Health', 'Work']);
      d.setCategoryName('w', 'Job');
      d.setCategoryKeywords('w', 'office meeting');
      expect(d.categories().last.keywords, 'office meeting');
      d.removeCategory('h');
      expect(d.categories().last.name, 'Job');
      expect(d.categories().length, defaultCategories.length + 1);
      expect(d.categories(deleted: true).skip(defaultCategories.length).map((c) => (c.name, c.deleted)),
          [('Health', true), ('Job', false)]);
    });

    test('the defaults need nothing in the document, and only changes to them are written', () {
      final d = newDoc();
      expect(d.categories().map((c) => c.id), [for (final c in defaultCategories) c.id]);
      expect(d.categories().every((c) => c.isDefault), isTrue);
      d.setCategoryRules('personal-projects', 'bringmeback');
      d.removeCategory('leisure');
      final p = d.categories().firstWhere((c) => c.id == 'personal-projects');
      expect((p.name, p.rules), ('Personal projects', 'bringmeback'));
      expect(p.rulePhrases, ['bringmeback']);
      expect(d.categories().map((c) => c.id), isNot(contains('leisure')));
      d.restoreDefaultCategories();
      expect(d.categories().map((c) => c.id), contains('leisure'));
    });

    test('are not listed as tasks', () {
      final d = newDoc()
        ..insert(0, 'a', name: 'task')
        ..addCategory('w', 'Work');
      expect(d.allTaskIds, ['a']);
    });

    test('a task keeps its category and who chose it, and carries both to a new note', () {
      final d = newDoc()
        ..addCategory('w', 'Work')
        ..insert(0, 'a', name: 'report', category: 'w')
        ..insert(1, 'b', name: 'standup');
      expect((d.task('a').category, d.task('a').categoryByHand), ('w', false));
      d.setTaskCategory('b', 'w', byHand: true);
      expect((d.task('b').category, d.task('b').categoryByHand), ('w', true));
      expect(d.categoryExamples().map((e) => (e.id, e.name, e.category)), [('b', 'standup', 'w')]);
      d.tearOff('n', 10);
      d.carry('b', 'b2', 0);
      expect((d.task('b2').category, d.task('b2').categoryByHand), ('w', true));
      d.clearTaskCategory('b2');
      expect((d.task('b2').category, d.task('b2').categoryByHand), (null, false));
    });

    test('sync between devices, and edits to different fields both survive', () {
      final a = newDoc()..addCategory('w', 'Work', keywords: 'office');
      final b = newDoc();
      exchange(a, b);
      expect(b.categories().last.name, 'Work');
      a.setCategoryName('w', 'Job');
      b.setCategoryKeywords('w', 'office meeting');
      b.insert(0, 't', name: 'report', category: 'w');
      exchange(a, b);
      for (final d in [a, b]) {
        final c = d.categories().last;
        expect((c.name, c.keywords), ('Job', 'office meeting'));
        expect(d.task('t').category, 'w');
      }
    });

    test('fields of the wrong type from another device read as no category', () {
      final d = newDoc()..insert(0, 'a', name: 'x');
      final other = CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks');
      CRDTMapHandler<Object?>(other, 'fields', handlerType: 'bmb.fields')
        ..set('a/category', 42)
        ..set('category/c/name', 7)
        ..set('category/d/name', 'Ok')
        ..set('category/d/addedAt', 'soon');
      d.doc.importChanges(other.exportChanges());
      expect(d.task('a').category, isNull);
      expect(d.categories().skip(defaultCategories.length).map((c) => (c.id, c.addedAt)),
          [('d', 0)]);
    });
  });
}
