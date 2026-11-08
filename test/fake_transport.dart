import 'dart:async';
import 'dart:typed_data';

import 'package:bringmeback/sync/peer.dart';

/// A network in memory: an offer names the transport that made it, an answer joins the two, and
/// messages go between them in order, like an ordered, reliable data channel.
class FakeNetwork {
  final _offers = <String, FakeTransport>{};
  final transports = <FakeTransport>[];
  var _next = 0;

  /// Applied to every message on its way, for tests that play an attacker on the path.
  Uint8List Function(Uint8List message)? onTheWay;

  Future<PeerTransport> create() async {
    final t = FakeTransport(this);
    transports.add(t);
    return t;
  }
}

class FakeTransport implements PeerTransport {
  final FakeNetwork network;
  final _messages = StreamController<Uint8List>();
  final _open = Completer<void>();
  FakeTransport? _peer;
  String? _offer;
  bool closed = false;

  FakeTransport(this.network) {
    _open.future.ignore();
  }

  @override
  Future<String> offer() async {
    final id = 'offer-${network._next++}';
    _offer = id;
    network._offers[id] = this;
    return id;
  }

  @override
  Future<String> answer(String offer) async {
    final remote = network._offers.remove(offer);
    if (remote == null) throw StateError('Unknown offer');
    _peer = remote;
    remote._peer = this;
    return 'answer-$offer';
  }

  @override
  Future<void> accept(String answer) async {
    if (_peer == null || answer != 'answer-$_offer') throw StateError('Wrong answer');
    _peer!._open.complete();
    _open.complete();
  }

  @override
  Future<void> get open => _open.future;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  void send(Uint8List message) {
    final peer = _peer;
    if (closed || peer == null) throw StateError('Closed');
    final delivered = network.onTheWay?.call(message) ?? message;
    scheduleMicrotask(() {
      if (!peer._messages.isClosed) peer._messages.add(Uint8List.fromList(delivered));
    });
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_open.isCompleted) _open.completeError(StateError('Closed'));
    await _messages.close();
    // A data channel closes at both ends.
    await _peer?.close();
  }
}
