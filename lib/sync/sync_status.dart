import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'sync_cubit.dart';
import 'sync_page.dart';

enum SyncHealth {
  /// Not in a group, or sync is off: nothing to watch.
  idle,

  /// Looking for the group's other devices, and none is online.
  alone,

  /// Some online devices aren't connected, so they can't sync.
  notConnected,

  /// Connected, and changes are still on their way.
  syncing,

  /// Every online device is connected and has the same tasks.
  inSync,
}

/// How sync is doing, in a few words for the task view.
class SyncStatus {
  final SyncHealth health;
  final String label;

  const SyncStatus(this.health, this.label);

  factory SyncStatus.of(SyncState state) {
    String devices(int n) => n == 1 ? '1 device' : '$n devices';
    final last = state.lastSynced;
    final since = last == null ? '' : '. Last in sync at ${_time(last)}';
    if (!state.paired) return const SyncStatus(SyncHealth.idle, 'Devices: not in a sync group');
    if (!state.live) return const SyncStatus(SyncHealth.idle, 'Devices: sync is off');
    final online = state.online.length;
    final connected = state.connected.length;
    if (online == 0 && connected == 0) {
      return SyncStatus(SyncHealth.alone, 'No other device online$since');
    }
    if (connected < online) {
      final what = connected > 0
          ? '$connected of $online online devices connected'
          : online == 1
              ? 'A device is online but not connected'
              : '$online devices are online but not connected';
      return SyncStatus(SyncHealth.notConnected, '$what$since');
    }
    if (!state.allInSync)
      return SyncStatus(SyncHealth.syncing, 'Syncing with ${devices(connected)}');
    return SyncStatus(SyncHealth.inSync, 'In sync with ${devices(connected)}');
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The Devices button in the task view, showing at a glance whether the other devices are
/// connected and in sync. Its tooltip says more, and it opens the Devices page.
class SyncStatusButton extends StatefulWidget {
  const SyncStatusButton({super.key});

  @override
  State<SyncStatusButton> createState() => _SyncStatusButtonState();
}

class _SyncStatusButtonState extends State<SyncStatusButton> {
  /// Each edit briefly takes the devices out of sync until they confirm it. Only show "syncing"
  /// if it lasts, so the icon doesn't flicker while typing.
  static const _settle = Duration(seconds: 2);

  SyncStatus? _shown;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _update(SyncStatus next) {
    final shown = _shown;
    if (shown != null && shown.health == SyncHealth.inSync && next.health == SyncHealth.syncing) {
      _pending ??= Timer(_settle, () {
        _pending = null;
        if (mounted) setState(() => _shown = SyncStatus.of(context.read<SyncCubit>().state));
      });
      return;
    }
    _pending?.cancel();
    _pending = null;
    _shown = next;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(builder: (context, state) {
      _update(SyncStatus.of(state));
      final status = _shown!;
      final colors = Theme.of(context).colorScheme;
      final (icon, color) = switch (status.health) {
        SyncHealth.idle => (Icons.devices, null),
        SyncHealth.alone => (Icons.cloud_off, colors.outline),
        SyncHealth.notConnected => (Icons.cloud_off, colors.error),
        SyncHealth.syncing => (Icons.cloud_sync, colors.tertiary),
        SyncHealth.inSync => (Icons.cloud_done, Colors.green),
      };
      return IconButton(
        tooltip: status.label,
        icon: Icon(icon, color: color, semanticLabel: status.label),
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncPage())),
      );
    });
  }
}
