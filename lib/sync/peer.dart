import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';

import 'pairing.dart';

/// A direct, ordered and reliable channel to one other device, before any encryption. The offer and
/// answer travel through [Signalling]; everything after goes straight between the two devices.
abstract class PeerTransport {
  /// This side's offer, with all its candidates in it.
  Future<String> offer();

  /// The answer to the other side's [offer], with all of this side's candidates in it.
  Future<String> answer(String offer);

  /// Takes the other side's answer to this side's [offer].
  Future<void> accept(String answer);

  /// Completes once messages can be sent.
  Future<void> get open;

  /// Messages from the other side. Done when the channel closes.
  Stream<Uint8List> get messages;

  void send(Uint8List message);
  Future<void> close();
}

/// The version of what two devices say to each other: the offer and answer, the framing on the
/// channel and the sync messages inside it. Devices sync only with the same version, and say so
/// on the Devices page when they can't.
///
/// 1: before versions were sent, the offer and answer were the bare SDP.
/// 2: the offer and answer carry the version; messages on the channel are numbered ([Reorder]).
const syncProtocol = 2;

/// Why a link closed before or after it connected, to show on the Devices page.
enum LinkFailure {
  /// No direct connection within the time limit.
  timeout,

  /// The direct connection couldn't be set up, or broke.
  transport,

  /// The encryption handshake failed: another key, another group, or a broken message.
  handshake,

  /// The other device runs another version of the app; see [PeerLink.remoteProtocol].
  version,

  /// The other device sent something this one can't read.
  protocol,
}

/// The offer or answer as signalled: the version, then the SDP.
List<int> _envelope(String sdp) => utf8.encode(jsonEncode({'v': syncProtocol, 'sdp': sdp}));

/// The version and SDP in a signalled offer or answer. A bare SDP is from version 1. Throws
/// [FormatException] for anything else.
({int version, String? sdp}) _openEnvelope(List<int> body) {
  final text = utf8.decode(body);
  if (text.startsWith('v=')) return (version: 1, sdp: null);
  final parsed = jsonDecode(text);
  if (parsed is! Map || parsed['v'] is! int) throw const FormatException('Not an envelope');
  final version = parsed['v'] as int;
  final sdp = parsed['sdp'];
  if (version == syncProtocol && sdp is! String) throw const FormatException('No SDP');
  return (version: version, sdp: version == syncProtocol ? sdp as String : null);
}

/// Makes a fresh [PeerTransport]. Tests pass an in-memory one.
typedef PeerTransportFactory = Future<PeerTransport> Function();

/// A link to one of the group's devices: sets up the [PeerTransport], runs the Noise handshake over
/// it, and then carries encrypted messages.
///
/// The initiator (see [Symbolon.initiates]) makes the offer and writes the first handshake message;
/// the IK pattern needs it to know the responder's key, which it has from the responder's announce.
/// The responder accepts only the device that the offer's signal named.
///
/// Anything unexpected closes the link: a message that is too big, doesn't decrypt or arrives out of
/// turn, a handshake from another key, or no channel within `timeout` ([connectTimeout] unless set). A closed link is never
/// reused; the owner makes a new one.
class PeerLink {
  static const connectTimeout = Duration(seconds: 30);

  /// Noise messages are at most 65535 bytes; anything bigger isn't one.
  static const maxMessage = 65535;

  final Uint8List remoteDevice;
  final Uint8List remoteSession;
  final bool initiator;
  final PeerTransport _transport;
  final DeviceIdentity _device;
  final GroupKeys _keys;
  final List<int> _prologue;
  final void Function(SignalKind kind, List<int> body) _signal;

  final _received = StreamController<Uint8List>.broadcast();
  final _connected = Completer<void>();
  final _closed = Completer<void>();
  StreamSubscription<Uint8List>? _listening;
  Timer? _timeout;
  SymbolonHandshake? _handshake;
  SymbolonChannel? _channel;
  LinkFailure? _failure;
  int? _remoteProtocol;

  /// Why the link closed, once it has; null when it was closed on purpose.
  LinkFailure? get failure => _failure;

  /// The other device's [syncProtocol], once its offer or answer has arrived.
  int? get remoteProtocol => _remoteProtocol;

  /// `signal` sends an offer or answer to [remoteSession].
  PeerLink({
    required this.remoteDevice,
    required this.remoteSession,
    required this.initiator,
    required PeerTransport transport,
    required DeviceIdentity device,
    required GroupKeys keys,
    required List<int> prologue,
    required void Function(SignalKind kind, List<int> body) signal,
    Duration timeout = connectTimeout,
  })  : _transport = transport,
        _device = device,
        _keys = keys,
        _prologue = prologue,
        _signal = signal {
    _timeout = Timer(timeout, () => fail(LinkFailure.timeout));
    _listening =
        transport.messages.listen(_message, onDone: () => fail(LinkFailure.transport));
    transport.open.then((_) => _opened(), onError: (Object _) => fail(LinkFailure.transport));
  }

