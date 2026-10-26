String intToFmtString(int seconds) {
  return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String intToSeconds(int seconds) {
  seconds = (seconds < 0) ? seconds * -1 : seconds;
  Duration duration = Duration(seconds: seconds);
  return duration.inSeconds.remainder(60).toString().padLeft(2, '0');
}

String intToMinutes(int seconds) {
  seconds = (seconds < 0) ? seconds * -1 : seconds;
  Duration duration = Duration(seconds: seconds);
  return (duration.inMinutes.remainder(60)).toString().padLeft(2, '0');
}

String intToHours(int seconds) {
  int positiveSeconds = (seconds < 0) ? seconds * -1 : seconds;
  Duration duration = Duration(seconds: positiveSeconds);
  String hours = (duration.inHours).toString().padLeft(2, '0');
  if (seconds < 0) {
    return "-$hours";
  }
  return hours;
}

/// A duration as a clock, "19:56" under an hour and "1:05:10" from an hour on. The sign is
/// dropped; callers show overtime their own way.
String formatClock(int seconds) {
  final s = seconds.abs();
  final hours = s ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  final secs = (s % 60).toString().padLeft(2, '0');
  if (hours == 0) return '${minutes.toString().padLeft(2, '0')}:$secs';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$secs';
}
