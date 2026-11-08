import 'dart:convert';
import 'dart:typed_data';

import 'package:bringmeback/sync/pairing.dart';
import 'package:bringmeback/sync/peer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'fake_transport.dart';
import 'symbolon_native.dart';

void main() {
  setUpAll(loadSymbolonForTests);

  final prologue = utf8.encode('bmb/v1 topic');

  /// Two linked devices; `signal` carries offers and answers between them directly.
  Future<(PeerLink, PeerLink)> pair(
    FakeNetwork net, {
    GroupKeys? responderKeys,
    DeviceIdentity? claimed,
    List<int>? responderPrologue,
  }) async {
    final keys = PairingCode.generate().deriveKeys();
    var a = DeviceIdentity.generate();
    var b = DeviceIdentity.generate();
    if (!symbolon.initiates(a.publicKey, b.publicKey)) (a, b) = (b, a);
    late PeerLink initiator, responder;
    SymbolonSignal signal(SignalKind kind, List<int> body, DeviceIdentity from) => SymbolonSignal(
        kind: kind,
        createdAt: 0,
        from: Uint8List(16)..[0] = 1,
        to: Uint8List(16)..[0] = 2,
        device: from.publicKey,
        body: body);
    initiator = PeerLink(
        remoteDevice: b.publicKey,
        remoteSession: Uint8List(16),
        initiator: true,
        transport: await net.create(),
        device: a,
        keys: keys,
        prologue: prologue,
        signal: (kind, body) => responder.signalled(signal(kind, body, a)));
    responder = PeerLink(
        // The responder only accepts the device the offer's signal named.
        remoteDevice: (claimed ?? a).publicKey,
        remoteSession: Uint8List(16),
        initiator: false,
        transport: await net.create(),
        device: b,
        keys: responderKeys ?? keys,
        prologue: responderPrologue ?? prologue,
        signal: (kind, body) => initiator.signalled(signal(kind, body, b)));
    await initiator.start();
    return (initiator, responder);
  }

  test('the devices connect and exchange encrypted messages both ways', () async {
    final net = FakeNetwork();
    final onTheWire = <Uint8List>[];
    net.onTheWay = (m) {
      onTheWire.add(m);
      return m;
    };
    final (a, b) = await pair(net);
    await Future.wait([a.connected, b.connected]);
    final aGot = <String>[];
    final bGot = <String>[];
    a.received.listen((m) => aGot.add(utf8.decode(m)));
    b.received.listen((m) => bGot.add(utf8.decode(m)));
    a.send(utf8.encode('hello'));
    a.send(utf8.encode('again'));
    b.send(utf8.encode('hi'));
    await pumpEventQueue();
    expect(bGot, ['hello', 'again']);
    expect(aGot, ['hi']);
    // Nothing goes over the channel in the clear.
    for (final m in onTheWire) {
      expect(utf8.decode(m, allowMalformed: true), isNot(contains('hello')));
    }
    await a.close();
    await pumpEventQueue();
    expect(b.isClosed, isTrue);
  });

  test('another group, another prologue or another device never connects', () async {
    final cases = <Future<(PeerLink, PeerLink)> Function(FakeNetwork)>[
      (n) async => pair(n, responderKeys: PairingCode.generate().deriveKeys()),
      (n) => pair(n, responderPrologue: utf8.encode('bmb/v1 other')),
      (n) => pair(n, claimed: DeviceIdentity.generate()),
    ];
    for (final make in cases) {
      final (a, b) = await make(FakeNetwork());
      await pumpEventQueue();
      expect(a.isConnected || b.isConnected, isFalse);
      expect(b.isClosed, isTrue);
      await expectLater(a.connected, throwsStateError);
    }
  });

  test('a tampered message closes the link', () async {
    final net = FakeNetwork();
    final (a, b) = await pair(net);
    await Future.wait([a.connected, b.connected]);
    net.onTheWay = (m) => Uint8List.fromList(m)..[m.length - 1] ^= 1;
    final got = <Uint8List>[];
    b.received.listen(got.add);
    a.send(utf8.encode('hello'));
    await pumpEventQueue();
    expect(got, isEmpty);
    expect(b.isClosed, isTrue);
    expect(a.isClosed, isTrue);
  });

  test('a link that never opens gives up', () async {
    final net = FakeNetwork();
    final link = PeerLink(
        remoteDevice: DeviceIdentity.generate().publicKey,
        remoteSession: Uint8List(16),
        initiator: true,
        transport: await net.create(),
        device: DeviceIdentity.generate(),
        keys: PairingCode.generate().deriveKeys(),
        prologue: prologue,
        signal: (kind, body) {},
        timeout: const Duration(milliseconds: 10));
    await link.start();
    await expectLater(link.connected, throwsStateError);
    expect(link.isClosed, isTrue);
    await pumpEventQueue();
    expect(net.transports.single.closed, isTrue);
  });
}
