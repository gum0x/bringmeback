import 'package:bringmeback/sync/relays.dart';
import 'package:bringmeback/sync/signalling.dart';
import 'package:bringmeback/sync/sync_config.dart';
import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_relay.dart';
import 'fake_transport.dart';
import 'symbolon_native.dart';

const _published = ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'];

void main() {
  group('normaliseRelay', () {
    test('accepts relay addresses and bare hosts', () {
      expect(normaliseRelay('wss://relay.example.com'), 'wss://relay.example.com');
      expect(normaliseRelay(' relay.example.com '), 'wss://relay.example.com');
      expect(normaliseRelay('wss://relay.example.com/'), 'wss://relay.example.com');
      expect(normaliseRelay('wss://relay.example.com:7447/nostr'), 'wss://relay.example.com:7447/nostr');
      expect(normaliseRelay('ws://192.168.1.10:7000'), 'ws://192.168.1.10:7000');
    });

    test('refuses anything else', () {
      for (final bad in [
        '',
        'https://relay.example.com',
        'wss://',
        'wss://user:pw@relay.example.com',
        'wss://relay.example.com?x=1',
        'javascript:alert(1)',
        'wss://bad host',
      ]) {
        expect(normaliseRelay(bad), isNull, reason: bad);
      }
    });
  });

  group('relaysFromLink', () {
    test('reads a comma-separated list from the query', () {
      expect(relaysFromLink(Uri.parse('https://app.example/?relays=wss://a.example,b.example')),
          ['wss://a.example', 'wss://b.example']);
    });

    test('reads repeated relay= and an encoded list', () {
      expect(
          relaysFromLink(Uri.parse(
              'https://app.example/?relay=wss%3A%2F%2Fa.example&relay=b.example&relay=a.example')),
          ['wss://a.example', 'wss://b.example']);
    });

    test('reads the fragment of a join link', () {
      expect(
          relaysFromLink(Uri.parse('https://app.example/#join=bmb1-abc&relays=wss://a.example')),
          ['wss://a.example']);
      expect(relaysFromLink(Uri.parse('https://app.example/#/sync?relays=a.example')),
          ['wss://a.example']);
    });

    test('names none without relays, and drops what is not a relay', () {
      expect(relaysFromLink(Uri.parse('https://app.example/')), isEmpty);
      expect(relaysFromLink(Uri.parse('https://app.example/#join=bmb1-abc')), isEmpty);
      expect(relaysFromLink(Uri.parse('https://app.example/?relays=https://x.example,%ZZ')),
          isEmpty);
    });
  });

  group('RelayList', () {
    test('turns published relays off and adds custom ones', () {
      var list = const RelayList(published: _published);
      expect(list.active, _published);
      expect(list.isDefault, isTrue);
      list = list.turn('wss://nos.lol', on: false).add('wss://mine.example');
      expect(list.active, ['wss://relay.damus.io', 'wss://relay.primal.net', 'wss://mine.example']);
      // Adding a published relay turns it back on instead of repeating it.
      list = list.add('wss://nos.lol');
      expect(list.custom, ['wss://mine.example']);
      expect(list.active, contains('wss://nos.lol'));
      expect(list.reset().isDefault, isTrue);
    });

    test('only() keeps exactly the given relays', () {
      final list = const RelayList(published: _published)
          .add('wss://old.example')
          .only(['wss://nos.lol', 'wss://new.example']);
      expect(list.active, ['wss://nos.lol', 'wss://new.example']);
    });

    test('saves only the changes and survives bad data', () {
      final list = const RelayList(published: _published)
          .turn('wss://relay.damus.io', on: false)
          .add('wss://mine.example');
      final back = RelayList.decode(list.encode(), [..._published, 'wss://later.example']);
      expect(back.active,
          ['wss://nos.lol', 'wss://relay.primal.net', 'wss://later.example', 'wss://mine.example']);
      expect(RelayList.decode('not json', _published).isDefault, isTrue);
      expect(RelayList.decode('{"custom":["https://x"]}', _published).custom, isEmpty);
    });
  });

  group('SyncCubit relays', () {
    setUpAll(loadSymbolonForTests);

    late List<Uri> dialled;
    late FakeRelay relay;
    RelayConnection connect(Uri url) {
      dialled.add(url);
      return relay.connect(url);
    }

    setUp(() {
      dialled = [];
      relay = FakeRelay();
    });

    Future<SyncCubit> live({Uri? link}) async {
      final cubit = SyncCubit(
          connect: connect,
          transport: FakeNetwork().create,
          config: SyncConfig(relays: [for (final r in _published) Uri.parse(r)]),
          link: link);
      await cubit.load();
      await cubit.createGroup();
      await cubit.setLive(true);
      await pumpEventQueue();
      return cubit;
    }

    test('uses the published relays, then the edited list, and remembers it', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await live();
      expect(dialled.toSet(), {for (final r in _published) Uri.parse(r)});

      dialled.clear();
      await a.setRelayOn('wss://relay.damus.io', on: false);
      await a.addRelay('mine.example');
      await pumpEventQueue();
      expect(a.state.relayCount, 3);
      expect(dialled.last, Uri.parse('wss://mine.example'));
      expect(dialled, isNot(contains(Uri.parse('wss://relay.damus.io'))));
      await expectLater(a.addRelay('https://nope.example'), throwsFormatException);
      await a.close();

      // A new run reads the saved list.
      dialled.clear();
      final again = SyncCubit(
          connect: connect,
          transport: FakeNetwork().create,
          config: SyncConfig(relays: [for (final r in _published) Uri.parse(r)]));
      await again.load();
      await pumpEventQueue();
      expect(again.state.activeRelays, ['wss://nos.lol', 'wss://relay.primal.net', 'wss://mine.example']);
      expect(dialled.toSet(), {for (final r in again.state.activeRelays) Uri.parse(r)});
      await again.close();
    });

    test('keeps at least one relay', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await live();
      expect(await a.setRelayOn(_published[0], on: false), isTrue);
      expect(await a.setRelayOn(_published[1], on: false), isTrue);
      expect(await a.setRelayOn(_published[2], on: false), isFalse);
      expect(a.state.activeRelays, [_published[2]]);
      await a.close();
    });

    test('a link\'s relays are used instead of the list, and can be saved', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await live(link: Uri.parse('https://app.example/?relays=wss://private.example'));
      expect(dialled, [Uri.parse('wss://private.example')]);
      expect(a.state.relayCount, 1);

      await a.keepLinkRelays();
      expect(a.state.linkRelays, isEmpty);
      expect(a.state.activeRelays, ['wss://private.example']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('syncRelays'), contains('private.example'));

      dialled.clear();
      await a.resetRelays();
      await pumpEventQueue();
      expect(dialled.toSet(), {for (final r in _published) Uri.parse(r)});
      await a.close();
    });

    test('two devices meet on the relays a link names', () async {
      SharedPreferences.setMockInitialValues({});
      final link = Uri.parse('https://app.example/#join=x&relays=wss://private.example');
      final a = await live(link: link);
      SharedPreferences.setMockInitialValues({});
      final b = SyncCubit(
          connect: connect,
          transport: FakeNetwork().create,
          config: SyncConfig(relays: [for (final r in _published) Uri.parse(r)]));
      await b.load();
      await b.joinGroup(a.state.code!);
      await b.useLinkRelays(['private.example']);
      await b.setLive(true);
      await pumpEventQueue();
      expect(b.state.activeRelays, ['wss://private.example']);
      expect(a.state.online, {b.state.device!.id});
      expect(dialled.toSet(), {Uri.parse('wss://private.example')});

      await b.useSavedRelays();
      expect(b.state.activeRelays, _published);
      await a.close();
      await b.close();
    });
  });
}
