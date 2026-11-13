import 'package:bringmeback/sync/pairing.dart';
import 'package:bringmeback/sync/share_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Uri.parse('https://example.com/bringmeback/');

  test('a link carries the code in the fragment, not the query', () async {
    final code = await PairingCode.generate().encode();
    final link = ShareLink.build(base, code);
    expect(link.toString(), 'https://example.com/bringmeback/#join=$code');
    expect(link.query, isEmpty);
  });

  test('extra parameters follow the code', () {
    final link = ShareLink.build(base, 'bmb1-abc', {'relays': 'wss://a,wss://b'});
    final parsed = ShareLink.parse(link.toString())!;
    expect(parsed.code, 'bmb1-abc');
    expect(parsed.params, {'relays': 'wss://a,wss://b'});
  });

  test('finds the code in a link, a bare code, a message, or a query', () {
    expect(ShareLink.parse('https://example.com/app/#join=bmb1-Ab_9-x')!.code, 'bmb1-Ab_9-x');
    expect(ShareLink.parse('  bmb1-Ab_9-x\n')!.code, 'bmb1-Ab_9-x');
    expect(ShareLink.parse('Join me: https://example.com/#join=bmb1-Ab_9-x thanks')!.code,
        'bmb1-Ab_9-x');
    expect(ShareLink.parse('https://example.com/?join=bmb1-Ab_9-x')!.code, 'bmb1-Ab_9-x');
    expect(ShareLink.parse('https://example.com/#/join?join=bmb1-Ab_9-x')!.code, 'bmb1-Ab_9-x');
  });

  test('ignores text without a code', () {
    expect(ShareLink.parse('https://example.com/'), isNull);
    expect(ShareLink.parse('https://example.com/#/'), isNull);
    expect(ShareLink.parse('hello'), isNull);
  });

  test('the base drops the fragment and query of the address the app was opened at', () {
    expect(ShareLink.baseOf(Uri.parse('https://example.com/app/?join=bmb1-x#join=bmb1-x')).toString(),
        'https://example.com/app/');
    expect(ShareLink.baseOf(Uri.parse('http://localhost:8080/#/')).toString(), 'http://localhost:8080/');
  });

  test('a pairing code parses from its link, so pasting the link joins too', () async {
    final pairing = PairingCode.generate();
    final code = await pairing.encode();
    final parsed = await PairingCode.parse(ShareLink.build(base, code).toString());
    expect(parsed.secret, pairing.secret);
    await expectLater(PairingCode.parse('https://example.com/'), throwsFormatException);
  });
}
