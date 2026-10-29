import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Devices pair by sharing one 32-byte group secret, shown as a QR code or a text code.
/// Every group key is derived from it, as in secure-share:
///   group secret  --HKDF-->  signalling password (encrypts offers and answers on public relays)
///                 --HKDF-->  group key (AES-256-GCM, seals signalling messages on the relays)
///                 --HKDF-->  topic key (HMAC, names the relay topic without revealing the group)
///                 --HKDF-->  Noise PSK (proves group membership in the Noise handshake)
///                 --HKDF-->  group fingerprint (shown on both devices so people can compare them)
/// Each device also has its own X25519 static key for Noise (Noise_IKpsk1_25519_ChaChaPoly_SHA256, the
/// suite secure-share is moving to). Data between devices goes through the Noise channel, not the group key.

const _codePrefix = 'bmb1-';
const _secretLength = 32;
const _checkLength = 2;
const _salt = 'bmb/v1';
const _nonceLength = 12;
const _macLength = 16;

final Random _random = Random.secure();
final _aes = AesGcm.with256bits();
final _x25519 = X25519();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _unb64(String text) => base64Url.decode(base64Url.normalize(text));

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

  Future<GroupKeys> deriveKeys() async => GroupKeys(
        signalingPassword: _b64(await _derive(secret, 'signaling')),
        groupKey: SecretKey(await _derive(secret, 'group')),
        topicKey: SecretKey(await _derive(secret, 'topic')),
        noisePsk: await _derive(secret, 'noise-psk'),
        fingerprint: _fingerprint(await _derive(secret, 'fingerprint', 6)),
      );
}

/// Six bytes as "1a2b-3c4d-5e6f", short enough to compare by eye.
String _fingerprint(List<int> bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join('-');
}

class GroupKeys {
  final String signalingPassword;
  final SecretKey groupKey;
  final SecretKey topicKey;
  final Uint8List noisePsk;
  final String fingerprint;

  GroupKeys(
      {required this.signalingPassword,
      required this.groupKey,
      required this.topicKey,
      required this.noisePsk,
      required this.fingerprint});

  /// A relay topic for `label` that only group members can compute.
  Future<String> topic(String label) async => _b64((await Hmac.sha256()
          .calculateMac(utf8.encode(label), secretKey: topicKey))
      .bytes);

  /// Encrypts with the group key: nonce, ciphertext and tag in one buffer. `aad` is authenticated but not
  /// encrypted, for context such as the message type, so a payload can't be replayed as something else.
  Future<Uint8List> seal(List<int> plaintext, {List<int> aad = const []}) async {
    final box = await _aes.encrypt(plaintext,
        secretKey: groupKey, nonce: randomBytes(_nonceLength), aad: aad);
    return box.concatenation();
  }

  /// Decrypts a [seal]ed buffer. Throws if it was altered or sealed with another key or `aad`.
  /// The result is still untrusted peer data and must be validated by the caller.
  Future<Uint8List> open(List<int> sealed, {List<int> aad = const []}) async {
    if (sealed.length < _nonceLength + _macLength) {
      throw FormatException('Ciphertext too short');
    }
    final box = SecretBox.fromConcatenation(sealed,
        nonceLength: _nonceLength, macLength: _macLength, copy: false);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: groupKey, aad: aad));
  }
}

/// This device's static X25519 key pair for the Noise handshake. The seed is stored with the app's other data.
class DeviceIdentity {
  final Uint8List seed;
  final Uint8List publicKey;

  DeviceIdentity._(this.seed, this.publicKey);

  static Future<DeviceIdentity> fromSeed(List<int> seed) async {
    if (seed.length != 32) throw FormatException('Invalid device key');
    final keyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return DeviceIdentity._(Uint8List.fromList(seed), Uint8List.fromList(publicKey.bytes));
  }

  static Future<DeviceIdentity> generate() => fromSeed(randomBytes(32));

  static Future<DeviceIdentity> decode(String text) => fromSeed(_unb64(text));

  String encode() => _b64(seed);

  /// The public key as text, how other devices name this one.
  String get id => _b64(publicKey);
}
