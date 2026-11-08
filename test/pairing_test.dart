import 'dart:convert';

import 'package:bringmeback/sync/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'symbolon_native.dart';

// Needs the native library: run `tool/build_symbolon.sh native` first.
void main() {
  setUpAll(loadSymbolonForTests);

  test('a code read on another device gives the same keys', () async {
    final a = PairingCode.generate();
    final b = await PairingCode.parse(await a.encode());
    final ka = a.deriveKeys();
    final kb = b.deriveKeys();
    expect(kb.fingerprint, ka.fingerprint);
    expect(kb.topic('signal'), ka.topic('signal'));
    expect(kb.open(ka.seal([1, 2, 3])), [1, 2, 3]);
  });

  test('keys are different per group and per label', () {
    final a = PairingCode.generate().deriveKeys();
    final b = PairingCode.generate().deriveKeys();
    expect(a.fingerprint, isNot(b.fingerprint));
    expect(a.fingerprint, matches(RegExp(r'^[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}$')));
    expect(a.topic('x'), isNot(a.topic('y')));
    expect(a.topic('x'), isNot(b.topic('x')));
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

  test('sealed payloads open only with the same key and context', () {
    final keys = PairingCode.generate().deriveKeys();
    final other = PairingCode.generate().deriveKeys();
    final msg = utf8.encode('hello');
    final sealed = keys.seal(msg, aad: utf8.encode('changes'));
    expect(keys.open(sealed, aad: utf8.encode('changes')), msg);
    expect(keys.seal(msg), isNot(keys.seal(msg)));
    expect(() => keys.open(sealed, aad: utf8.encode('offer')), throwsA(anything));
    expect(() => other.open(sealed, aad: utf8.encode('changes')), throwsA(anything));
    final tampered = [...sealed]..[30] ^= 1;
    expect(() => keys.open(tampered, aad: utf8.encode('changes')), throwsA(anything));
    expect(() => keys.open([1, 2, 3]), throwsA(anything));
  });

  test('a device key survives a save and reload', () {
    final device = DeviceIdentity.generate();
    final restored = DeviceIdentity.decode(device.encode());
    expect(restored.id, device.id);
    expect(device.publicKey.length, 32);
    expect(DeviceIdentity.generate().id, isNot(device.id));
  });

  test('a device key saved by the earlier version still loads', () {
    // An X25519 seed from the `cryptography` package, and the public key it gave (RFC 7748 vector).
    final seed = base64Url.encode(List.generate(32, (i) => 0)).replaceAll('=', '');
    expect(DeviceIdentity.decode(seed).id, isNotEmpty);
    final alicePrivate = _hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a');
    expect(DeviceIdentity.fromPrivate(alicePrivate).publicKey,
        _hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a'));
  });
}

List<int> _hex(String s) =>
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];
