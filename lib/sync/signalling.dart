import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// How one relay is doing, for the Devices page.
class RelayStatus {
  final Uri url;
  final bool connected;

  /// Whether the relay passed on one of this device's own messages, so it carries the group's
  /// messages. A connected relay that never does drops them, and no device is found through it.
  final bool delivers;

  /// The last reason the relay gave for refusing a message or a subscription, if any.
  final String? problem;

  /// When the relay last passed on one of this device's own messages, in this connection.
  final DateTime? lastEcho;

  /// When the relay last passed on a message from another device of the group, in this run.
  final DateTime? lastFromGroup;

  const RelayStatus(this.url,
      {this.connected = false,
      this.delivers = false,
      this.problem,
      this.lastEcho,
      this.lastFromGroup});
}

/// Finds this group's other devices through Nostr relays, so they can set up a direct connection.
///
/// Only signalling goes through relays, never data, and every message is sealed by Symbolon with the
/// group's keys: a relay sees an ephemeral event under a topic it can't link to the group's secret,
/// signed by a key that changes every app run. Relays pass ephemeral events on to whoever is
/// subscribed and don't store them, so both devices must be online at the same time.
///
/// Everything a relay sends is untrusted: anything that doesn't parse, doesn't open with the group's
/// keys, or is more than two minutes old is dropped without a reply.
class Signalling {
  /// Kind 21059: ephemeral, the kind Symbolon's events use.
  static const _kind = 21059;

  /// Bigger relay messages are dropped before they are parsed. A sealed signal is at most 16 KiB.
  static const _maxMessage = 64 * 1024;
  static const _seenLimit = 1024;

  final SymbolonSignalBox _box;
  final Uint8List _device;
  final RelayConnector _connect;
  final int Function() _now;
  /// The throwaway key events are signed with. A new one on every [checkRelays] round, so a relay
  /// can't link a device's events over time, and a relay's spam filter, which may stop passing on
  /// a key's events to others after many of them, never sees one key for long.
  SymbolonEventSigner _signer = symbolon.eventSigner();
  final List<_Relay> _relays = [];
  final _incoming = StreamController<SymbolonSignal>.broadcast();
  final _relaysUp = StreamController<int>.broadcast();
  final _seen = <String>{};

  /// The ids of this device's latest events, to tell its own messages coming back from a relay.
  final _mine = <String>{};

  /// This app run's session id; other devices address their replies to it.
  final Uint8List session = symbolon.newSession();

  Signalling(
      {required SymbolonGroupKeys group,
      required Uint8List device,
      required List<Uri> relays,
      RelayConnector connect = webSocketRelay,
      int Function()? now})
      : _box = symbolon.signalBox(group),
        _device = device,
        _connect = connect,
        _now = now ?? unixNow {
    for (final url in relays) {
      _relays.add(_Relay(url, this));
    }
  }

  /// The group's relay topic, which the Noise prologue also binds.
  Uint8List get topic => _box.topic;

  /// How many relays this device is connected to now, out of [relayCount].
  int get relaysConnected => _relays.where((r) => r._open).length;
  int get relayCount => _relays.length;

  /// Each relay's state, in the order they were given.
  List<RelayStatus> get relayStatus => [
        for (final r in _relays)
          RelayStatus(r.url,
              connected: r._open,
              delivers: r._delivers,
              problem: r._problem,
              lastEcho: r._lastEcho,
              lastFromGroup: r._lastFromGroup)
      ];

  /// [relaysConnected], each time it changes.
  Stream<int> get relayChanges => _relaysUp.stream;

  void _relayChanged() {
    if (!_relaysUp.isClosed) _relaysUp.add(relaysConnected);
  }

  /// Signals from the group's other devices, to this session or to everyone.
  Stream<SymbolonSignal> get signals => _incoming.stream;

  /// Connects to every relay, subscribes to the group's topic and announces this device.
  void start() {
    for (final relay in _relays) {
      relay.connect();
    }
  }

