import 'dart:convert';

import 'package:bringmeback/sync/pairing.dart';
import 'package:symbolon_flutter/symbolon_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'symbolon_native.dart';

// Two devices of the same group run the Noise handshake in memory.
void main() {
  setUpAll(loadSymbolonForTests);

  final prologue = utf8.encode('bringmeback test');

  (SymbolonChannel, SymbolonChannel) connect(
      DeviceIdentity a, DeviceIdentity b, GroupKeys keysA, GroupKeys keysB) {
    final initiator = symbolon.initiator(a.key, b.publicKey, keysA.inner, prologue);
    final responder = symbolon.responder(b.key, keysB.inner, prologue);
    responder.readMessage(initiator.writeMessage([]));
    expect(responder.remoteStatic, a.publicKey);
    initiator.readMessage(responder.writeMessage([]));
    expect(initiator.isFinished && responder.isFinished, isTrue);
    return (initiator.intoChannel(), responder.intoChannel());
  }

  test('devices of one group get a working channel', () {
    final keys = PairingCode.generate().deriveKeys();
    final a = DeviceIdentity.generate(), b = DeviceIdentity.generate();
    expect(symbolon.initiates(a.publicKey, b.publicKey),
        isNot(symbolon.initiates(b.publicKey, a.publicKey)));
    final (ca, cb) = connect(a, b, keys, keys);
    expect(cb.decrypt(ca.encrypt(utf8.encode('hi'))), utf8.encode('hi'));
    expect(ca.decrypt(cb.encrypt([7])), [7]);
    expect(symbolon.maxPlaintext, greaterThan(60000));
    expect(() => ca.decrypt([1, 2, 3]), throwsA(anything));
    expect(ca.isOpen, isFalse);
  });

  test('a device from another group is rejected', () {
    final a = DeviceIdentity.generate(), b = DeviceIdentity.generate();
    expect(
        () => connect(a, b, PairingCode.generate().deriveKeys(), PairingCode.generate().deriveKeys()),
        throwsA(anything));
  });
}
