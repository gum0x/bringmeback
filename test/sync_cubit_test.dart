import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';

void main() {
  setUpAll(loadSymbolonForTests);

  test('paired devices with live sync on see each other online, and not once one leaves', () async {
    SharedPreferences.setMockInitialValues({});
    final relay = FakeRelay();
    final a = SyncCubit(connect: relay.connect, transport: FakeNetwork().create);
    await a.load();
    await a.createGroup();
    // Off by default: nothing is sent to any relay.
    await pumpEventQueue();
    expect(relay.published, isEmpty);
    await a.setLive(true);
    await pumpEventQueue();

    // A second device, with its own stored state.
    SharedPreferences.setMockInitialValues({});
    final b = SyncCubit(connect: relay.connect, transport: FakeNetwork().create);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();

    expect(a.state.online, {b.state.device!.id});
    expect(b.state.online, {a.state.device!.id});
    // Each device answers the other's announce once, then it goes quiet.
    final sent = relay.published.length;
    await pumpEventQueue();
    expect(relay.published, hasLength(sent));

    await b.setLive(false);
    await pumpEventQueue();
    expect(a.state.online, isEmpty);
    await a.close();
    await b.close();
  });

  test('online devices connect directly, and reconnect after the link drops', () async {
    final relay = FakeRelay();
    final net = FakeNetwork();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: net.create);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    SharedPreferences.setMockInitialValues({});
    final b = SyncCubit(connect: relay.connect, transport: net.create);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();

    expect(a.state.connected, {b.state.device!.id});
    expect(b.state.connected, {a.state.device!.id});
    // One link: only one of the two made an offer.
    expect(net.transports, hasLength(2));

    // The channel drops; the initiator sets up a new link after a short wait.
    await net.transports.first.close();
    await pumpEventQueue();
    expect(a.state.connected, isEmpty);
    expect(b.state.connected, isEmpty);
    await Future<void>.delayed(const Duration(seconds: 6));
    await pumpEventQueue();
    expect(a.state.connected, {b.state.device!.id});
    expect(b.state.connected, {a.state.device!.id});

    await b.setLive(false);
    await pumpEventQueue();
    expect(a.state.connected, isEmpty);
    expect(a.state.online, isEmpty);
    await a.close();
    await b.close();
  });

  test('a device whose relay socket died silently is found again by a device that comes back',
      () async {
    // The desktop stays open while its relay socket dies without closing (the computer slept); the
    // phone goes to the background without a bye, then comes back with a new session.
    const tick = Duration(milliseconds: 200);
    final relay = FakeRelay();
    final net = FakeNetwork();
    SharedPreferences.setMockInitialValues({});
    final desktop =
        SyncCubit(connect: relay.connect, transport: net.create, autoSyncEvery: tick);
    await desktop.load();
    await desktop.createGroup();
    await desktop.setLive(true);
    SharedPreferences.setMockInitialValues({});
    final phone = SyncCubit(
        connect: relay.connect, transport: net.create, autoSyncEvery: tick, staleAfter: Duration.zero);
    await phone.load();
    await phone.joinGroup(desktop.state.code!);
    await phone.setLive(true);
    await pumpEventQueue();
    expect(phone.state.connected, {desktop.state.device!.id});

    // The phone is frozen in the background: its link dies, no bye is sent.
    phone.paused();
    for (final t in net.transports) {
      await t.close();
    }
    for (final c in relay.connections) {
      c.dead = true;
    }
    await pumpEventQueue();

    // The phone comes back: it reconnects to the relay with a new session and announces.
    await phone.resumed();
    await Future<void>.delayed(tick * 10);
    await pumpEventQueue();

    expect(phone.state.online, {desktop.state.device!.id});
    expect(phone.state.connected, {desktop.state.device!.id});
    expect(desktop.state.connected, {phone.state.device!.id});
    await phone.close();
    await desktop.close();
  });

  test('a device that left without a bye stops counting as online after a few rounds', () async {
    const tick = Duration(milliseconds: 100);
    final relay = FakeRelay();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: FakeNetwork().create, autoSyncEvery: tick);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    SharedPreferences.setMockInitialValues({});
    // B can't connect directly (no transport), so it is online but never connected.
    final b = SyncCubit(
        connect: relay.connect,
        transport: () => Future.error(StateError('no WebRTC')),
        autoSyncEvery: tick);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();
    expect(a.state.online, {b.state.device!.id});

    // While B is there, it keeps announcing, so A keeps it online.
    await Future<void>.delayed(tick * 6);
    expect(a.state.online, {b.state.device!.id});

    // B vanishes without a bye.
    for (final c in relay.connections) {
      if (c != relay.connections.first) c.dead = true;
    }
    await Future<void>.delayed(tick * 6);
    await pumpEventQueue();
    expect(a.state.online, isEmpty);
    expect(a.state.problems, isEmpty, reason: 'No warning left for a device that is gone');
    await a.close();
    await b.close();
  });

  test('a device that lost its link and then left stops showing as not syncing', () async {
    // 2026-11-18: the phone said "Device … isn't syncing" next to "No other device online".
    const tick = Duration(milliseconds: 100);
    final relay = FakeRelay();
    final net = FakeNetwork();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: net.create, autoSyncEvery: tick);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    SharedPreferences.setMockInitialValues({});
    final b = SyncCubit(connect: relay.connect, transport: net.create, autoSyncEvery: tick);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();
    final bId = b.state.device!.id;
    expect(a.state.connected, {bId});

    // B is frozen: its link drops and it falls silent on the relay, without a bye.
    for (final c in relay.connections.skip(1)) {
      c.dead = true;
    }
    for (final t in net.transports) {
      await t.close();
    }
    await pumpEventQueue();
    expect(a.state.problems.keys, contains(bId));

    await Future<void>.delayed(tick * 6);
    await pumpEventQueue();
    expect(a.state.online, isEmpty);
    expect(a.state.problems, isEmpty);
    await a.close();
    await b.close();
  });
}
