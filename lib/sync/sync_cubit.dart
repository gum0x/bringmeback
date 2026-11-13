import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import '../version/build_info.dart';
import 'doc_sync.dart';
import 'pairing.dart';
import 'peer.dart';
import 'relays.dart';
import 'signalling.dart';
import 'sync_config.dart';

/// Why this device isn't syncing with one of the group's devices, for the Devices page.
class SyncProblem {
  final LinkFailure failure;

  /// The other device's [syncProtocol], when it is known.
  final int? remoteProtocol;

  /// Whether the link had connected before it failed.
  final bool wasConnected;

  const SyncProblem(this.failure, {this.remoteProtocol, this.wasConnected = false});

  /// What went wrong and what to do about it, in a sentence or two.
  String get message => switch (failure) {
        LinkFailure.version => remoteProtocol != null && remoteProtocol! > syncProtocol
            ? 'That device runs a newer version of bringmeback (sync version $remoteProtocol, '
                'this one is $syncProtocol). Update this device, for example by reloading the page.'
            : 'That device runs an older version of bringmeback (sync version '
                '${remoteProtocol ?? 1}, this one is $syncProtocol). Update it, for example by '
                'reloading the page there.',
        LinkFailure.timeout => 'No direct connection within '
            '${PeerLink.connectTimeout.inSeconds} seconds. Both devices need to be on the same '
            'network, and a browser setting that blocks WebRTC (such as Brave\'s "Disable '
            'non-proxied UDP") stops it. A device on an older version of bringmeback also never '
            'answers.',
        LinkFailure.transport => wasConnected
            ? 'The connection was lost. Trying again.'
            : 'The direct connection could not be set up. Check that both devices are on the same '
                'network.',
        LinkFailure.handshake => 'The encrypted handshake failed. Check that the group '
            'fingerprint is the same on both devices, and that both run the same version.',
        LinkFailure.protocol => 'That device sent data this one can\'t read. Check that both run '
            'the same version of bringmeback.',
      };
}

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

  /// Why the link to a device failed last, by device id, until it connects.
  final Map<String, SyncProblem> problems;

  /// The app build each device that offered or answered runs, by device id.
  final Map<String, BuildInfo> builds;

  /// How many relays this device is connected to, out of [relayCount], while it looks for devices.
  final int relaysUp;
  final int relayCount;

  /// True when no relay could be reached for a while: then no device can be found.
  final bool relaysUnreachable;

  /// The relays saved on this device.
  final RelayList relays;

  /// The relays the link that opened the app names (`?relays=…`), used instead of [relays] while
  /// not empty.
  final List<String> linkRelays;

  const SyncState(
      {this.device,
      this.pairing,
      this.code,
      this.keys,
      this.supported = true,
      this.live = false,
      this.online = const {},
      this.connected = const {},
      this.problems = const {},
      this.builds = const {},
      this.relaysUp = 0,
      this.relayCount = 0,
      this.relaysUnreachable = false,
      this.relays = const RelayList(published: []),
      this.linkRelays = const []});

  bool get paired => pairing != null;

  /// The relays this device looks for the group's other devices on.
  List<String> get activeRelays => linkRelays.isNotEmpty ? linkRelays : relays.active;

  SyncState copyWith(
          {bool? live,
          Set<String>? online,
          Set<String>? connected,
          Map<String, SyncProblem>? problems,
          Map<String, BuildInfo>? builds,
          int? relaysUp,
          int? relayCount,
          bool? relaysUnreachable,
          RelayList? relays,
          List<String>? linkRelays}) =>
      SyncState(
          device: device,
          pairing: pairing,
          code: code,
          keys: keys,
          supported: supported,
          live: live ?? this.live,
          online: online ?? this.online,
          connected: connected ?? this.connected,
          problems: problems ?? this.problems,
          builds: builds ?? this.builds,
          relaysUp: relaysUp ?? this.relaysUp,
          relayCount: relayCount ?? this.relayCount,
          relaysUnreachable: relaysUnreachable ?? this.relaysUnreachable,
          relays: relays ?? this.relays,
          linkRelays: linkRelays ?? this.linkRelays);
}

class SyncCubit extends Cubit<SyncState> {
  static const _deviceKey = 'deviceKey';
  static const _pairingKey = 'pairingCode';
  static const _liveKey = 'liveSync';
  static const _relaysKey = 'syncRelays';

  /// Bound into every Noise handshake together with the group's topic.
  static const _prologue = 'bringmeback/v1';
  static const _firstRetry = Duration(seconds: 5);
  static const _maxRetry = Duration(minutes: 5);

  final RelayConnector _connect;
  final SyncConfig _config;
  final PeerTransportFactory _newTransport;
  DocumentSync? _sync;
  Signalling? _signalling;
  StreamSubscription<SymbolonSignal>? _signals;
  StreamSubscription<int>? _relayChanges;
  Timer? _relayCheck;

