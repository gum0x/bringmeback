import 'package:bringmeback/sync/sync_cubit.dart';
import 'package:bringmeback/sync/sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_relay.dart';
import 'symbolon_native.dart';

void main() {
  setUpAll(loadSymbolonForTests);

  test('the task view shows whether the other devices are connected and in sync', () async {
    SharedPreferences.setMockInitialValues({});
    final cubit = SyncCubit(connect: FakeRelay().connect);
    await cubit.load();
    expect(SyncStatus.of(cubit.state).health, SyncHealth.off);
    await cubit.createGroup();
    expect(SyncStatus.of(cubit.state).label, 'Devices: sync is off');
    final live = cubit.state.copyWith(live: true);
    expect(SyncStatus.of(live).health, SyncHealth.alone);

    final at = DateTime(2026, 11, 9, 9, 5);
    final notConnected = live.copyWith(online: {'b', 'c'}, connected: {'b'}, lastSynced: at);
    expect(SyncStatus.of(notConnected).health, SyncHealth.notConnected);
    expect(SyncStatus.of(notConnected).label,
        '1 of 2 online devices connected. Last in sync at 09:05');

    final down = live.copyWith(relaysUnreachable: true);
    expect(SyncStatus.of(down).health, SyncHealth.relaysDown);
    // Devices already connected keep syncing without the relays.
    expect(SyncStatus.of(down.copyWith(online: {'b'}, connected: {'b'}, inSync: {'b'})).health,
        SyncHealth.inSync);

    final syncing = live.copyWith(online: {'b'}, connected: {'b'});
    expect(SyncStatus.of(syncing).health, SyncHealth.syncing);
    final inSync = syncing.copyWith(inSync: {'b'});
    expect(SyncStatus.of(inSync).health, SyncHealth.inSync);
    expect(SyncStatus.of(inSync).label, 'In sync with 1 device');
    await cubit.close();
  });

  testWidgets('Sync now shows only in a sync group, and says what it did', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cubit = SyncCubit(connect: FakeRelay().connect);
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(bottomNavigationBar: SyncNowButton()))));
    expect(find.byTooltip('Sync now'), findsNothing);

    await tester.runAsync(cubit.createGroup);
    await tester.pump();
    await tester.tap(find.byTooltip('Sync now (sync is off)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Sync is off on this device.'), findsOneWidget);

    await tester.runAsync(() => cubit.setLive(true));
    await tester.pump();
    await tester.tap(find.byTooltip('Sync now'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Looking for your other devices'), findsOneWidget);
    await tester.runAsync(cubit.close);
  });
}
