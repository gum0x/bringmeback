import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_relay.dart';
import 'symbolon_native.dart';

void main() {
  setUpAll(loadSymbolonForTests);

  test('paired devices with live sync on see each other online, and not once one leaves', () async {
    SharedPreferences.setMockInitialValues({});
    final relay = FakeRelay();
    final a = SyncCubit(connect: relay.connect);
    await a.load();
    await a.createGroup();
    // Off by default: nothing is sent to any relay.
    await pumpEventQueue();
    expect(relay.published, isEmpty);
    await a.setLive(true);
    await pumpEventQueue();

    // A second device, with its own stored state.
    SharedPreferences.setMockInitialValues({});
    final b = SyncCubit(connect: relay.connect);
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
}