  /// How long to wait for a first relay before saying none can be reached.
  static const relayGrace = Duration(seconds: 10);

  /// Sessions heard from in this run, so each gets one announce back and no more.
  final _answered = <String>{};

  /// Links by device id, and the devices whose link is being set up.
  final _links = <String, PeerLink>{};
  final _pending = <String>{};

  /// Initiator only: when to try a dropped link again, and how long to wait the time after.
  final _retries = <String, Timer>{};
  final _backoff = <String, Duration>{};

  /// When the app was last hidden, while it is hidden.
  DateTime? _hiddenAt;

  /// How long the app may be hidden before its relay connections and links are not trusted to be up.
  /// iOS freezes a hidden Safari tab, and its sockets die without a close the app ever sees.
  final Duration _staleAfter;

  /// The relays named by the link the app was opened with, until [load] puts them in the state.
  final List<String> _linkRelays;

  /// `document` is the task document to keep in sync, once it has loaded. `link` is the address the
  /// app was opened with; on the web that is the page's address, whose `relays=` it uses.
  SyncCubit(
      {RelayConnector connect = webSocketRelay,
      SyncConfig? config,
      PeerTransportFactory? transport,
      Future<CRDTDocument>? document,
      Uri? link,
      Duration staleAfter = const Duration(seconds: 20)})
      : _connect = connect,
        _staleAfter = staleAfter,
        _linkRelays = relaysFromLink(link ?? (kIsWeb ? Uri.base : Uri())),
        _config = config ?? SyncConfig.fromEnvironment(),
        _newTransport = transport ?? _webRtc(config ?? SyncConfig.fromEnvironment()),
        super(const SyncState()) {
    document?.then((doc) {
      if (isClosed) return;
      final sync = DocumentSync(doc);
      _sync = sync;
      for (final link in _links.values) {
        if (link.isConnected) sync.attach(link);
      }
    });
  }

  /// Syncs `doc` from now on instead of the document it synced before, after the task list replaced
  /// its document (see `TasksBloc.clearAll`).
  Future<void> useDocument(CRDTDocument doc) async {
    final old = _sync;
    final sync = DocumentSync(doc);
    _sync = sync;
    await old?.close();
    for (final link in _links.values) {
      if (link.isConnected) sync.attach(link);
    }
  }

  /// The app went to the background.
  void paused() => _hiddenAt ??= DateTime.now();