  /// Sends a signal through every connected relay. Leave out `to` for announce and bye.
  void send(SignalKind kind, {Uint8List? to, List<int> body = const []}) {
    final message = _event(kind, to: to, body: body);
    for (final relay in _relays) {
      relay.send(message);
    }
  }

  /// The relay message [send] would publish, for tests that play the relay.
  @visibleForTesting
  String eventForTests(SignalKind kind) => _event(kind);

  String _event(SignalKind kind, {Uint8List? to, List<int> body = const []}) {
    final now = _now();
    final content = _box.seal(SymbolonSignal(
        kind: kind, createdAt: now, from: session, to: to, device: _device, body: body));
    final event = _signer.signalEvent(now, _box.topic, content);
    try {
      final id = (jsonDecode(event) as Map)['id'];
      if (id is String) {
        _mine.add(id);
        if (_mine.length > 64) _mine.remove(_mine.first);
      }
    } on Object {
      // Only the delivery check needs the id.
    }
    return '["EVENT",$event]';
  }

  /// Checks that every relay still answers, and reconnects the ones that don't. Call it every so
  /// often (`SyncCubit` does on each automatic sync round).
  ///
  /// A relay connection can die without ever closing: after the computer sleeps, or when it changes
  /// network, the socket stays "open" but nothing goes through in either direction, so this device
  /// neither hears nor reaches the others while it still counts the relay as connected. Each check
  /// sends the subscription again, which a relay answers at once (with EOSE). A relay that sent
  /// nothing at all since the previous check is taken as dead and connected again, which also
  /// announces this device on it.
  void checkRelays() {
    _signer = symbolon.eventSigner();
    for (final relay in _relays) {
      relay.check();
    }
  }

  /// Says goodbye and disconnects from every relay.
  Future<void> stop() async {
    send(SignalKind.bye);
    await Future.wait(_relays.map((r) => r.close()));
    await _incoming.close();
    await _relaysUp.close();
  }

  /// How far back the subscription reaches. As wide as the age Symbolon accepts, so a device whose
  /// clock is behind this one's by up to two minutes is still heard; with 10 s, a clock 10 s behind
  /// was enough for the relay to filter out its answers.
  static const _window = 120;

  String _subscription(String id) =>
      '["REQ","$id",${symbolon.signalFilter(_box.topic, _now() - _window)}]';

