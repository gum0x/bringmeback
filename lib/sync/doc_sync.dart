import 'dart:async';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'peer.dart';

/// Keeps the task document the same on this device and the group's devices it has a link to.
///
/// When a link connects, each side sends its version vector, and the other answers with every change
/// the vector doesn't cover. After that, each change made here goes to every link as it happens.
/// After taking in changes, a side sends its vector again, so each side knows when the other has
/// caught up: a link is in sync while both vectors are the same. Changes travel only inside the
/// links' Noise channel.
///
/// Wire format, inside each Noise message: one flags byte (bit 0 set when more fragments follow) and
/// the fragment. Fragments join into one message: a type byte, then
/// - [_vector]: the sender's version vector ([VersionVector.toBytes]);
/// - [_changes]: changes, as crdt_lf's change codec writes them.
///
/// Every byte from a link is untrusted, paired or not: messages over [maxMessage], unknown types,
/// and anything that doesn't decode close the link. The document itself drops changes it can't
/// apply, and the task list reads fields defensively.
class DocumentSync {
  static const _vector = 1;
  static const _changes = 2;
  static const _more = 1;

  /// The largest message after joining fragments.
  static const maxMessage = 16 * 1024 * 1024;

  /// Changes go out in batches of about this many bytes, so one message never gets near [maxMessage].
  static const _batchBytes = 1024 * 1024;

  final CRDTDocument _doc;
  final _links = <PeerLink, _Incoming>{};
  late final StreamSubscription<Change> _local;
  final _inSync = StreamController<Set<PeerLink>>.broadcast();
  Set<PeerLink> _lastInSync = const {};

  DocumentSync(this._doc) {
    _local = _doc.localChanges.listen((change) {
      for (final link in _links.keys.toList()) {
        _send(link, _changes, ChangeCodec.encodeBlobs([change.toBytes()]));
      }
      _status();
    });
  }

  /// The links whose device has the same changes as this one, each time that may have changed.
  /// A change made here takes every link out of sync until its device confirms it.
  Stream<Set<PeerLink>> get inSync => _inSync.stream;

  /// The links in sync now. See [inSync].
  Set<PeerLink> get linksInSync => _lastInSync;

  void _status() {
    final ours = _doc.getVersionVector();
    final now = {
      for (final MapEntry(key: link, value: incoming) in _links.entries)
        if (incoming.remote case final remote?)
          if (remote.isStrictlyNewerOrEqualThan(ours) && ours.isStrictlyNewerOrEqualThan(remote))
            link,
    };
    _lastInSync = now;
    if (!_inSync.isClosed) _inSync.add(now);
  }

  /// Syncs over `link` from now until it closes. Call it once the link is connected.
  void attach(PeerLink link) {
    if (link.isClosed || _links.containsKey(link)) return;
    final incoming = _Incoming();
    _links[link] = incoming;
    incoming.subscription =
        link.received.listen((fragment) => _fragment(link, fragment), onDone: () => _drop(link));
    link.closed.then((_) => _drop(link));
    _send(link, _vector, _doc.getVersionVector().toBytes());
  }

  void _drop(PeerLink link) {
    final incoming = _links.remove(link);
    if (incoming == null) return;
    incoming.subscription?.cancel();
    _status();
  }

  void _fragment(PeerLink link, Uint8List fragment) {
    final incoming = _links[link];
    if (incoming == null) return;
    if (fragment.isEmpty || fragment[0] & ~_more != 0) return _reject(link);
    final data = Uint8List.sublistView(fragment, 1);
    if (incoming.size + data.length > maxMessage) return _reject(link);
    incoming.parts.add(data);
    incoming.size += data.length;
    if (fragment[0] & _more != 0) return;
    final message = incoming.take();
    try {
      _message(link, message);
    } on Object {
      _reject(link);
    }
  }

  void _message(PeerLink link, Uint8List message) {
    if (message.isEmpty) throw const FormatException('Empty message');
    final body = Uint8List.sublistView(message, 1);
    switch (message[0]) {
      case _vector:
        final remote = VersionVector.fromBytes(body);
        _sendChanges(link, _doc.exportChangesNewerThan(remote));
        _links[link]?.remote = remote.mutable();
        _status();
      case _changes:
        final changes = [for (final blob in ChangeCodec.decodeBlobs(body)) Change.fromBytes(blob)];
        _doc.importChanges(changes, origin: link);
        // The sender has what it sent.
        final remote = _links[link]?.remote;
        if (remote != null) {
          for (final change in changes) {
            remote.update(change.id.peerId, change.id.hlc);
          }
        }
        // Tell every device what this one has now: the sender learns it caught this one up, and the
        // others answer with anything that is still missing on either side.
        final vector = _doc.getVersionVector().toBytes();
        for (final other in _links.keys.toList()) {
          _send(other, _vector, vector);
        }
        _status();
      default:
        throw const FormatException('Unknown message');
    }
  }

  void _sendChanges(PeerLink link, List<Change> changes) {
    var batch = <Uint8List>[];
    var size = 0;
    for (final change in changes) {
      final bytes = change.toBytes();
      if (batch.isNotEmpty && size + bytes.length > _batchBytes) {
        _send(link, _changes, ChangeCodec.encodeBlobs(batch));
        batch = [];
        size = 0;
      }
      batch.add(bytes);
      size += bytes.length;
    }
    if (batch.isNotEmpty) _send(link, _changes, ChangeCodec.encodeBlobs(batch));
  }

  /// Sends one message as as many fragments as the channel needs.
  void _send(PeerLink link, int type, Uint8List body) {
    if (!link.isConnected) return;
    final message = Uint8List(body.length + 1)
      ..[0] = type
      ..setRange(1, body.length + 1, body);
    final room = symbolon.maxPlaintext - 1;
    for (var at = 0; at < message.length; at += room) {
      final end = at + room < message.length ? at + room : message.length;
      final more = end < message.length;
      link.send(Uint8List(end - at + 1)
        ..[0] = more ? _more : 0
        ..setRange(1, end - at + 1, message, at));
      if (!more) break;
    }
  }

  void _reject(PeerLink link) {
    _drop(link);
    link.fail(LinkFailure.protocol);
  }

  Future<void> close() async {
    await _local.cancel();
    for (final incoming in _links.values) {
      await incoming.subscription?.cancel();
    }
    _links.clear();
    await _inSync.close();
  }
}

/// The fragments of the message a link is in the middle of sending.
class _Incoming {
  StreamSubscription<Uint8List>? subscription;

  /// The other device's version vector, as it last said.
  VersionVector? remote;
  final parts = <Uint8List>[];
  var size = 0;

  Uint8List take() {
    final out = Uint8List(size);
    var at = 0;
    for (final p in parts) {
      out.setRange(at, at + p.length, p);
      at += p.length;
    }
    parts.clear();
    size = 0;
    return out;
  }
}
