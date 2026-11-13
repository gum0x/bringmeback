import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'doc_sync_test.dart' show newDocument, twoDevices;
import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';

/// What happens when devices that are out of sync are asked to sync, more than once, and when both
/// change the same task while apart. docs/SYNC.md describes the same cases.
void main() {
  setUpAll(loadSymbolonForTests);

  /// Both devices have the same tasks, the same changes, and know it.
  void expectSame(TaskDocument a, TaskDocument b, SyncCubit first, SyncCubit second) {
    expect(b.ids, a.ids);
    for (final id in a.ids) {
      expect(b.task(id).name, a.task(id).name, reason: id);
      expect(b.task(id).doneAt, a.task(id).doneAt, reason: id);
    }
    expect(b.doc.exportChanges().length, a.doc.exportChanges().length,
        reason: 'No change is lost, and none is applied twice');
    expect(first.state.inSync, {second.state.device!.id});
    expect(second.state.inSync, {first.state.device!.id});
  }

  group('Two resyncs while the devices are out of sync', () {
    test('with the link up but messages held back: both resyncs are applied once', () async {
      final a = newDocument()..insert(0, 't1', name: 'Shared');
      final b = newDocument();
      final (first, second, net) = await twoDevices(a, b);
      expect(b.ids, ['t1']);

      // Messages stop getting through, as on a congested network: the devices drift apart.
      net.hold = true;
      a.insert(1, 'a2', name: 'Written on A');
      b.insert(1, 'b2', name: 'Written on B');
      b.setName('t1', 'Renamed on B');
      await pumpEventQueue();
      expect(first.state.allInSync, isFalse);

      // Sync now, twice on each device, while nothing gets through.
      expect(await first.syncNow(), SyncNowResult.syncing);
      expect(await first.syncNow(), SyncNowResult.syncing);
      expect(await second.syncNow(), SyncNowResult.syncing);
      expect(await second.syncNow(), SyncNowResult.syncing);
      await pumpEventQueue();
      expect(a.ids, ['t1', 'a2'], reason: 'Nothing arrives while held');

      // The network recovers: the live changes and all four resyncs arrive, duplicates included.
      net.release();
      await pumpEventQueue();
      expect(a.ids.toSet(), {'t1', 'a2', 'b2'});
      expect(a.ids.where((id) => id == 'b2'), hasLength(1), reason: 'Not inserted twice');
      expect(a.task('t1').name, 'Renamed on B');
      expectSame(a, b, first, second);

      // And another resync on the synced devices changes nothing.
      final changes = a.doc.exportChanges().length;
      await first.syncNow();
      await second.syncNow();
      await pumpEventQueue();
      expect(a.doc.exportChanges(), hasLength(changes));
      expectSame(a, b, first, second);
      await first.close();
      await second.close();
    });

    test('with the link down: Sync now reconnects at once, and a second press does no harm',
        () async {
      final a = newDocument()..insert(0, 't1', name: 'Shared');
      final b = newDocument();
      final (first, second, net) = await twoDevices(a, b);

      // The link drops while both stay online; each device writes on its own.
      await net.transports.first.close();
      await pumpEventQueue();
      expect(first.state.connected, isEmpty);
      expect(first.state.online, {second.state.device!.id});
      a.insert(1, 'a2', name: 'Written on A');
      a.setName('t1', 'Renamed on A');
      b.insert(1, 'b2', name: 'Written on B');

      // Without Sync now the next try is 5 s away. Two presses on each device, straight away.
      final presses = await Future.wait(
          [first.syncNow(), first.syncNow(), second.syncNow(), second.syncNow()]);
      expect(presses, everyElement(SyncNowResult.connecting));
      await pumpEventQueue();
      expect(first.state.connected, {second.state.device!.id});
      expect(second.state.connected, {first.state.device!.id});
      expect(net.transports.where((t) => !t.closed), hasLength(2),
          reason: 'One new link, not one per press');

      expect(a.ids.toSet(), {'t1', 'a2', 'b2'});
      expect(b.task('t1').name, 'Renamed on A');
      expectSame(a, b, first, second);
      await first.close();
      await second.close();
    });

    test('a change reaches a device through another one when the two can\'t connect', () async {
      // A is linked to B and to C, but B and C can't reach each other.
      final relay = FakeRelay();
      final net = FakeNetwork()..blocked.add(('B', 'C'));
      final docs = [for (var i = 0; i < 3; i++) newDocument()];
      final cubits = <SyncCubit>[];
      for (final (i, name) in ['A', 'B', 'C'].indexed) {
        SharedPreferences.setMockInitialValues({});
        final cubit = SyncCubit(
            connect: relay.connect,
            transport: () => net.createFor(name),
            document: Future.value(docs[i].doc));
        await cubit.load();
        if (i == 0) {
          await cubit.createGroup();
        } else {
          await cubit.joinGroup(cubits.first.state.code!);
        }
        await cubit.setLive(true);
        await pumpEventQueue();
        cubits.add(cubit);
      }
      final [a, b, c] = docs;
      final [first, second, third] = cubits;
      expect(first.state.connected, hasLength(2));
      expect(second.state.connected, {first.state.device!.id});
      expect(third.state.connected, {first.state.device!.id});

      c.insert(0, 'c1', name: 'Written on C');
      await pumpEventQueue();
      expect(a.ids, ['c1']);
      expect(b.ids, ['c1'], reason: 'A passes on what it got from C');
      b.setName('c1', 'Renamed on B');
      await pumpEventQueue();
      expect(c.task('c1').name, 'Renamed on B');
      for (final cubit in cubits) {
        await cubit.close();
      }
    });

    test('devices that missed each other\'s announce still find each other and sync', () async {
      final relay = FakeRelay();
      final net = FakeNetwork();
      final a = newDocument()..insert(0, 'a1', name: 'Written on A');
      final b = newDocument()..insert(0, 'b1', name: 'Written on B');
      SharedPreferences.setMockInitialValues({});
      final first = SyncCubit(
          connect: relay.connect,
          transport: net.create,
          document: Future.value(a.doc),
          autoSyncEvery: const Duration(milliseconds: 200));
      await first.load();
      await first.createGroup();
      await first.setLive(true);
      await pumpEventQueue();
      // The relay drops B's announce: neither device knows the other is online.
      relay.deaf = true;
      SharedPreferences.setMockInitialValues({});
      final second = SyncCubit(
          connect: relay.connect,
          transport: net.create,
          document: Future.value(b.doc),
          autoSyncEvery: const Duration(milliseconds: 200));
      await second.load();
      await second.joinGroup(first.state.code!);
      await second.setLive(true);
      await pumpEventQueue();
      relay.deaf = false;
      expect(first.state.online, isEmpty);
      expect(second.state.online, isEmpty);

      // Nobody presses anything.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await pumpEventQueue();
      expect(first.state.connected, {second.state.device!.id});
      expect(a.ids.toSet(), {'a1', 'b1'});
      expectSame(a, b, first, second);
      await first.close();
      await second.close();
    });
  });

  test('Sync now with sync off does nothing, and with nobody online looks again', () async {
    final relay = FakeRelay();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: FakeNetwork().create);
    await a.load();
    expect(await a.syncNow(), SyncNowResult.off, reason: 'Not in a group');
    await a.createGroup();
    expect(await a.syncNow(), SyncNowResult.off, reason: 'Find my devices online is off');
    expect(relay.published, isEmpty);
    await a.setLive(true);
    await pumpEventQueue();
    final sent = relay.published.length;
    expect(await a.syncNow(), SyncNowResult.looking);
    await pumpEventQueue();
    expect(relay.published.length, greaterThan(sent), reason: 'Announced again');
    await a.close();
  });

  group('Closing the same task on two linked devices that are out of sync', () {
    /// A device: its task list, and sync for its document.
    Future<(TasksBloc, SyncCubit)> device(FakeRelay relay, FakeNetwork net, {String? code}) async {
      SharedPreferences.setMockInitialValues({});
      final tasks = TasksBloc();
      final doc = await tasks.document;
      final sync = SyncCubit(connect: relay.connect, transport: net.create, document: Future.value(doc));
      await sync.load();
      if (code == null) {
        await sync.createGroup();
      } else {
        await sync.joinGroup(code);
      }
      await sync.setLive(true);
      await pumpEventQueue();
      return (tasks, sync);
    }

    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();
    }

    TaskState byId(TasksBloc bloc, String id) =>
        bloc.state.tasks.firstWhere((t) => t.id.value == id);

    for (final apart in ['link down', 'messages held back']) {
      test('($apart) the task is done once, and the next one has one timer running', () async {
        final relay = FakeRelay();
        final net = FakeNetwork();
        final (tasksA, syncA) = await device(relay, net);
        final (tasksB, syncB) = await device(relay, net, code: syncA.state.code);
        await settle();
        expect(syncA.state.connected, hasLength(1));

        // On A: two tasks, the first one running.
        tasksA.add(AddTaskOnTopEvent(name: 'Second', id: const ValueKey('t2')));
        await settle();
        tasksA.add(AddTaskOnTopEvent(name: 'First', id: const ValueKey('t1')));
        await settle();
        expect(tasksB.state.tasks.map((t) => t.name), ['First', 'Second']);
        expect(byId(tasksB, 't1').running, isTrue);

        // The devices get out of sync.
        if (apart == 'link down') {
          await syncB.setLive(false);
        } else {
          net.hold = true;
        }
        await settle();

        // Both check off "First", a second apart, each without seeing the other's.
        tasksA.add(SetDoneEvent(index: 0, done: true));
        await settle();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        tasksB.add(SetDoneEvent(index: 0, done: true));
        await settle();
        expect(byId(tasksA, 't1').doneAt, isNot(byId(tasksB, 't1').doneAt));
        expect(byId(tasksA, 't2').running, isTrue);
        expect(byId(tasksB, 't2').running, isTrue);

        // Back in sync.
        if (apart == 'link down') {
          await syncB.setLive(true);
        } else {
          net.release();
        }
        await settle();
        await syncA.syncNow();
        await settle();

        for (final bloc in [tasksA, tasksB]) {
          final first = byId(bloc, 't1');
          final second = byId(bloc, 't2');
          expect(bloc.state.tasks.map((t) => t.name), ['First', 'Second'], reason: 'No duplicate');
          expect(first.done, isTrue);
          expect(first.running, isFalse);
          expect(first.entries.where((e) => e.end == null), isEmpty);
          // The later check-off wins on both devices.
          expect(first.doneAt, byId(tasksB, 't1').doneAt);
          // Each device started "Second" when it checked off "First". Only one may count.
          expect(second.running, isTrue);
          expect(second.entries.where((e) => e.end == null), hasLength(1),
              reason: 'Two open time entries would count the time twice');
        }
        List<(int, int?)> entries(TasksBloc bloc) =>
            [for (final e in byId(bloc, 't2').entries) (e.start, e.end)];
        expect(entries(tasksA), entries(tasksB));

        await syncA.close();
        await syncB.close();
        await tasksA.close();
        await tasksB.close();
      });
    }

    test('one device checks it off, the other writes a new task on top: only the new one runs',
        () async {
      final relay = FakeRelay();
      final net = FakeNetwork();
      final (tasksA, syncA) = await device(relay, net);
      final (tasksB, syncB) = await device(relay, net, code: syncA.state.code);
      await settle();
      tasksA.add(AddTaskOnTopEvent(name: 'Second', id: const ValueKey('t2')));
      await settle();
      tasksA.add(AddTaskOnTopEvent(name: 'First', id: const ValueKey('t1')));
      await settle();
      expect(tasksB.state.tasks.map((t) => t.name), ['First', 'Second']);

      await syncB.setLive(false);
      await settle();
      // A checks off "First", which starts "Second" on A.
      tasksA.add(SetDoneEvent(index: 0, done: true));
      await settle();
      final secondStarted = byId(tasksA, 't2').entries.last.start;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      // B, a moment later, writes a new task on top, which stops "First" and starts "Urgent".
      tasksB.add(AddTaskOnTopEvent(name: 'Urgent', id: const ValueKey('t0')));
      await settle();
      final urgentStarted = byId(tasksB, 't0').entries.single.start;

      await syncB.setLive(true);
      await settle();
      await syncA.syncNow();
      await settle();
      for (final bloc in [tasksA, tasksB]) {
        expect(bloc.state.tasks.map((t) => t.name), ['Urgent', 'First', 'Second']);
        expect(byId(bloc, 't0').running, isTrue);
        expect(byId(bloc, 't1').done, isTrue);
        expect(byId(bloc, 't1').running, isFalse);
        expect(byId(bloc, 't2').running, isFalse, reason: 'Only the current task runs');
        // "Second" ran on A from when "First" was checked off until "Urgent" started on B.
        expect([for (final e in byId(bloc, 't2').entries) (e.start, e.end)],
            [(secondStarted, urgentStarted)]);
      }
      await syncA.close();
      await syncB.close();
      await tasksA.close();
      await tasksB.close();
    });
  });
}
