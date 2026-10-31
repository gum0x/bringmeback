import 'dart:typed_data';

import 'symbolon_native.dart' if (dart.library.js_interop) 'symbolon_web.dart' as backend;

/// Symbolon (github.com/common-sec/symbolon), the library that does bringmeback's sync cryptography.
/// Desktop and phone builds call its Rust code through flutter_rust_bridge; the web build calls its
/// JavaScript binding. Both run the same Rust code, so devices agree whatever they run on.
abstract class Symbolon {
  /// Every key of a group. `context` names the app and protocol version.
  SymbolonGroupKeys groupKeys(List<int> context, List<int> secret);

  SymbolonDeviceKey generateDeviceKey();

  SymbolonDeviceKey deviceKeyFromPrivate(List<int> privateKey);

  /// Whether the device with `localPublic` starts the handshake.
  bool initiates(List<int> localPublic, List<int> remotePublic);

  SymbolonHandshake initiator(SymbolonDeviceKey device, List<int> remotePublic,
      SymbolonGroupKeys group, List<int> prologue);

  SymbolonHandshake responder(SymbolonDeviceKey device, SymbolonGroupKeys group, List<int> prologue);

  /// The largest plaintext one channel message can carry.
  int get maxPlaintext;
}

abstract class SymbolonGroupKeys {
  Uint8List fingerprint();
  Uint8List topic(List<int> label);
  Uint8List seal(List<int> plaintext, List<int> aad);
  Uint8List open(List<int> sealed, List<int> aad);
}

abstract class SymbolonDeviceKey {
  Uint8List get publicKey;

  /// Only for storing the key on this device.
  Uint8List privateKey();
}

/// The Noise IKpsk1 handshake. Any error ends it.
abstract class SymbolonHandshake {
  Uint8List writeMessage(List<int> payload);
  Uint8List readMessage(List<int> message);
  bool get isFinished;

  /// The other device's public key, once its first message has been read.
  Uint8List? get remoteStatic;

  /// Ends the handshake; it can't be used afterwards.
  SymbolonChannel intoChannel();
}

/// Encrypted messages after the handshake. Any rejected message closes it.
abstract class SymbolonChannel {
  Uint8List encrypt(List<int> plaintext);
  Uint8List decrypt(List<int> ciphertext);
  bool get isOpen;
}

Future<Symbolon>? _loading;
Symbolon? _loaded;

/// Loads Symbolon once. Safe to call from anywhere that needs it.
Future<Symbolon> loadSymbolon() => _loading ??= backend.load().then((s) => _loaded = s);

/// Symbolon after [loadSymbolon] has finished.
Symbolon get symbolon =>
    _loaded ?? (throw StateError('Call loadSymbolon() before using Symbolon.'));
