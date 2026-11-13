import 'dart:typed_data';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';

TaskDocument newDocument() =>
    TaskDocument(CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks'));

/// Two paired devices with live sync on, each with its own task document.
Future<(SyncCubit, SyncCubit, FakeNetwork)> twoDevices(TaskDocument a, TaskDocument b) async {
  final relay = FakeRelay();
  final net = FakeNetwork();
  SharedPreferences.setMockInitialValues({});
  final first =
      SyncCubit(connect: relay.connect, transport: net.create, document: Future.value(a.doc));
  await first.load();
  await first.createGroup();
  await first.setLive(true);
  SharedPreferences.setMockInitialValues({});
  final second =
      SyncCubit(connect: relay.connect, transport: net.create, document: Future.value(b.doc));
  await second.load();
  await second.joinGroup(first.state.code!);
  await second.setLive(true);
  await pumpEventQueue();
  return (first, second, net);
}

void main() {
  setUpAll(loadSymbolonForTests);

  test('connected devices exchange what the other is missing, then every new change', () async {
    final a = newDocument()..insert(0, 'a1', name: 'Written on A');
    final b = newDocument()..insert(0, 'b1', name: 'Written on B');
    final (first, second, _) = await twoDevices(a, b);
    expect(first.state.connected, hasLength(1));

    expect(a.ids.toSet(), {'a1', 'b1'});
    expect(b.ids, a.ids);
    expect(b.task('a1').name, 'Written on A');

    a.setName('b1', 'Renamed on A');
    b.insert(0, 'b2', name: 'Live from B');
    await pumpEventQueue();
    expect(b.task('b1').name, 'Renamed on A');
    expect(a.ids, b.ids);
    expect(a.task('b2').name, 'Live from B');

    await first.close();
    await second.close();
  });

  test('each device knows whether the other has caught up', () async {
    final a = newDocument()..insert(0, 'a1', name: 'Written on A');
    final b = newDocument();
    final (first, second, net) = await twoDevices(a, b);
    final bId = second.state.device!.id;
    final aId = first.state.device!.id;
    expect(first.state.inSync, {bId});
    expect(second.state.inSync, {aId});
    expect(first.state.allInSync, isTrue);
    expect(first.state.lastSynced, isNotNull);

    // A change on A takes B out of sync on both sides until it has arrived and B has said so.
    net.hold = true;
    a.setName('a1', 'Renamed on A');
    await pumpEventQueue();
    expect(first.state.inSync, isEmpty);
    expect(first.state.allInSync, isFalse);
    net.release();
    await pumpEventQueue();
    expect(b.task('a1').name, 'Renamed on A');
    expect(first.state.inSync, {bId});
    expect(second.state.inSync, {aId});

    // A dropped link is no longer in sync, but the last time it was stays.
    await second.close();
    await pumpEventQueue();
    expect(first.state.inSync, isEmpty);
    expect(first.state.lastSynced, isNotNull);
    await first.close();
  });

  test('messages bigger than one channel message arrive whole', () async {
    final a = newDocument();
    for (var i = 0; i < 200; i++) {
      a.insert(i, 't$i', name: 'x' * 2000);
    }
    final b = newDocument();
    final (first, second, _) = await twoDevices(a, b);
    expect(b.ids, hasLength(200));
    expect(b.task('t199').name, 'x' * 2000);
    // And one change bigger than a channel message, live.
    a.setName('t0', 'y' * 100000);
    await pumpEventQueue();
    expect(b.task('t0').name, 'y' * 100000);
    await first.close();
    await second.close();
  });

  test('a device that sends garbage loses its link and changes nothing', () async {
    final a = newDocument()..insert(0, 'a1', name: 'Mine');
    final b = newDocument();
    final (first, second, net) = await twoDevices(a, b);
    // Play a compromised device: tamper with what the second device's link encrypts.
    final bLink = second.linkForTests(first.state.device!.id)!;
    bLink.send(Uint8List.fromList([0, 9, 1, 2, 3]));
    await pumpEventQueue();
    expect(first.state.connected, isEmpty);
    expect(a.ids, ['a1']);
    expect(net.transports.where((t) => !t.closed), isEmpty);
    await first.close();
    await second.close();
  });

  test('fields of the wrong type, which only a bad device could write, read as defaults', () {
    final tasks = newDocument()..insert(0, 't', name: 'ok');
    // The bad device has seen the task, so its writes come after it.
    final bad = CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks')
      ..importChanges(tasks.doc.exportChanges());
    final fields = CRDTMapHandler<Object?>(bad, 'fields', handlerType: 'bmb.fields');
    fields
      ..set('t/name', 42)
      ..set('t/timerLength', 'long')
      ..set('t/e/notanumber', 5)
      ..set('t/e/100', 'end');
    expect(fields.value['t/name'], 42);
    tasks.doc.importChanges(bad.exportChanges());
    final t = tasks.task('t');
    expect(t.name, '');
    expect(t.timerLengthSeconds, 20 * 60);
    expect(t.entries.where((e) => e.start == 100), isEmpty);
  });
}
