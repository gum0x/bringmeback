import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pairing.dart';

/// Whether this device is in a sync group, and the keys for it. Live sync itself comes in a later step,
/// so for now this only stores the pairing.
class SyncState {
  final DeviceIdentity? device;
  final PairingCode? pairing;
  final String? code;
  final GroupKeys? keys;

  const SyncState({this.device, this.pairing, this.code, this.keys});

  bool get paired => pairing != null;
}

class SyncCubit extends Cubit<SyncState> {
  static const _deviceKey = 'deviceKey';
  static const _pairingKey = 'pairingCode';

  SyncCubit() : super(const SyncState());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDevice = prefs.getString(_deviceKey);
    final DeviceIdentity device;
    if (storedDevice == null) {
      device = await DeviceIdentity.generate();
      await prefs.setString(_deviceKey, device.encode());
    } else {
      device = await DeviceIdentity.decode(storedDevice);
    }
    final storedCode = prefs.getString(_pairingKey);
    PairingCode? pairing;
    if (storedCode != null) {
      try {
        pairing = await PairingCode.parse(storedCode);
      } on FormatException {
        await prefs.remove(_pairingKey);
      }
    }
    emit(await _stateFor(device, pairing));
  }

  /// Starts a new group with this device in it.
  Future<void> createGroup() => _join(PairingCode.generate());

  /// Joins the group of the device that shows `code`. Throws [FormatException] for a bad code.
  Future<void> joinGroup(String code) async => _join(await PairingCode.parse(code));

  Future<void> leaveGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairingKey);
    emit(SyncState(device: state.device));
  }

  Future<void> _join(PairingCode pairing) async {
    final next = await _stateFor(state.device!, pairing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairingKey, next.code!);
    emit(next);
  }

  static Future<SyncState> _stateFor(DeviceIdentity device, PairingCode? pairing) async =>
      pairing == null
          ? SyncState(device: device)
          : SyncState(
              device: device,
              pairing: pairing,
              code: await pairing.encode(),
              keys: await pairing.deriveKeys());
}
