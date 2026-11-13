import 'dart:convert';

import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/sync/pairing.dart';
import 'package:bringmeback/sync/peer.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';

void main() {
  setUpAll(loadSymbolonForTests);

  group('Reorder', () {
    Uint8List m(int seq, int byte) => Reorder.frame(seq, Uint8List.fromList([byte]));

    test('passes messages on in the order they were sent', () {
      final r = Reorder(8);
      expect(r.take(m(1, 11)), isEmpty);
      expect(r.take(m(2, 12)), isEmpty);
      expect([for (final x in r.take(m(0, 10))!) x.single], [10, 11, 12]);
      expect([for (final x in r.take(m(3, 13))!) x.single], [13]);
    });

    test('a repeated, too short or too far ahead message is refused', () {
      final r = Reorder(4);
      expect(r.take(m(1, 1)), isEmpty);
      expect(r.take(m(1, 1)), isNull);
      expect(r.take(Uint8List(3)), isNull);
      expect(Reorder(4).take(m(4, 1)), isNull);
      // A message already passed on can't come again.
      final s = Reorder(4)..take(m(0, 1));
      expect(s.take(m(0, 1)), isNull);
    });
  });

  group('versions', () {
    Future<PeerLink> responder(FakeNetwork net) async => PeerLink(
        remoteDevice: DeviceIdentity.generate().publicKey,
        remoteSession: Uint8List(16),
        initiator: false,
        transport: await net.create(),
        device: DeviceIdentity.generate(),
        keys: PairingCode.generate().deriveKeys(),
        prologue: utf8.encode('p'),
        signal: (kind, body) => fail('Must not answer another version'));

    SymbolonSignal offer(List<int> body) => SymbolonSignal(
        kind: SignalKind.offer,
        createdAt: 0,
        from: Uint8List(16),
        to: Uint8List(16),
        device: Uint8List(32),
        body: body);

    test('an offer from before versions (bare SDP) is refused as an older version', () async {
      final link = await responder(FakeNetwork());
      await link.signalled(offer(utf8.encode('v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\n')));
      expect(link.isClosed, isTrue);
      expect(link.failure, LinkFailure.version);
      expect(link.remoteProtocol, 1);
      final problem = SyncProblem(link.failure!, remoteProtocol: link.remoteProtocol);
      expect(problem.message, contains('older version'));
    });

    test('an offer from a newer version is refused and says to update this device', () async {
      final link = await responder(FakeNetwork());
      await link.signalled(offer(utf8.encode(jsonEncode({'v': syncProtocol + 1, 'x': 1}))));
      expect(link.failure, LinkFailure.version);
      expect(link.remoteProtocol, syncProtocol + 1);
      expect(SyncProblem(LinkFailure.version, remoteProtocol: syncProtocol + 1).message,
          contains('Update this device'));
    });

    test('an offer that is neither is a protocol failure', () async {
      final link = await responder(FakeNetwork());
      await link.signalled(offer(utf8.encode('{"no": "version"}')));
      expect(link.failure, LinkFailure.protocol);
    });
  });

  Future<(SyncCubit, SyncCubit, FakeNetwork)> twoDevices({Duration? staleAfter}) async {
    final relay = FakeRelay();
    final net = FakeNetwork();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: net.create);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    SharedPreferences.setMockInitialValues({});
    final b = SyncCubit(
        connect: relay.connect,
        transport: net.create,
        staleAfter: staleAfter ?? const Duration(seconds: 20));
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();
    return (a, b, net);
  }

  test('a dropped link shows as a problem until it connects again', () async {
    final (a, b, net) = await twoDevices();
    expect(a.state.connected, {b.state.device!.id});
    expect(a.state.relayCount, greaterThan(0));
    expect(a.state.relaysUp, a.state.relayCount);
    await net.transports.first.close();
    await pumpEventQueue();
    final problem = a.state.problems[b.state.device!.id]!;
    expect(problem.failure, LinkFailure.transport);
    expect(problem.wasConnected, isTrue);
    await Future<void>.delayed(const Duration(seconds: 6));
    await pumpEventQueue();
    expect(a.state.connected, {b.state.device!.id});
    expect(a.state.problems, isEmpty);
    await a.close();
    await b.close();
  });

  test('no relay reachable is reported after the grace period', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: (_) => throw StateError('offline'), transport: FakeNetwork().create);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    expect(a.state.relaysUnreachable, isFalse);
    await Future<void>.delayed(SyncCubit.relayGrace + const Duration(milliseconds: 200));
    expect(a.state.relaysUnreachable, isTrue);
    await a.close();
  });

  test('coming back after a long break reconnects at once', () async {
    final (a, b, net) = await twoDevices(staleAfter: Duration.zero);
    expect(b.state.connected, {a.state.device!.id});
    final before = net.transports.length;
    // A short break with no hide before it does nothing.
    await b.resumed();
    expect(net.transports, hasLength(before));
    b.paused();
    await b.resumed();
    await pumpEventQueue();
    expect(net.transports.length, greaterThan(before));
    expect(b.state.connected, {a.state.device!.id});
    expect(a.state.connected, {b.state.device!.id});
    await a.close();
    await b.close();
  });

  group('joining with a clean slate', () {
    test('clears the tasks first, then joins and syncs the new document', () async {
      SharedPreferences.setMockInitialValues({});
      final a = SyncCubit(transport: FakeNetwork().create, connect: FakeRelay().connect);
      await a.load();
      await a.createGroup();
      SharedPreferences.setMockInitialValues({});
      final b = SyncCubit(transport: FakeNetwork().create, connect: FakeRelay().connect);
      await b.load();
      var cleared = 0;
      Future<CRDTDocument> clear() async {
        cleared++;
        expect(b.state.paired, isFalse, reason: 'Cleared before joining');
        return CRDTDocument(peerId: PeerId.generate());
      }

      await expectLater(b.joinGroup('bmb1-nope', clearFirst: clear), throwsFormatException);
      expect(cleared, 0, reason: 'A bad code changes nothing');
      await b.joinGroup(a.state.code!, clearFirst: clear);
      expect(cleared, 1);
      expect(b.state.paired, isTrue);
      await a.close();
      await b.close();
    });

    test('clearAll deletes every task and starts a new document', () async {
      SharedPreferences.setMockInitialValues({});
      final bloc = TasksBloc();
      final first = await bloc.document;
      bloc.add(InsertTaskEvent(index: 0, name: 'Junk', id: const ValueKey('junk')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.tasks.map((t) => t.name), contains('Junk'));
      final prefs = await SharedPreferences.getInstance();
      final peerBefore = prefs.getString('peerId');
      final second = await bloc.clearAll();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.tasks, isEmpty);
      expect(identical(first, second), isFalse);
      expect(prefs.getString('peerId'), isNot(peerBefore));
      expect(prefs.getString('taskDocument'), isNot(contains('Junk')));
      await bloc.close();
    });
  });
}
