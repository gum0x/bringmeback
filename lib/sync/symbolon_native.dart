import 'dart:typed_data';

import '../src/rust/api/symbolon.dart' as rust;
import '../src/rust/frb_generated.dart';
import 'symbolon.dart';

Future<Symbolon> load() async {
  await RustLib.init();
  return _Native();
}

class _Native implements Symbolon {
  @override
  SymbolonGroupKeys groupKeys(List<int> context, List<int> secret) =>
      _GroupKeys(rust.GroupKeys(context: context, secret: secret));

  @override
  SymbolonDeviceKey generateDeviceKey() => _DeviceKey(rust.DeviceKey.generate());

  @override
  SymbolonDeviceKey deviceKeyFromPrivate(List<int> privateKey) =>
      _DeviceKey(rust.DeviceKey.fromPrivate(privateKey: privateKey));

  @override
  bool initiates(List<int> localPublic, List<int> remotePublic) =>
      rust.initiates(localPublic: localPublic, remotePublic: remotePublic);

  @override
  SymbolonHandshake initiator(SymbolonDeviceKey device, List<int> remotePublic,
          SymbolonGroupKeys group, List<int> prologue) =>
      _Handshake(rust.NoiseHandshake.initiator(
          device: (device as _DeviceKey).inner,
          remotePublic: remotePublic,
          group: (group as _GroupKeys).inner,
          prologue: prologue));

  @override
  SymbolonHandshake responder(
          SymbolonDeviceKey device, SymbolonGroupKeys group, List<int> prologue) =>
      _Handshake(rust.NoiseHandshake.responder(
          device: (device as _DeviceKey).inner,
          group: (group as _GroupKeys).inner,
          prologue: prologue));

  @override
  int get maxPlaintext => rust.SecureChannel.maxPlaintext().toInt();
}

class _GroupKeys implements SymbolonGroupKeys {
  final rust.GroupKeys inner;

  _GroupKeys(this.inner);

  @override
  Uint8List fingerprint() => inner.fingerprint();

  @override
  Uint8List topic(List<int> label) => inner.topic(label: label);

  @override
  Uint8List seal(List<int> plaintext, List<int> aad) => inner.seal(plaintext: plaintext, aad: aad);

  @override
  Uint8List open(List<int> sealed, List<int> aad) => inner.open(sealed: sealed, aad: aad);
}

class _DeviceKey implements SymbolonDeviceKey {
  final rust.DeviceKey inner;
  @override
  final Uint8List publicKey;

  _DeviceKey(this.inner) : publicKey = inner.publicKey();

  @override
  Uint8List privateKey() => inner.privateKey();
}

class _Handshake implements SymbolonHandshake {
  final rust.NoiseHandshake inner;

  _Handshake(this.inner);

  @override
  Uint8List writeMessage(List<int> payload) => inner.writeMessage(payload: payload);

  @override
  Uint8List readMessage(List<int> message) => inner.readMessage(message: message);

  @override
  bool get isFinished => inner.isFinished();

  @override
  Uint8List? get remoteStatic => inner.remoteStatic();

  @override
  SymbolonChannel intoChannel() => _Channel(inner.intoChannel());
}

class _Channel implements SymbolonChannel {
  final rust.SecureChannel inner;

  _Channel(this.inner);

  @override
  Uint8List encrypt(List<int> plaintext) => inner.encrypt(plaintext: plaintext);

  @override
  Uint8List decrypt(List<int> ciphertext) => inner.decrypt(ciphertext: ciphertext);

  @override
  bool get isOpen => inner.isOpen();
}
