import 'dart:convert';
import 'dart:typed_data';

import 'package:bringmeback/sync/signalling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'fake_relay.dart';
import 'symbolon_native.dart';

void main() {
  setUpAll(loadSymbolonForTests);

  final secret = List.generate(32, (i) => i);
  SymbolonGroupKeys group(String context) => symbolon.groupKeys(utf8.encode(context), secret);
  Uint8List device() => symbolon.generateDeviceKey().publicKey;
  final relays = [Uri.parse('wss://relay.test')];

  Signalling node(FakeRelay relay, {String context = 'bringmeback/v1', Uint8List? key}) =>
      Signalling(group: group(context), device: key ?? device(), relays: relays, connect: relay.connect);

  test('devices of one group find each other and exchange offers', () async {
    final relay = FakeRelay();
    final aKey = device();
    final a = node(relay, key: aKey);
    final b = node(relay);
    final aHeard = <SymbolonSignal>[];
    final bHeard = <SymbolonSignal>[];
    a.signals.listen(aHeard.add);
    b.signals.listen(bHeard.add);

    a.start();
    await pumpEventQueue();
    b.start();
    await pumpEventQueue();
    // A was subscribed when B announced; B wasn't subscribed yet when A announced.
    expect(aHeard.single.kind, SignalKind.announce);
    expect(bHeard, isEmpty);

    b.send(SignalKind.offer, to: a.session, body: utf8.encode('sdp'));
    // An offer to some other session goes to nobody.
    b.send(SignalKind.offer, to: symbolon.newSession(), body: utf8.encode('not for a'));
    await pumpEventQueue();
    expect(aHeard.last.kind, SignalKind.offer);
    expect(utf8.decode(aHeard.last.body), 'sdp');
    expect(aHeard, hasLength(2));

    a.send(SignalKind.answer, to: aHeard.last.from, body: utf8.encode('answer'));
    await pumpEventQueue();
    expect(bHeard.single.kind, SignalKind.answer);
    expect(bHeard.single.device, aKey);
    await a.stop();
    await pumpEventQueue();
    expect(bHeard.last.kind, SignalKind.bye);
    await b.stop();
  });

  test('relays see only sealed content under the topic, signed by a throwaway key', () async {
    final relay = FakeRelay();
    final a = node(relay)..start();
    await pumpEventQueue();
    final event = (jsonDecode(relay.published.single) as List)[1] as Map;
    expect(event['kind'], 21059);
    expect(utf8.decode(base64.decode(event['content'] as String), allowMalformed: true),
        isNot(contains('announce')));
    final again = node(relay)..start();
    await pumpEventQueue();
    final second = (jsonDecode(relay.published.last) as List)[1] as Map;
    expect(second['pubkey'], isNot(event['pubkey']));
    expect(second['tags'], event['tags']);
    await a.stop();
    await again.stop();
  });

  test('ignores other groups, junk, duplicates and old messages', () async {
    final relay = FakeRelay();
    final heard = <SymbolonSignal>[];
    var clock = 1800000000;
    final a = Signalling(
        group: group('bringmeback/v1'), device: device(), relays: relays, connect: relay.connect,
        now: () => clock)
      ..signals.listen(heard.add)
      ..start();
    await pumpEventQueue();
    final other = node(relay, context: 'other/v1')..start();
    await pumpEventQueue();
    expect(heard, isEmpty);

    final conn = relay.connections.first;
    for (final junk in ['not json', '[]', '["EVENT"]', '["NOTICE","hi"]', '["EVENT","x",{}]',
        jsonEncode(['EVENT', conn.subscription, {'kind': 21059, 'id': 'a', 'content': 'AAAA'}]),
        'x' * 70000]) {
      conn.incoming.add(junk);
    }
    await pumpEventQueue();
    expect(heard, isEmpty);

    // A real event from this group, delivered twice and then replayed much later.
    final sender = Signalling(
        group: group('bringmeback/v1'), device: device(), relays: relays, connect: FakeRelay().connect,
        now: () => clock);
    final event = (jsonDecode(sender.eventForTests(SignalKind.announce)) as List)[1];
    final message = jsonEncode(['EVENT', conn.subscription, event]);
    conn.incoming..add(message)..add(message);
    await pumpEventQueue();
    expect(heard, hasLength(1));
    clock += 3600;
    final late = Map.of(event as Map)..['id'] = 'other id';
    conn.incoming.add(jsonEncode(['EVENT', conn.subscription, late]));
    await pumpEventQueue();
    expect(heard, hasLength(1));
    await a.stop();
    await other.stop();
  });

  test('reconnects after the relay drops and announces again', () async {
    final relay = FakeRelay()..reachable = false;
    final a = node(relay)..start();
    await pumpEventQueue();
    expect(relay.published, isEmpty);
    relay.reachable = true;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await pumpEventQueue();
    expect(relay.published, hasLength(1));
    await relay.connections.last.incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await pumpEventQueue();
    expect(relay.published, hasLength(2));
    await a.stop();
  });
}
