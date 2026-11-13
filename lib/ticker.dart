import 'dart:async';

/// Calls [onTick] once a second, just after each second turns over.
///
/// A plain `Timer.periodic` drifts against the clock and runs late whenever the app is busy, for
/// example while the mouse moves over it. When its ticks happen to sit near the moment a second
/// turns over, that jitter makes some ticks land just before it and others just after, so the
/// clock on screen holds one second too long and then skips the next. Firing a little after each
/// turnover keeps every second on screen the same length.
class SecondTicker {
  final void Function() onTick;

  /// Where in the second the clock turns over, in milliseconds. Whole seconds of wall-clock time
  /// turn over at 0; a countdown to a deadline turns over at the deadline's milliseconds.
  final int Function() turnoverMs;

  Timer? _timer;

  // Late enough that the turnover has surely passed, early enough to look instant.
  static const _margin = 20;

  SecondTicker(this.onTick, {int Function()? turnoverMs})
      : turnoverMs = turnoverMs ?? (() => 0) {
    _schedule();
  }

  /// Milliseconds from [nowMs] until just after the next turnover at [turnoverMs].
  static int delayUntilNext(int nowMs, int turnoverMs) {
    final untilTurnover = (turnoverMs - nowMs) % 1000;
    return untilTurnover + _margin;
  }

  void _schedule() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer(
        Duration(milliseconds: delayUntilNext(now, turnoverMs())), () {
      onTick();
      if (_timer != null) _schedule();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
