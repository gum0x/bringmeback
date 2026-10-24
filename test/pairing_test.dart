import 'dart:convert';

import 'package:bringmeback/sync/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a code read on another device gives the same keys', () async {
    final a = PairingCode.generate();
    final b = await PairingCode.parse(await a.encode());
    final ka = await a.deriveKeys();
    final kb = await b.deriveKeys();
    expect(kb.fingerprint, ka.fingerprint);
    expect(kb.signalingPassword, ka.signalingPassword);
    expect(await kb.topic('signal'), await ka.topic('signal'));
    expect(await ka.groupKey.extractBytes(), await kb.groupKey.extractBytes());
  });

  test('keys are different per group and per purpose', () async {
    final a = await PairingCode.generate().deriveKeys();
    final b = await PairingCode.generate().deriveKeys();
    expect(a.fingerprint, isNot(b.fingerprint));
    expect(await a.groupKey.extractBytes(), isNot(await a.topicKey.extractBytes()));
    expect(await a.topic('x'), isNot(await a.topic('y')));
  });

  test('bad codes are rejected', () async {
    final code = await PairingCode.generate().encode();
    final last = code[code.length - 1];
    final typo = code.substring(0, code.length - 1) + (last == 'A' ? 'B' : 'A');
    for (final bad in ['', 'hello', 'bmb1-', 'bmb1-!!!', code.substring(0, 20), typo]) {
      expect(() => PairingCode.parse(bad), throwsFormatException, reason: bad);
    }
    expect((await PairingCode.parse('  $code\n')).secret.length, 32);
  });

  test('sealed payloads open only with the same key and context', () async {
    final keys = await PairingCode.generate().deriveKeys();
    final other = await PairingCode.generate().deriveKeys();
    final msg = utf8.encode('hello');
    final sealed = await keys.seal(msg, aad: utf8.encode('changes'));
    expect(await keys.open(sealed, aad: utf8.encode('changes')), msg);
    expect(await keys.seal(msg), isNot(await keys.seal(msg)));
    await expectLater(keys.open(sealed, aad: utf8.encode('offer')), throwsA(anything));
    await expectLater(other.open(sealed, aad: utf8.encode('changes')), throwsA(anything));
    final tampered = [...sealed]..[20] ^= 1;
    await expectLater(keys.open(tampered, aad: utf8.encode('changes')), throwsA(anything));
    await expectLater(keys.open([1, 2, 3]), throwsFormatException);
  });

  test('device signatures verify only for the signing device', () async {
    final device = await DeviceIdentity.generate();
    final restored = await DeviceIdentity.decode(device.encode());
    expect(restored.id, device.id);
    final msg = utf8.encode('change');
    final sig = await restored.sign(msg);
    expect(await verifySignature(device.id, msg, sig), isTrue);
    expect(await verifySignature(device.id, utf8.encode('other'), sig), isFalse);
    final stranger = await DeviceIdentity.generate();
    expect(await verifySignature(stranger.id, msg, sig), isFalse);
    expect(await verifySignature('not-a-key', msg, sig), isFalse);
  });
}