  /// Completes once the handshake is done and [send] can be used.
  Future<void> get connected => _connected.future;

  /// Completes once the link is closed, for whatever reason.
  Future<void> get closed => _closed.future;

  bool get isConnected => _channel != null && !isClosed;
  bool get isClosed => _closed.isCompleted;

  /// Decrypted messages from the other device. Still untrusted: parse them strictly.
  Stream<Uint8List> get received => _received.stream;

  /// Initiator only: makes the offer and sends it.
  Future<void> start() async {
    assert(initiator);
    try {
      final offer = await _transport.offer();
      if (!isClosed) _signal(SignalKind.offer, _envelope(offer));
    } on Object {
      await fail(LinkFailure.transport);
    }
  }

  /// Handles the offer (responder) or answer (initiator) from [remoteSession].
  Future<void> signalled(SymbolonSignal signal) async {
    if (isClosed) return;
    final ({int version, String? sdp}) opened;
    try {
      opened = _openEnvelope(signal.body);
    } on Object {
      await fail(LinkFailure.protocol);
      return;
    }
    _remoteProtocol = opened.version;
    final sdp = opened.sdp;
    if (sdp == null) {
      await fail(LinkFailure.version);
      return;
    }
    try {
      if (signal.kind == SignalKind.offer && !initiator) {
        final answer = await _transport.answer(sdp);
        if (!isClosed) _signal(SignalKind.answer, _envelope(answer));
      } else if (signal.kind == SignalKind.answer && initiator) {
        await _transport.accept(sdp);
      } else {
        await fail(LinkFailure.protocol);
      }
    } on Object {
      await fail(LinkFailure.transport);
    }
  }

  void _opened() {
    if (isClosed || !initiator) return;
    _guard(() {
      final handshake = symbolon.initiator(_device.key, remoteDevice, _keys.inner, _prologue);
      _handshake = handshake;
      _transport.send(handshake.writeMessage(const []));
    });
  }

  void _message(Uint8List message) {
    if (isClosed) return;
    if (message.length > maxMessage) {
      fail(LinkFailure.protocol);
      return;
    }
    _guard(() {
      final channel = _channel;
      if (channel != null) {
        final plaintext = channel.decrypt(message);
        if (!_received.isClosed) _received.add(plaintext);
        return;
      }
      var handshake = _handshake;
      if (handshake == null) {
        // Only the responder gets a message before it has a handshake: the initiator's first.
        if (initiator) throw StateError('Out of turn');
        handshake = symbolon.responder(_device.key, _keys.inner, _prologue);
        _handshake = handshake;
        handshake.readMessage(message);
        if (!_same(handshake.remoteStatic, remoteDevice)) throw StateError('Another device');
        _transport.send(handshake.writeMessage(const []));
      } else {
        if (!initiator) throw StateError('Out of turn');
        handshake.readMessage(message);
      }
      if (!handshake.isFinished) throw StateError('Handshake not finished');
      _channel = handshake.intoChannel();
      _handshake = null;
      _timeout?.cancel();
      _connected.complete();
    });
  }

  /// Encrypts and sends one message. At most [Symbolon.maxPlaintext] bytes.
  void send(List<int> plaintext) {
    final channel = _channel;
    if (channel == null || isClosed) throw StateError('Not connected');
    _guard(() => _transport.send(channel.encrypt(plaintext)));
  }

  /// Anything that throws here is the handshake or a message that doesn't decrypt.
  void _guard(void Function() action) {
    try {
      action();
    } on Object {
      fail(LinkFailure.handshake);
    }
  }

  /// Closes the link because of `reason`, which [failure] then tells.
  Future<void> fail(LinkFailure reason) {
    if (!isClosed) _failure = reason;
    return close();
  }

  Future<void> close() async {
    if (isClosed) return;
    _closed.complete();
    _timeout?.cancel();
    _channel = null;
    _handshake = null;
    if (!_connected.isCompleted) _connected.completeError(StateError('Closed'));
    // Nobody may be waiting on connected; don't let its error go unhandled.
    _connected.future.ignore();
    await _listening?.cancel();
    await _received.close();
    await _transport.close();
  }
}

