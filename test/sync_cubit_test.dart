import 'package:bringmeback/sync/signalling.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';


/// Connects through [relay] until [vanish], after which this device's connections are dead and it
/// can't reconnect: a phone frozen in the background, without a bye.
class _Vanishing {
  final FakeRelay relay;
  final mine = <FakeConnection>[];
  bool gone = false;
  _Vanishing(this.relay);

  RelayConnection connect(Uri url) {
    if (gone) throw StateError('frozen');
    final c = relay.connect(url) as FakeConnection;
    mine.add(c);
    return c;
  }

  void vanish() {
    gone = true;
    for (final c in mine) {
      c.dead = true;
    }
  }
}

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
    final bRelay = _Vanishing(relay);
    final b = SyncCubit(
        connect: bRelay.connect,
        transport: () => Future.error(StateError('no WebRTC')),
        autoSyncEvery: tick);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();
    expect(a.state.online, {b.state.device!.id});

    // While B is there, it keeps announcing, so A keeps it online.
    await Future<void>.delayed(tick * 14);
    expect(a.state.online, {b.state.device!.id});

    // B vanishes without a bye.
    bRelay.vanish();
    await Future<void>.delayed(tick * 16);
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
    final bRelay = _Vanishing(relay);
    final b = SyncCubit(connect: bRelay.connect, transport: net.create, autoSyncEvery: tick);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();
    final bId = b.state.device!.id;
    expect(a.state.connected, {bId});

    // B is frozen: its link drops and it falls silent on the relay, without a bye.
    bRelay.vanish();
    for (final t in net.transports) {
      await t.close();
    }
    await pumpEventQueue();
    expect(a.state.problems.keys, contains(bId));

    await Future<void>.delayed(tick * 16);
    await pumpEventQueue();
    expect(a.state.online, isEmpty);
    expect(a.state.problems, isEmpty);
    await a.close();
    await b.close();
  });

  test('announces back off while no device answers, and come quickly again after Sync now',
      () async {
    const tick = Duration(milliseconds: 50);
    final relay = FakeRelay();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: FakeNetwork().create, autoSyncEvery: tick);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    await pumpEventQueue();
    final atStart = relay.published.length;

    // Alone for 40 rounds: announces after 1, 2, 4, 8, 10, 10 and 10 rounds, not 40 times.
    await Future<void>.delayed(tick * 40 + tick ~/ 2);
    // Each announce goes to the 3 default relays, all played by the fake relay here.
    final announced = (relay.published.length - atStart) ~/ 3;
    expect(announced, inInclusiveRange(5, 7));

    // Sync now looks again at once and starts over from a short gap.
    final before = relay.published.length;
    expect(await a.syncNow(), SyncNowResult.looking);
    await pumpEventQueue();
    await Future<void>.delayed(tick * 2 + tick ~/ 2);
    expect(relay.published.length - before, greaterThanOrEqualTo(2),
        reason: 'The announce on reconnecting, and one on the next round');
    await a.close();
  });
}