  /// The app is in front again. After a long enough break, reconnects at once instead of waiting
  /// for dead sockets to time out and for the retry backoff.
  Future<void> resumed() async {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null || DateTime.now().difference(hiddenAt) < _staleAfter) return;
    if (isClosed || state.device == null) return;
    _emit(state.copyWith(online: const {}));
    await _restartSignalling();
  }

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
    final relays = RelayList.decode(prefs.getString(_relaysKey), _published);
    emit((await _stateFor(device, pairing))
        .copyWith(live: live, relays: relays, linkRelays: _linkRelays));
    await _restartSignalling();
  }

  List<String> get _published => [for (final r in _config.relays) r.toString()];

  /// Turns a published relay on or off. The last relay in use can't be turned off: returns false.
  Future<bool> setRelayOn(String relay, {required bool on}) =>
      _saveRelays(state.relays.turn(relay, on: on));

  /// Adds a relay, given as `wss://host` or just the host. Throws [FormatException] when it isn't a
  /// relay address.
  Future<void> addRelay(String input) async {
    final relay = normaliseRelay(input);
    if (relay == null) {
      throw const FormatException('Enter a relay address like wss://relay.example.com');
    }
    await _saveRelays(state.relays.add(relay));
  }

  /// Removes a relay added on this device. The last relay in use can't be removed: returns false.
  Future<bool> removeRelay(String relay) => _saveRelays(state.relays.remove(relay));

  /// Back to the published relays, all on.
  Future<bool> resetRelays() => _saveRelays(state.relays.reset());

  /// Uses the relays a link names instead of the saved ones, until [useSavedRelays]. For a link the
  /// app gets after it started, such as one opened from the share menu.
  Future<void> useLinkRelays(List<String> relays) async {
    final valid = relays.map(normaliseRelay).whereType<String>().toSet().toList();
    if (valid.isEmpty || listEquals(valid, state.linkRelays)) return;
    await _changeRelays(state.copyWith(linkRelays: valid));
  }

  /// Saves the link's relays as this device's list: exactly those on, and stops using the link's.
  Future<void> keepLinkRelays() async {
    if (state.linkRelays.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final relays = state.relays.only(state.linkRelays);
    await prefs.setString(_relaysKey, relays.encode());
    await _changeRelays(state.copyWith(relays: relays, linkRelays: const []));
  }

  /// Stops using the link's relays for this run, and uses the saved ones.
  Future<void> useSavedRelays() => _changeRelays(state.copyWith(linkRelays: const []));

  Future<bool> _saveRelays(RelayList relays) async {
    if (relays.active.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    if (relays.isDefault) {
      await prefs.remove(_relaysKey);
    } else {
      await prefs.setString(_relaysKey, relays.encode());
    }
    await _changeRelays(state.copyWith(relays: relays));
    return true;
  }

  /// Emits `next`, and reconnects when the relays in use changed.
  Future<void> _changeRelays(SyncState next) async {
    final changed = !listEquals(next.activeRelays, state.activeRelays);
    _emit(next);
    if (changed) await _restartSignalling();
  }

  /// Turns looking for the group's other devices on or off.
  Future<void> setLive(bool live) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liveKey, live);
    emit(state.copyWith(live: live, online: const {}));
    await _restartSignalling();
  }

  Future<void> _stopSignalling() async {
    await _signals?.cancel();
    await _relayChanges?.cancel();
    _relayCheck?.cancel();
    await _signalling?.stop();
    _signals = null;
    _relayChanges = null;
    _signalling = null;
    _answered.clear();
    await _closeLinks();
    _emit(state.copyWith(
        problems: const {}, builds: const {}, relaysUp: 0, relayCount: 0, relaysUnreachable: false));
  }

  Future<void> _restartSignalling() async {
    await _stopSignalling();
    if (!state.paired || !state.live) return;
    final signalling = Signalling(
        group: state.keys!.inner,
        device: state.device!.publicKey,
        relays: [for (final r in state.activeRelays) Uri.parse(r)],
        connect: _connect);
    _signalling = signalling;
    _signals = signalling.signals.listen(_heard);
    _relayChanges = signalling.relayChanges.listen((up) {
      if (up > 0) _relayCheck?.cancel();
      _emit(state.copyWith(relaysUp: up, relaysUnreachable: up == 0 && _relayCheck?.isActive != true));
    });
    _relayCheck = Timer(relayGrace, () {
      if (_signalling == signalling && signalling.relaysConnected == 0) {
        _emit(state.copyWith(relaysUnreachable: true));
      }
    });
    _emit(state.copyWith(relayCount: signalling.relayCount));
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
            connected: {...state.connected}..remove(device),
            problems: {...state.problems}..remove(device)));
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

  /// The link to a device, for tests that play a misbehaving device.
  @visibleForTesting
  PeerLink? linkForTests(String deviceId) => _links[deviceId];

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
    var wasConnected = false;
    link.connected.then((_) {
      _backoff.remove(id);
      if (_links[id] != link) return;
      wasConnected = true;
      _sync?.attach(link);
      final build = link.remoteBuild;
      _emit(state.copyWith(
          connected: {...state.connected, id},
          problems: {...state.problems}..remove(id),
          builds: build == null ? null : {...state.builds, id: build}));
    }, onError: (Object _) {});
    link.closed.then((_) {
      if (_links[id] != link) return;
      _links.remove(id);
      final failure = link.failure;
      final build = link.remoteBuild;
      _emit(state.copyWith(
          builds: build == null ? null : {...state.builds, id: build},
          connected: {...state.connected}..remove(id),
          problems: failure == null
              ? null
              : {
                  ...state.problems,
                  id: SyncProblem(failure,
                      remoteProtocol: link.remoteProtocol, wasConnected: wasConnected)
                }));
      // Another version won't change by trying again; its next announce (after an update) will.
      if (failure != LinkFailure.version &&
          initiator &&
          _signalling == signalling &&
          state.online.contains(id)) {
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
    await _stopSignalling();
    await _sync?.close();
    return super.close();
  }

  /// Starts a new group with this device in it.
  Future<void> createGroup() => _join(PairingCode.generate());

  /// Joins the group of the device that shows `code`. Throws [FormatException] for a bad code, before
  /// anything changes.
  ///
  /// With `clearFirst`, this device's tasks are deleted before it joins, so it brings nothing into
  /// the group and only gets the group's tasks: `clearFirst` empties the task list and returns its
  /// new document, which sync then uses.
  Future<void> joinGroup(String code, {Future<CRDTDocument> Function()? clearFirst}) async {
    final pairing = await PairingCode.parse(code);
    if (clearFirst != null) {
      // No link may carry the old tasks while they are being replaced.
      await _stopSignalling();
      await useDocument(await clearFirst());
    }
    await _join(pairing);
  }

  Future<void> leaveGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairingKey);
    emit(SyncState(
        device: state.device,
        live: state.live,
        relays: state.relays,
        linkRelays: state.linkRelays));
    await _restartSignalling();
  }

  Future<void> _join(PairingCode pairing) async {
    final next = await _stateFor(state.device!, pairing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairingKey, next.code!);
    emit(next.copyWith(live: state.live, relays: state.relays, linkRelays: state.linkRelays));
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