bool _same(List<int>? a, List<int> b) {
  if (a == null || a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < b.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// [PeerTransport] over a WebRTC data channel, with flutter_webrtc on every platform.
///
/// Every message carries a 4-byte sequence number in front, and messages are passed on in that
/// order. The channel itself is ordered, but in Safari the web plugin hands over each message as a
/// Blob and reads it asynchronously, so two messages can come out swapped. Noise needs them in
/// order, so without this a swap broke the link.
///
/// Both sides open the same pre-negotiated, ordered and reliable channel, so neither waits for the
/// other to announce one. Candidates are gathered before the offer or answer is sent, so each side
/// sends exactly one signal. With no ICE servers only host candidates exist, which is enough on one
/// network.
class WebRtcTransport implements PeerTransport {
  static const _gatherTimeout = Duration(seconds: 5);

  /// How many messages may wait for an earlier one before the channel counts as broken.
  static const _maxWaiting = 256;

  final RTCPeerConnection _pc;
  final RTCDataChannel _dc;
  final _messages = StreamController<Uint8List>();
  final _open = Completer<void>();
  final _gathered = <Completer<void>>[];
  var _sent = 0;
  final _reorder = Reorder(_maxWaiting);

  WebRtcTransport._(this._pc, this._dc) {
    _open.future.ignore();
    _dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && !_open.isCompleted) _open.complete();
      if (s == RTCDataChannelState.RTCDataChannelClosed) _ended();
    };
    _dc.onMessage = (m) {
      // Only binary messages are ours.
      if (!m.isBinary || _messages.isClosed) return;
      final ready = _reorder.take(m.binary);
      if (ready == null) {
        close();
        return;
      }
      for (final message in ready) {
        _messages.add(message);
      }
    };
    _pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        for (final c in _gathered) {
          if (!c.isCompleted) c.complete();
        }
      }
    };
    _pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _ended();
      }
    };
  }

  /// A transport that uses `iceServers` (STUN or TURN URLs) besides host candidates.
  static Future<PeerTransport> create(List<Uri> iceServers) async {
    final pc = await createPeerConnection({
      'iceServers': [
        for (final s in iceServers) {'urls': s.toString()}
      ],
    });
    final dc = await pc.createDataChannel(
        'bringmeback',
        RTCDataChannelInit()
          ..negotiated = true
          ..id = 0
          ..ordered = true
          ..binaryType = 'binary');
    return WebRtcTransport._(pc, dc);
  }

  Future<String> _localDescription() async {
    final gathered = Completer<void>();
    _gathered.add(gathered);
    if (await _pc.getIceGatheringState() != RTCIceGatheringState.RTCIceGatheringStateComplete) {
      // Send what has been gathered by then; slow STUN servers shouldn't hold up the rest.
      await gathered.future.timeout(_gatherTimeout, onTimeout: () {});
    }
    final description = await _pc.getLocalDescription();
    return description!.sdp!;
  }

  @override
  Future<String> offer() async {
    await _pc.setLocalDescription(await _pc.createOffer());
    return _localDescription();
  }

  @override
  Future<String> answer(String offer) async {
    await _pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
    await _pc.setLocalDescription(await _pc.createAnswer());
    return _localDescription();
  }

  @override
  Future<void> accept(String answer) =>
      _pc.setRemoteDescription(RTCSessionDescription(answer, 'answer'));

  @override
  Future<void> get open => _open.future;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  void send(Uint8List message) =>
      _dc.send(RTCDataChannelMessage.fromBinary(Reorder.frame(_sent++, message)));

  void _ended() {
    if (!_open.isCompleted) _open.completeError(StateError('Closed'));
    if (!_messages.isClosed) _messages.close();
  }

  @override
  Future<void> close() async {
    _ended();
    await _dc.close();
    await _pc.close();
    await _pc.dispose();
  }
}

/// Puts a channel's messages back in the order they were sent, by the sequence number in front of
/// each ([frame]).
class Reorder {
  final int maxWaiting;
  final _waiting = <int, Uint8List>{};
  var _next = 0;

  Reorder(this.maxWaiting);

  /// `message` with sequence number `seq` in front.
  static Uint8List frame(int seq, Uint8List message) {
    final out = Uint8List(message.length + 4);
    ByteData.sublistView(out).setUint32(0, seq & 0xffffffff);
    out.setRange(4, out.length, message);
    return out;
  }

  /// Takes one framed message and returns the messages that are now next in order, which may be
  /// none. Returns null when the message can't be right: too short, a number already taken, or too
  /// many messages waiting for a missing one.
  List<Uint8List>? take(Uint8List framed) {
    if (framed.length < 4) return null;
    final seq = ByteData.sublistView(framed).getUint32(0);
    final ahead = (seq - _next) & 0xffffffff;
    if (ahead >= maxWaiting || _waiting.containsKey(seq)) return null;
    _waiting[seq] = Uint8List.sublistView(framed, 4);
    final ready = <Uint8List>[];
    for (var message = _waiting.remove(_next); message != null; message = _waiting.remove(_next)) {
      ready.add(message);
      _next = (_next + 1) & 0xffffffff;
    }
    return ready;
  }
}
