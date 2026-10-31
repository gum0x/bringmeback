import 'dart:convert';

import 'package:bringmeback/src/rust/api/symbolon.dart' as symbolon;
import 'package:bringmeback/sync/pairing.dart';
import 'package:bringmeback/sync/symbolon.dart';
import 'package:flutter_test/flutter_test.dart';

// Two devices of the same group run the Noise handshake in memory, through the Dart binding.
void main() {
  setUpAll(loadSymbolon);

  final prologue = utf8.encode('bringmeback test');

  (symbolon.SecureChannel, symbolon.SecureChannel) connect(
      DeviceIdentity a, DeviceIdentity b, GroupKeys keysA, GroupKeys keysB) {
    final initiator = symbolon.NoiseHandshake.initiator(
        device: a.key, remotePublic: b.publicKey, group: keysA.inner, prologue: prologue);
    final responder =
        symbolon.NoiseHandshake.responder(device: b.key, group: keysB.inner, prologue: prologue);
    responder.readMessage(message: initiator.writeMessage(payload: []));
    expect(responder.remoteStatic(), a.publicKey);
    initiator.readMessage(message: responder.writeMessage(payload: []));
    expect(initiator.isFinished() && responder.isFinished(), isTrue);
    return (initiator.intoChannel(), responder.intoChannel());
  }

  test('devices of one group get a working channel', () {
    final keys = PairingCode.generate().deriveKeys();
    final a = DeviceIdentity.generate(), b = DeviceIdentity.generate();
    expect(symbolon.initiates(localPublic: a.publicKey, remotePublic: b.publicKey),
        isNot(symbolon.initiates(localPublic: b.publicKey, remotePublic: a.publicKey)));
    final (ca, cb) = connect(a, b, keys, keys);
    expect(cb.decrypt(ciphertext: ca.encrypt(plaintext: utf8.encode('hi'))), utf8.encode('hi'));
    expect(ca.decrypt(ciphertext: cb.encrypt(plaintext: [7])), [7]);
    expect(() => ca.decrypt(ciphertext: [1, 2, 3]), throwsA(anything));
    expect(ca.isOpen(), isFalse);
  });

  test('a device from another group is rejected', () {
    final a = DeviceIdentity.generate(), b = DeviceIdentity.generate();
    expect(
        () => connect(a, b, PairingCode.generate().deriveKeys(), PairingCode.generate().deriveKeys()),
        throwsA(anything));
  });
}
