import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'pairing.dart';
import 'signalling.dart';
import 'sync_config.dart';

/// Whether this device is in a sync group, the keys for it, and which of the group's devices are
/// online. The data exchange between them comes in a later step.
class SyncState {
  final DeviceIdentity? device;
  final PairingCode? pairing;
  final String? code;
  final GroupKeys? keys;

  /// False when Symbolon could not be loaded, so this device can't sync.
  final bool supported;

  /// Whether this device looks for the group's other devices on the relays. Off by default.
  final bool live;

  /// The device ids ([DeviceIdentity.id]) of the group's other devices that are online now.
  final Set<String> online;

  const SyncState(
      {this.device,
      this.pairing,
      this.code,
      this.keys,
      this.supported = true,
      this.live = false,
      this.online = const {}});

  bool get paired => pairing != null;

  SyncState copyWith({bool? live, Set<String>? online}) => SyncState(
      device: device,
      pairing: pairing,
      code: code,
      keys: keys,
      supported: supported,
      live: live ?? this.live,
      online: online ?? this.online);
}

class SyncCubit extends Cubit<SyncState> {
  static const _deviceKey = 'deviceKey';
  static const _pairingKey = 'pairingCode';
  static const _liveKey = 'liveSync';

  final RelayConnector _connect;
  final SyncConfig _config;
  Signalling? _signalling;
  StreamSubscription<SymbolonSignal>? _signals;

  /// Sessions heard from in this run, so each gets one announce back and no more.
  final _answered = <String>{};

  SyncCubit({RelayConnector connect = webSocketRelay, SyncConfig? config})
      : _connect = connect,
        _config = config ?? SyncConfig.fromEnvironment(),
        super(const SyncState());

  Future<void> load() async {
    try {
      await loadSymbolon();
    } on Object {
      // Without Symbolon there is no sync, but the rest of the app works.
      emit(const SyncState(supported: false));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final storedDevice = prefs.getString(_deviceKey);
    final DeviceIdentity device;
    if (storedDevice == null) {
      device = DeviceIdentity.generate();
      await prefs.setString(_deviceKey, device.encode());
    } else {
      device = DeviceIdentity.decode(storedDevice);
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
    final live = prefs.getBool(_liveKey) ?? false;
    emit((await _stateFor(device, pairing)).copyWith(live: live));
    await _restartSignalling();
  }

  /// Turns looking for the group's other devices on or off.
  Future<void> setLive(bool live) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liveKey, live);
    emit(state.copyWith(live: live, online: const {}));
    await _restartSignalling();
  }

  Future<void> _restartSignalling() async {
    await _signals?.cancel();
    await _signalling?.stop();
    _signals = null;
    _signalling = null;
    _answered.clear();
    if (!state.paired || !state.live) return;
    final signalling = Signalling(
        group: state.keys!.inner,
        device: state.device!.publicKey,
        relays: _config.relays,
        connect: _connect);
    _signalling = signalling;
    _signals = signalling.signals.listen(_heard);
    signalling.start();
  }

  void _heard(SymbolonSignal signal) {
    final device = base64Url.encode(signal.device).replaceAll('=', '');
    switch (signal.kind) {
      case SignalKind.announce:
        emit(state.copyWith(online: {...state.online, device}));
        // Announce back once, so a device that came online after this one learns about it too.
        if (_answered.add(base64.encode(signal.from))) {
          _signalling?.send(SignalKind.announce);
        }
      case SignalKind.bye:
        emit(state.copyWith(online: {...state.online}..remove(device)));
      case SignalKind.offer || SignalKind.answer || SignalKind.candidate:
        // The direct connection is set up in a later step.
        break;
    }
  }

  @override
  Future<void> close() async {
    await _signals?.cancel();
    await _signalling?.stop();
    return super.close();
  }

  /// Starts a new group with this device in it.
  Future<void> createGroup() => _join(PairingCode.generate());

  /// Joins the group of the device that shows `code`. Throws [FormatException] for a bad code.
  Future<void> joinGroup(String code) async => _join(await PairingCode.parse(code));

  Future<void> leaveGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairingKey);
    emit(SyncState(device: state.device, live: state.live));
    await _restartSignalling();
  }

  Future<void> _join(PairingCode pairing) async {
    final next = await _stateFor(state.device!, pairing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairingKey, next.code!);
    emit(next.copyWith(live: state.live));
    await _restartSignalling();
  }

  static Future<SyncState> _stateFor(DeviceIdentity device, PairingCode? pairing) async =>
      pairing == null
          ? SyncState(device: device)
          : SyncState(
              device: device,
              pairing: pairing,
              code: await pairing.encode(),
              keys: pairing.deriveKeys());
}
