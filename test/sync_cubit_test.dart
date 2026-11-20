import 'dart:async';
import 'dart:io';

import 'package:bringmeback/sync/signalling.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:bringmeback/sync/sync_log.dart';
import 'package:bringmeback/sync/sync_status.dart';
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

  test('announces on events, not every round, and again at once after Sync now', () async {
    // 2026-11-18: relay.damus.io answered "rate-limited: you are noting too much" to a desktop that
    // announced itself every 30 s while alone.
    const tick = Duration(milliseconds: 50);
    final relay = FakeRelay();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: FakeNetwork().create, autoSyncEvery: tick);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    await pumpEventQueue();
    final atStart = relay.published.length;

    // Alone for 40 rounds: once more on the first round, then one safety announce after 20.
    await Future<void>.delayed(tick * 40 + tick ~/ 2);
    // Each announce goes to the 3 default relays, all played by the fake relay here.
    final announced = (relay.published.length - atStart) ~/ 3;
    expect(announced, inInclusiveRange(2, 3));

    // Sync now looks again at once: it reconnects, which announces, and once more next round.
    final before = relay.published.length;
    expect(await a.syncNow(), SyncNowResult.looking);
    await pumpEventQueue();
    final restarted = relay.published.length;
    expect(restarted - before, 6, reason: 'A bye from the old session, an announce from the new');
    await Future<void>.delayed(tick * 2 + tick ~/ 2);
    expect(relay.published.length - restarted, 3, reason: 'And once more on the next round');
    await a.close();
  });

  test('a computer that wakes from sleep reconnects and announces at once', () async {
    // While the computer sleeps, timers don't run and relay sockets die without a close. The first
    // round after waking comes far later than due.
    const tick = Duration(milliseconds: 50);
    final relay = FakeRelay();
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: relay.connect, transport: FakeNetwork().create, autoSyncEvery: tick);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    await Future<void>.delayed(tick * 3);
    final connections = relay.connections.length;
    for (final c in relay.connections) {
      c.dead = true;
    }
    final before = relay.published.length;

    sleep(tick * 5);
    await Future<void>.delayed(tick + tick ~/ 2);
    await pumpEventQueue();
    expect(relay.connections.length, connections + 3, reason: 'New sockets to each relay');
    expect(relay.published.length - before, greaterThanOrEqualTo(3), reason: 'Announced on them');
    await a.close();
  });

  test('D3.7 a relay that was unreachable doesn\'t stop the reconnect after a network change',
      () async {
    // Reproduces 2026-11-20: the desktop couldn't reach nos.lol. After a reconnect (wake, network
    // back, back to the front) it stayed off the relays until reloaded, still listing the other two
    // as connected, while the phone said "No other device online".
    const tick = Duration(seconds: 30);
    final relay = FakeRelay();
    final down = FakeRelay()..reachable = false;
    final net = FakeNetwork();
    RelayConnection desktopRelays(Uri url) =>
        url.host == 'nos.lol' ? down.connect(url) : relay.connect(url);
    SharedPreferences.setMockInitialValues({});
    final a = SyncCubit(connect: desktopRelays, transport: net.create, autoSyncEvery: tick);
    await a.load();
    await a.createGroup();
    await a.setLive(true);
    await pumpEventQueue();
    expect(a.state.relaysUp, 2);

    // The desktop's sockets die without a close, then its network comes back.
    for (final c in relay.connections) {
      c.dead = true;
    }
    final before = relay.connections.length;
    unawaited(a.networkChanged());
    await pumpEventQueue();
    expect(relay.connections.length, before + 2, reason: 'New sockets to the reachable relays');
    // The Devices page says where sync is, and the log says what happened.
    expect(syncStep(a.state), startsWith('3/5 Waiting for another device'));
    final log = SyncLog.instance.lines.join('\n');
    expect(log, contains('restart signalling: network back'));
    expect(log, contains('relay nos.lol: connect failed'));

    // The phone opens now, and the two find each other.
    SharedPreferences.setMockInitialValues({});
    final b = SyncCubit(connect: relay.connect, transport: net.create, autoSyncEvery: tick);
    await b.load();
    await b.joinGroup(a.state.code!);
    await b.setLive(true);
    await pumpEventQueue();
    expect(a.state.connected, {b.state.device!.id});
    expect(b.state.connected, {a.state.device!.id});
    await a.close();
    await b.close();
  });

  test('a device whose network comes back reconnects and finds the other at once', () async {
    const tick = Duration(seconds: 30);
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

    // A's network goes away: its sockets and its link die without a close or a bye.
    // A connected first: its sockets are the first three.
    for (final c in relay.connections.take(3)) {
      c.dead = true;
    }
    // Then it comes back, long before any round would notice.
    await a.networkChanged();
    await pumpEventQueue();
    expect(a.state.online, {bId});
    expect(a.state.connected, {bId});
    await a.close();
    await b.close();
  });
}
