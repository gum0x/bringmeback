import 'package:bringmeback/bloc/history.dart';
import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'doc_sync_test.dart' show newDocument, twoDevices;
import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';

/// Tearing off a note on one device, and what the group's other devices see of it: the note kept in
/// History, the fresh note, and the unfinished tasks waiting to be written again or let go.
void main() {
  setUpAll(loadSymbolonForTests);

  final yesterday = nowSeconds() - 24 * 3600;

  /// Yesterday's note with one task done and two unfinished, written on [d].
  void writeYesterdaysNote(TaskDocument d) => d
    ..setNoteStartedAt(yesterday)
    ..insert(0, 'done', name: 'Write report')
    ..insert(1, 'carry', name: 'Call the bank', timerLengthSeconds: 600, notes: 'Ask about fees')
    ..insert(2, 'drop', name: 'Buy milk')
    ..setDone('done', true);

  /// Both devices read the same notes, the same note in use, and the same unfinished tasks.
  void expectSameNotes(TaskDocument a, TaskDocument b) {
    expect(b.ids, a.ids);
    expect(b.noteStartedAt, a.noteStartedAt);
    String read(NoteRecord n) => '${n.id} ${n.startedAt}-${n.closedAt}: ${n.taskIds.join(',')}';
    expect(b.notes.map(read), a.notes.map(read));
    expect(b.pendingIds, a.pendingIds);
    final ids = {...a.allTaskIds, ...b.allTaskIds};
    expect(b.statuses(ids), a.statuses(ids));
    expect(b.doc.exportChanges().length, a.doc.exportChanges().length);
  }

  test('a note torn off on one device is torn off on the other, and kept in its History', () async {
    final a = newDocument();
    writeYesterdaysNote(a);
    final b = newDocument();
    final (first, second, _) = await twoDevices(a, b);
    expect(b.ids, ['done', 'carry', 'drop']);
    expect(b.noteStartedAt, yesterday);

    final at = nowSeconds();
    a.tearOff('n1', at);
    await pumpEventQueue();

    expect(b.ids, isEmpty, reason: 'The torn-off note leaves the other device too');
    expect(b.noteStartedAt, at, reason: 'Both start the fresh note at the same time');
    final note = b.notes.single;
    expect((note.id, note.startedAt, note.closedAt), ('n1', yesterday, at));
    expect(note.taskIds, ['done', 'carry', 'drop']);
    expect(b.pendingIds, ['carry', 'drop']);
    expect(b.statuses(['done', 'carry', 'drop']), {
      'done': TaskStatus.done,
      'carry': TaskStatus.pending,
      'drop': TaskStatus.pending,
    });
    final history = buildHistory(b);
    expect(history.notes, hasLength(1), reason: 'The fresh note is empty, so only the torn one');
    expect([for (final t in history.notes.single.tasks) t.name],
        ['Write report', 'Call the bank', 'Buy milk']);
    expectSameNotes(a, b);

    await first.close();
    await second.close();
  });

  test('carrying and letting go on the other device reach the one that tore the note off',
      () async {
    final a = newDocument();
    writeYesterdaysNote(a);
    final b = newDocument();
    final (first, second, _) = await twoDevices(a, b);
    a.tearOff('n1', nowSeconds());
    await pumpEventQueue();

    // B writes one unfinished task on today's note and lets go of the other.
    b.carry('carry', 'carried', 0);
    b.letGo('drop');
    await pumpEventQueue();

    expect(a.pendingIds, isEmpty);
    expect(a.ids, ['carried']);
    final carried = a.task('carried');
    expect(carried.name, 'Call the bank');
    expect(carried.notes, 'Ask about fees');
    expect(carried.timerLengthSeconds, 600);
    expect(carried.carriedFrom, 'carry');
    expect(a.statuses(['done', 'carry', 'drop', 'carried']), {
      'done': TaskStatus.done,
      'carry': TaskStatus.carried,
      'drop': TaskStatus.letGo,
      'carried': TaskStatus.open,
    });
    // The old note keeps its lines; the carried task is today's.
    expect(a.notes.single.taskIds, ['done', 'carry', 'drop']);
    expectSameNotes(a, b);

    // Edits to the carried task on A reach B, and the torn note stays as it was.
    a.setName('carried', 'Call the bank before noon');
    a.setDone('carried', true);
    await pumpEventQueue();
    expect(b.task('carried').name, 'Call the bank before noon');
    expect(b.task('carried').done, isTrue);
    expect(b.task('carry').name, 'Call the bank');
    expectSameNotes(a, b);

    await first.close();
    await second.close();
  });

  test('a note torn off while the other device was apart reaches it when they sync again',
      () async {
    final a = newDocument();
    writeYesterdaysNote(a);
    final b = newDocument();
    final (first, second, net) = await twoDevices(a, b);

    net.hold = true;
    final at = nowSeconds();
    a.tearOff('n1', at);
    a.carry('carry', 'carried', 0);
    await pumpEventQueue();
    expect(b.ids, ['done', 'carry', 'drop'], reason: 'Nothing arrives while held');

    net.release();
    await pumpEventQueue();
    expect(b.ids, ['carried']);
    expect(b.noteStartedAt, at);
    expect(b.notes.single.taskIds, ['done', 'carry', 'drop']);
    expect(b.pendingIds, ['drop']);
    expectSameNotes(a, b);
    expect(first.state.inSync, {second.state.device!.id});
    expect(second.state.inSync, {first.state.device!.id});

    await first.close();
    await second.close();
  });

  test('a task written on the old note while apart from the tear-off lands on the fresh note',
      () async {
    final a = newDocument();
    writeYesterdaysNote(a);
    final b = newDocument();
    final (first, second, net) = await twoDevices(a, b);

    net.hold = true;
    a.tearOff('n1', nowSeconds());
    // B hasn't seen the tear-off yet and writes another task on what it still shows.
    b.insert(3, 'late', name: 'Written on B');
    await pumpEventQueue();

    net.release();
    await pumpEventQueue();
    // A tore off only the tasks it had; B's task is not lost, and is on the note in use.
    expect(a.ids, ['late']);
    expect(a.notes.single.taskIds, ['done', 'carry', 'drop']);
    expect(a.status('late'), TaskStatus.open);
    expect(a.pendingIds, ['carry', 'drop']);
    expectSameNotes(a, b);

    await first.close();
    await second.close();
  });

  test('a note torn off on both devices while apart is kept once', () async {
    final a = newDocument();
    writeYesterdaysNote(a);
    final b = newDocument();
    final (first, second, net) = await twoDevices(a, b);

    // Both devices open the next morning without reaching each other, and both tear the note off.
    net.hold = true;
    a.tearOff('n-a', nowSeconds());
    b.tearOff('n-b', nowSeconds() + 1);
    await pumpEventQueue();

    net.release();
    await pumpEventQueue();
    expect(a.ids, isEmpty);
    expect(a.pendingIds, ['carry', 'drop'], reason: 'Each unfinished task waits once');
    expectSameNotes(a, b);
    expect(buildHistory(a).notes, hasLength(1),
        reason: 'History shows yesterday\'s note once, not once per device that tore it off');

    await first.close();
    await second.close();
  }, skip: 'Known bug: each device keeps the note under its own id, so History shows it twice');

  test('an unfinished task carried on both devices while apart is written once', () async {
    final a = newDocument();
    writeYesterdaysNote(a);
    final b = newDocument();
    final (first, second, net) = await twoDevices(a, b);
    a.tearOff('n1', nowSeconds());
    await pumpEventQueue();
    expect(b.pendingIds, ['carry', 'drop']);

    net.hold = true;
    a.carry('carry', 'carried-a', 0);
    b.carry('carry', 'carried-b', 0);
    await pumpEventQueue();

    net.release();
    await pumpEventQueue();
    expectSameNotes(a, b);
    expect([for (final t in a.tasks()) t.name], ['Call the bank'],
        reason: 'The same task carried on two devices is on today\'s note once');

    await first.close();
    await second.close();
  }, skip: 'Known bug: each device writes its own copy, so the task is on today\'s note twice');

  group('The app on two devices', () {
    /// A laptop with yesterday's note and a phone, paired, each with its own saved document and
    /// peer id. The phone was in use yesterday too, with the same note, unless [freshPhone].
    Future<(TasksBloc, TasksBloc, List<SyncCubit>)> twoApps({bool freshPhone = false}) async {
      final relay = FakeRelay();
      final net = FakeNetwork();
      final yesterdays = TaskDocument(CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks'));
      writeYesterdaysNote(yesterdays);
      Future<(TasksBloc, SyncCubit)> device({TaskDocument? saved}) async {
        SharedPreferences.setMockInitialValues({
          'peerId': PeerId.generate().toString(),
          if (saved != null) 'taskDocument': saved.encodeChanges(),
        });
        final bloc = TasksBloc()..add(LoadStateEvent());
        await bloc.document;
        await pumpEventQueue();
        final sync =
            SyncCubit(connect: relay.connect, transport: net.create, document: bloc.document);
        await sync.load();
        return (bloc, sync);
      }

      final (laptop, laptopSync) = await device(saved: yesterdays);
      expect(laptop.state.needsTearOff(), isTrue);
      await laptopSync.createGroup();
      await laptopSync.setLive(true);
      final (phone, phoneSync) = await device(saved: freshPhone ? null : yesterdays);
      await phoneSync.joinGroup(laptopSync.state.code!);
      await phoneSync.setLive(true);
      await pumpEventQueue();
      await pumpEventQueue();
      return (laptop, phone, [laptopSync, phoneSync]);
    }

    Future<void> closeAll(List<TasksBloc> blocs, List<SyncCubit> syncs) async {
      for (final s in syncs) {
        await s.close();
      }
      for (final b in blocs) {
        await b.close();
      }
    }

    test('the phone leaves the tear-off view once the laptop tears the note off', () async {
      final (laptop, phone, syncs) = await twoApps();
      expect(phone.state.tasks.map((t) => t.name), ['Write report', 'Call the bank', 'Buy milk']);
      expect(phone.state.needsTearOff(), isTrue);

      laptop.add(TearOffNoteEvent());
      await pumpEventQueue();
      await pumpEventQueue();

      expect(laptop.state.needsTearOff(), isFalse);
      expect(phone.state.needsTearOff(), isFalse,
          reason: 'The phone shows today\'s note, not yesterday\'s to tear off again');
      expect(phone.state.tasks, isEmpty);
      expect(phone.state.pending.map((t) => t.name), ['Call the bank', 'Buy milk']);
      expect(buildHistory(phone.taskDocument!).notes, hasLength(1));

      // The phone carries one; the laptop's note shows it, and its pending list shrinks.
      phone.add(CarryTaskEvent(id: 'carry'));
      await pumpEventQueue();
      await pumpEventQueue();
      expect(laptop.state.tasks.map((t) => t.name), ['Call the bank']);
      expect(laptop.state.pending.map((t) => t.name), ['Buy milk']);
      await closeAll([laptop, phone], syncs);
    });

    test('a new device joining doesn\'t move the start of a note it never had', () async {
      final (laptop, phone, syncs) = await twoApps(freshPhone: true);
      expect(phone.state.tasks.map((t) => t.name), ['Write report', 'Call the bank', 'Buy milk']);
      expect(laptop.state.needsTearOff(), isTrue,
          reason: 'Yesterday\'s note still needs tearing off on the laptop');
      expect(phone.state.needsTearOff(), isTrue);
      await closeAll([laptop, phone], syncs);
    },
        skip:
            'Known bug: a fresh install writes current/startedAt as it loads, and that later write '
            'wins, so every device skips tearing off yesterday\'s note');
  });
}
