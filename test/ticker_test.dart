import 'package:bringmeback/ticker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waits until just after the next wall-clock second', () {
    expect(SecondTicker.delayUntilNext(10000, 0), 20);
    expect(SecondTicker.delayUntilNext(10001, 0), 1019);
    expect(SecondTicker.delayUntilNext(10999, 0), 21);
    expect(SecondTicker.delayUntilNext(10500, 0), 520);
  });

  test('follows a turnover inside the second', () {
    expect(SecondTicker.delayUntilNext(10000, 300), 320);
    expect(SecondTicker.delayUntilNext(10301, 300), 1019);
    expect(SecondTicker.delayUntilNext(10299, 300), 21);
  });

  test('a late tick still lands on the next second, not the same one again', () {
    // Ticks meant for just after 11.000 that ran late keep aiming at the second after.
    for (final now in [11020, 11200, 11900, 11979]) {
      final next = now + SecondTicker.delayUntilNext(now, 0);
      expect(next ~/ 1000, 12, reason: 'at $now');
    }
  });
}
