import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../src/rust/api/symbolon.dart' as symbolon;

/// Devices pair by sharing one 32-byte group secret, shown as a QR code or a text code. Symbolon
/// (github.com/common-sec/symbolon) derives every group key from it: the seal key for signalling messages
/// on public relays, the topic key that names the relay topic, the Noise PSK that proves group membership,
/// and the fingerprint people compare. Each device also has its own X25519 key for the Noise handshake.
/// Data between devices goes through the Noise channel, not the group keys.

const _codePrefix = 'bmb1-';
const _secretLength = 32;
const _checkLength = 2;
const _salt = 'bmb/v1';

final Random _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _unb64(String text) => base64Url.decode(base64Url.normalize(text));

/// Only for the typo check in the pairing code, which needs no secrecy. Group keys come from Symbolon.
Future<Uint8List> _derive(List<int> secret, String info, [int length = 32]) async {
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
      secretKey: SecretKey(secret), nonce: utf8.encode(_salt), info: utf8.encode(info));
  return Uint8List.fromList(await key.extractBytes());
}

/// The group secret and the pairing code that carries it.
class PairingCode {
  final Uint8List secret;

  PairingCode._(this.secret);

  factory PairingCode.generate() => PairingCode._(randomBytes(_secretLength));

  /// Parses a code typed, pasted or scanned on another device. Throws [FormatException].
  static Future<PairingCode> parse(String text) async {
    final trimmed = text.trim();
    if (!trimmed.startsWith(_codePrefix)) {
      throw FormatException('This is not a bringmeback pairing code.');
    }
    final Uint8List bytes;
    try {
      bytes = _unb64(trimmed.substring(_codePrefix.length));
    } on Object {
      throw FormatException('The pairing code is damaged.');
    }
    if (bytes.length != _secretLength + _checkLength) {
      throw FormatException('The pairing code is incomplete.');
    }
    final secret = Uint8List.sublistView(bytes, 0, _secretLength);
    final check = await _derive(secret, 'check', _checkLength);
    if (check[0] != bytes[_secretLength] || check[1] != bytes[_secretLength + 1]) {
      throw FormatException('The pairing code has a typo.');
    }
    return PairingCode._(Uint8List.fromList(secret));
  }

  /// The text form, also what the QR code holds. The last bytes are a check that catches typos.
  Future<String> encode() async =>
      _codePrefix + _b64([...secret, ...await _derive(secret, 'check', _checkLength)]);

  /// Every key of the group, derived by Symbolon. Call [loadSymbolon] first.
  GroupKeys deriveKeys() => GroupKeys._(symbolon.GroupKeys(secret: secret));
}

/// Six bytes as "1a2b-3c4d-5e6f", short enough to compare by eye.
String _fingerprint(List<int> bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join('-');
}

/// The group's keys. They stay inside Symbolon; only results come out.
class GroupKeys {
  final symbolon.GroupKeys inner;

  GroupKeys._(this.inner);

  /// Shown on every device so people can check they joined the same group.
  String get fingerprint => _fingerprint(inner.fingerprint());

  /// A relay topic for `label` that only group members can compute.
  String topic(String label) => _b64(inner.topic(label: utf8.encode(label)));

  /// Encrypts a signalling message for the relays. `aad` is authenticated but not encrypted, for context
  /// such as the message type, so a payload can't be replayed as something else.
  Uint8List seal(List<int> plaintext, {List<int> aad = const []}) =>
      inner.seal(plaintext: plaintext, aad: aad);

  /// Decrypts a [seal]ed buffer. Throws if it was altered or sealed with another key or `aad`.
  /// The result is still untrusted peer data and must be validated by the caller.
  Uint8List open(List<int> sealed, {List<int> aad = const []}) =>
      inner.open(sealed: sealed, aad: aad);
}

/// This device's static X25519 key for the Noise handshake. The private key is stored with the app's
/// other data. Older versions stored an X25519 seed, which is the same 32 bytes.
class DeviceIdentity {
  final symbolon.DeviceKey key;
  final Uint8List publicKey;

  DeviceIdentity._(this.key) : publicKey = key.publicKey();

  static DeviceIdentity fromPrivate(List<int> privateKey) {
    if (privateKey.length != 32) throw FormatException('Invalid device key');
    return DeviceIdentity._(symbolon.DeviceKey.fromPrivate(privateKey: privateKey));
  }

  static DeviceIdentity generate() => DeviceIdentity._(symbolon.DeviceKey.generate());

  static DeviceIdentity decode(String text) => fromPrivate(_unb64(text));

  String encode() => _b64(key.privateKey());

  /// The public key as text, how other devices name this one.
  String get id => _b64(publicKey);
}
