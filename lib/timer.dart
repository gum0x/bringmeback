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