  void _receive(_Relay relay, Object? message) {
    final id = relay._subscriptionId;
    if (message is! String || message.length > _maxMessage) return;
    final Object? parsed;
    try {
      parsed = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (parsed is! List || parsed.isEmpty) return;
    // Refusals: ["OK", <event id>, false, <reason>], ["CLOSED", <subscription id>, <reason>] and
    // ["NOTICE", <message>]. Kept to show on the Devices page, never acted on.
    final problem = switch (parsed) {
      ['OK', final String eventId, false, final String reason] when _mine.contains(eventId) =>
        reason,
      ['CLOSED', final String sub, final String reason] when sub == id => reason,
      ['NOTICE', final String notice] => notice,
      _ => null,
    };
    if (problem != null) {
      relay._problem = problem.length > 200 ? problem.substring(0, 200) : problem;
      _relayChanged();
      return;
    }
    // ["EVENT", <subscription id>, <event>].
    if (parsed.length != 3 || parsed[0] != 'EVENT' || parsed[1] != id) return;
    final event = parsed[2];
    if (event is! Map || event['kind'] != _kind) return;
    final eventId = event['id'];
    final content = event['content'];
    if (eventId is! String || content is! String) return;
    if (_mine.contains(eventId)) {
      // The relay passed on this device's own message: it carries the group's messages.
      relay._lastEcho = DateTime.now();
      if (!relay._delivers) relay._problem = null;
      relay._delivers = true;
      _relayChanged();
      return;
    }
    // The same event arrives once from every relay: it is passed on once, but each relay that
    // carried it is noted, for the Devices page.
    final fresh = _seen.add(eventId);
    if (_seen.length > _seenLimit) _seen.remove(_seen.first);
    final SymbolonSignal signal;
    try {
      signal = _box.open(content, _now());
    } on Object {
      return;
    }
    if (_same(signal.from, session)) return;
    relay._lastFromGroup = DateTime.now();
    _relayChanged();
    if (!fresh) return;
    if (!_same(signal.to, session) && signal.to.any((b) => b != 0)) return;
    if (!_incoming.isClosed) _incoming.add(signal);
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int unixNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A connection to one relay: text messages in both directions.
abstract class RelayConnection {
  /// Completes once connected, or throws if the relay can't be reached.
  Future<void> get ready;
  Stream<Object?> get messages;
  void add(String message);
  Future<void> close();
}

/// Opens a connection to a relay. Tests pass an in-memory relay instead.
typedef RelayConnector = RelayConnection Function(Uri url);

RelayConnection webSocketRelay(Uri url) => _WebSocketRelay(WebSocketChannel.connect(url));

class _WebSocketRelay implements RelayConnection {
  final WebSocketChannel _channel;

  _WebSocketRelay(this._channel);

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  void add(String message) => _channel.sink.add(message);

  @override
  Future<void> close() async => _channel.sink.close();
}

/// One relay: connects, subscribes, and reconnects with backoff when the connection drops.
class _Relay {
  static const _maxBackoff = Duration(minutes: 1);

  final Uri url;
  final Signalling owner;
  RelayConnection? _channel;
  StreamSubscription<Object?>? _listening;
  Timer? _retry;
  Duration _backoff = const Duration(seconds: 1);
  bool _closed = false;
  bool _open = false;
  String? _subscriptionId;
  bool _delivers = false;
  DateTime? _lastEcho;
  DateTime? _lastFromGroup;
  String? _problem;

  /// True from a liveness probe until the relay sends anything.
  bool _awaitingReply = false;

  _Relay(this.url, this.owner);

  Future<void> connect() async {
    if (_closed) return;
    final id = _randomId();
    final RelayConnection channel;
    try {
      channel = owner._connect(url);
      _channel = channel;
      await channel.ready;
    } on Object {
      _scheduleRetry();
      return;
    }
    if (_closed) {
      await channel.close();
      return;
    }
    _open = true;
    _subscriptionId = id;
    _awaitingReply = false;
    owner._relayChanged();
    _backoff = const Duration(seconds: 1);
    _listening = channel.messages.listen((m) {
      _awaitingReply = false;
      owner._receive(this, m);
    }, onDone: _dropped, onError: (Object _) => _dropped(), cancelOnError: true);
    channel.add(owner._subscription(id));
    // Announce on every (re)connect, so devices that came online meanwhile find this one.
    channel.add(owner._event(SignalKind.announce));
  }

  void send(String message) {
    if (_open) _channel?.add(message);
  }

  /// See [Signalling.checkRelays].
  void check() {
    final id = _subscriptionId;
    if (_closed || !_open || id == null) return;
    if (_awaitingReply) {
      // Silent since the last probe: the socket is dead even though it never closed.
      final channel = _channel;
      _dropped();
      _channel = null;
      unawaited(channel?.close().catchError((Object _) {}));
      return;
    }
    _awaitingReply = true;
    _channel?.add(owner._subscription(id));
  }

  void _dropped() {
    if (!_open && _retry?.isActive == true) return;
    _open = false;
    _delivers = false;
    _lastEcho = null;
    _subscriptionId = null;
    owner._relayChanged();
    _listening?.cancel();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(_backoff, connect);
    _backoff = _backoff * 2 > _maxBackoff ? _maxBackoff : _backoff * 2;
  }

  Future<void> close() async {
    _closed = true;
    _open = false;
    _retry?.cancel();
    await _listening?.cancel();
    await _channel?.close();
  }
}

final _random = Random.secure();

String _randomId() =>
    List.generate(8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
