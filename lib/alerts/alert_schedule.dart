import '../bloc/tasks_bloc.dart';

enum AlertKind {
  /// The countdown ran out.
  timeUp,

  /// Another 30 minutes of the countdown passed.
  reminder,
}

/// Seconds between reminders.
const reminderSeconds = 30 * 60;

/// The alert due when a task's countdown goes from `previous` to `remaining` seconds, if any.
///
/// Running out is [AlertKind.timeUp]. Crossing a multiple of [reminderSeconds] is a reminder,
/// except right after running out, which the time-up alert already covers.
AlertKind? alertBetween(int previous, int remaining) {
  if (previous == remaining) return null;
  if (previous > 0 && remaining <= 0) return AlertKind.timeUp;
  if (previous >= 0 && remaining < 0) return null;
  return _floorDiv(previous) != _floorDiv(remaining) ? AlertKind.reminder : null;
}

int _floorDiv(int s) => (s / reminderSeconds).floor();

/// An alert due at [at], in seconds since the epoch.
class ScheduledAlert {
  final int at;
  final AlertKind kind;
  final String taskName;

  const ScheduledAlert(this.at, this.kind, this.taskName);

  @override
  bool operator ==(Object other) =>
      other is ScheduledAlert && other.at == at && other.kind == kind && other.taskName == taskName;

  @override
  int get hashCode => Object.hash(at, kind, taskName);

  @override
  String toString() => 'ScheduledAlert($at, $kind, $taskName)';
}

/// The alerts the running tasks will raise after `now`, as [alertBetween] decides them second by
/// second, soonest first: at most `max` of them, and none more than `horizon` seconds ahead.
///
/// Only running countdowns change, so only running tasks raise alerts.
List<ScheduledAlert> alertsAfter(List<TaskState> tasks, int now,
    {int horizon = 24 * 60 * 60, int max = 32}) {
  final alerts = <ScheduledAlert>[];
  for (final task in tasks) {
    if (!task.running) continue;
    final remaining = task.remainingSecondsAt(now);
    // The countdown reaches value `v` at `now + remaining - v`.
    void add(int v, AlertKind kind) {
      final at = now + remaining - v;
      if (at > now && at - now <= horizon) alerts.add(ScheduledAlert(at, kind, task.name));
    }

    if (remaining > 0) add(0, AlertKind.timeUp);
    // Reminders: the countdown steps from k * reminderSeconds to one second below it, k != 0.
    for (var k = _floorDiv(remaining);; k--) {
      if (k == 0) continue;
      final v = k * reminderSeconds - 1;
      if (remaining - v > horizon) break;
      add(v, AlertKind.reminder);
    }
  }
  alerts.sort((a, b) => a.at.compareTo(b.at));
  return alerts.length > max ? alerts.sublist(0, max) : alerts;
}
