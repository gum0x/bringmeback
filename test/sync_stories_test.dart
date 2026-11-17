import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/sync/signalling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'doc_sync_test.dart' show newDocument, twoDevices;
import 'fake_relay.dart';
import 'symbolon_native.dart';
import 'task_document_test.dart' show exchange;

/// User stories of docs/USER-STORIES.md that no other test file covers. Each test names its story.
void main() {
  setUpAll(loadSymbolonForTests);

  TaskDocument yesterdaysNote() => newDocument()
    ..setNoteStartedAt(1000)
    ..insert(0, 't1', name: 'one')
    ..insert(1, 't2', name: 'two');

  group('T1 tearing off reaches the other devices', () {
    test('T1.1 a note torn off on one device clears it on a connected one, at once', () async {
      final desktop = yesterdaysNote();
      final phone = newDocument();
      final (a, b, _) = await twoDevices(desktop, phone);
      expect(phone.ids, ['t1', 't2']);

      desktop.tearOff('n1', 2000);
      await pumpEventQueue();

      // Nothing left to tear off on the phone: its note is the new, empty one.
      expect(phone.ids, isEmpty);
      expect(phone.noteStartedAt, 2000);
      expect(phone.notes.single.taskIds, ['t1', 't2']);
      expect(phone.pendingIds, ['t1', 't2']);
      await a.close();
      await b.close();
    });

    test('T1.2 a tear-off made while the devices were apart arrives when they sync again',
        () async {
      final desktop = yesterdaysNote();
      final phone = newDocument();
      final (a, b, net) = await twoDevices(desktop, phone);
      net.hold = true;
      desktop.tearOff('n1', 2000);
      desktop.carry('t1', 'c1', 0);
      await pumpEventQueue();
      expect(phone.ids, ['t1', 't2'], reason: 'Apart: the phone still shows the old note');

      net.release();
      await pumpEventQueue();
      expect(phone.ids, ['c1']);
      expect(phone.noteStartedAt, 2000);
      expect(phone.pendingIds, ['t2']);
      await a.close();
      await b.close();
    });

    test('T1.5 one device writes a task again while the other lets it go: written again wins', () {
      final desktop = yesterdaysNote();
      final phone = newDocument();
      exchange(desktop, phone);
      desktop.tearOff('n1', 2000);
      exchange(desktop, phone);

      desktop.carry('t1', 'c1', 0);
      phone.letGo('t1');
      exchange(desktop, phone);

      for (final d in [desktop, phone]) {
        expect(d.ids, ['c1'], reason: 'The task written again stays on today\'s note');
        expect(d.statuses(['t1'])['t1'], TaskStatus.carried);
        expect(d.pendingIds, ['t2']);
      }
    });
  });

  group('D5 clocks', () {
    final secret = List.generate(32, (i) => i);
    SymbolonGroupKeys group() => symbolon.groupKeys('bringmeback/v1'.codeUnits, secret);

    Future<List<SymbolonSignal>> heardWithSkew(int seconds) async {
      final relay = FakeRelay();
      final clock = unixNow();
      final a = Signalling(
          group: group(),
          device: symbolon.generateDeviceKey().publicKey,
          relays: [Uri.parse('wss://relay.test')],
          connect: relay.connect,
          now: () => clock);
      final other = Signalling(
          group: group(),
          device: symbolon.generateDeviceKey().publicKey,
          relays: [Uri.parse('wss://relay.test')],
          connect: relay.connect,
          now: () => clock + seconds);
      final heard = <SymbolonSignal>[];
      a.signals.listen(heard.add);
      a.start();
      await pumpEventQueue();
      other.start();
      await pumpEventQueue();
      await a.stop();
      await other.stop();
      return heard;
    }

    test('D5.1 a device whose clock is up to two minutes off either way is heard', () async {
      expect(await heardWithSkew(-110), hasLength(1));
      expect(await heardWithSkew(110), hasLength(1));
    });

    test('D5.2 a device whose clock is more than two minutes off is not heard (known limit)',
        () async {
      expect(await heardWithSkew(-180), isEmpty);
      expect(await heardWithSkew(180), isEmpty);
    });
  });
}
