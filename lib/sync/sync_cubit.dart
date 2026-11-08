import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'pairing.dart';
import 'peer.dart';
import 'signalling.dart';
import 'sync_config.dart';

/// Whether this device is in a sync group, the keys for it, and which of the group's devices are
/// online and connected. The data exchange between them comes in a later step.
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

  /// The device ids of the group's devices this one has a direct, encrypted link to.
  final Set<String> connected;

  const SyncState(
      {this.device,
      this.pairing,
      this.code,
      this.keys,
      this.supported = true,
      this.live = false,
      this.online = const {},
      this.connected = const {}});

  bool get paired => pairing != null;

  SyncState copyWith({bool? live, Set<String>? online, Set<String>? connected}) => SyncState(
      device: device,
      pairing: pairing,
      code: code,
      keys: keys,
      supported: supported,
      live: live ?? this.live,
      online: online ?? this.online,
      connected: connected ?? this.connected);
}

class SyncCubit extends Cubit<SyncState> {
  static const _deviceKey = 'deviceKey';
  static const _pairingKey = 'pairingCode';
  static const _liveKey = 'liveSync';

  /// Bound into every Noise handshake together with the group's topic.
  static const _prologue = 'bringmeback/v1';
  static const _firstRetry = Duration(seconds: 5);
  static const _maxRetry = Duration(minutes: 5);

  final RelayConnector _connect;
  final SyncConfig _config;
  final PeerTransportFactory _newTransport;
  Signalling? _signalling;
  StreamSubscription<SymbolonSignal>? _signals;

  /// Sessions heard from in this run, so each gets one announce back and no more.
  final _answered = <String>{};

  /// Links by device id, and the devices whose link is being set up.
  final _links = <String, PeerLink>{};
  final _pending = <String>{};

  /// Initiator only: when to try a dropped link again, and how long to wait the time after.
  final _retries = <String, Timer>{};
  final _backoff = <String, Duration>{};

  SyncCubit(
      {RelayConnector connect = webSocketRelay,
      SyncConfig? config,
      PeerTransportFactory? transport})
      : _connect = connect,
        _config = config ?? SyncConfig.fromEnvironment(),
        _newTransport = transport ?? _webRtc(config ?? SyncConfig.fromEnvironment()),
        super(const SyncState());

  static PeerTransportFactory _webRtc(SyncConfig config) =>
      () => WebRtcTransport.create(config.iceServers);

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
    await _closeLinks();
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
    final device = _id(signal.device);
    switch (signal.kind) {
      case SignalKind.announce:
        _emit(state.copyWith(online: {...state.online, device}));
        // Announce back once, so a device that came online after this one learns about it too.
        if (_answered.add(base64.encode(signal.from))) {
          _signalling?.send(SignalKind.announce);
        }
        if (_initiates(signal.device)) _link(signal, initiator: true);
      case SignalKind.bye:
        _retries.remove(device)?.cancel();
        _backoff.remove(device);
        _links.remove(device)?.close();
        _emit(state.copyWith(
            online: {...state.online}..remove(device),
            connected: {...state.connected}..remove(device)));
      case SignalKind.offer:
        // Only the device that doesn't initiate takes offers, so two devices never cross offers.
        if (!_initiates(signal.device)) {
          _emit(state.copyWith(online: {...state.online, device}));
          _link(signal, initiator: false);
        }
      case SignalKind.answer:
        final link = _links[device];
        if (link != null && _sameBytes(link.remoteSession, signal.from)) link.signalled(signal);
      case SignalKind.candidate:
        // Candidates travel inside the offer and the answer.
        break;
    }
  }

  bool _initiates(List<int> remote) => symbolon.initiates(state.device!.publicKey, remote);

  /// Sets up a link to the device that sent `signal`: an announce (initiator) or an offer.
  Future<void> _link(SymbolonSignal signal, {required bool initiator}) async {
    final id = _id(signal.device);
    final existing = _links[id];
    // Announces repeat when a relay reconnects; keep a link that is still up for that session.
    if (initiator &&
        existing != null &&
        !existing.isClosed &&
        _sameBytes(existing.remoteSession, signal.from)) {
      return;
    }
    final signalling = _signalling;
    if (signalling == null || !_pending.add(id)) return;
    _retries.remove(id)?.cancel();
    final PeerTransport transport;
    try {
      transport = await _newTransport();
    } on Object {
      _pending.remove(id);
      return;
    }
    // No await from here until the link is in _links, so a repeated announce can't start another.
    _pending.remove(id);
    if (_signalling != signalling || isClosed) {
      await transport.close();
      return;
    }
    _links.remove(id)?.close();
    final link = PeerLink(
        remoteDevice: Uint8List.fromList(signal.device),
        remoteSession: Uint8List.fromList(signal.from),
        initiator: initiator,
        transport: transport,
        device: state.device!,
        keys: state.keys!,
        prologue: [...utf8.encode(_prologue), ...signalling.topic],
        signal: (kind, body) => signalling.send(kind, to: signal.from, body: body));
    _links[id] = link;
    link.connected.then((_) {
      _backoff.remove(id);
      if (_links[id] == link) _emit(state.copyWith(connected: {...state.connected, id}));
    }, onError: (Object _) {});
    link.closed.then((_) {
      if (_links[id] != link) return;
      _links.remove(id);
      _emit(state.copyWith(connected: {...state.connected}..remove(id)));
      if (initiator && _signalling == signalling && state.online.contains(id)) {
        _retry(signal, signalling);
      }
    });
    if (initiator) {
      await link.start();
    } else {
      await link.signalled(signal);
    }
  }

  /// Tries a dropped link again after a while, waiting longer each time it fails.
  void _retry(SymbolonSignal announce, Signalling signalling) {
    final id = _id(announce.device);
    final wait = _backoff[id] ?? _firstRetry;
    _backoff[id] = wait * 2 > _maxRetry ? _maxRetry : wait * 2;
    _retries[id]?.cancel();
    _retries[id] = Timer(wait, () {
      _retries.remove(id);
      if (_signalling == signalling && state.online.contains(id)) _link(announce, initiator: true);
    });
  }

  Future<void> _closeLinks() async {
    for (final t in _retries.values) {
      t.cancel();
    }
    _retries.clear();
    _backoff.clear();
    final links = _links.values.toList();
    _links.clear();
    await Future.wait(links.map((l) => l.close()));
    _emit(state.copyWith(connected: const {}));
  }

  void _emit(SyncState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() async {
    await _signals?.cancel();
    await _signalling?.stop();
    _signalling = null;
    await _closeLinks();
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

String _id(List<int> device) => base64Url.encode(device).replaceAll('=', '');

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
