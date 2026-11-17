import 'package:shared_preferences/shared_preferences.dart';

/// The two reminders that frame the day: one in the morning to bring the note up to date, one in
/// the afternoon to start closing what is open.
enum RoutineReminder {
  morning(
    label: 'Morning reminder',
    title: 'Plan your day',
    body: 'Update bringmeback: put today\'s tasks on the note, in the order you will do them.',
    defaultMinutes: 9 * 60,
    idBase: 100,
  ),
  afternoon(
    label: 'Afternoon reminder',
    title: 'Start wrapping up',
    body: 'Time to close today\'s open tasks: finish them, or let them go.',
    defaultMinutes: 17 * 60,
    idBase: 200,
  );

  /// The name of the setting.
  final String label;

  /// What the notification says.
  final String title;
  final String body;

  /// When it rings by default, in minutes after midnight.
  final int defaultMinutes;

  /// Notification ids for this reminder are [idBase] plus the day it is scheduled for, counted from
  /// today, so each day's notification can be replaced or cancelled on its own.
  final int idBase;

  const RoutineReminder({
    required this.label,
    required this.title,
    required this.body,
    required this.defaultMinutes,
    required this.idBase,
  });
}

/// When one reminder rings, and whether it is on.
class ReminderTime {
  final bool enabled;

  /// Minutes after midnight, local time.
  final int minutes;

  const ReminderTime({required this.enabled, required this.minutes});

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  /// 09:00, 17:30.
  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderTime copyWith({bool? enabled, int? minutes}) =>
      ReminderTime(enabled: enabled ?? this.enabled, minutes: minutes ?? this.minutes);

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.enabled == enabled && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(enabled, minutes);
}

/// One notification to show at [at].
class ScheduledReminder {
  final RoutineReminder reminder;
  final DateTime at;

  /// Which day it is for, counted from today: 0 for today, 1 for tomorrow.
  final int day;

  const ScheduledReminder(this.reminder, this.at, this.day);

  int get id => reminder.idBase + day;

  /// The same reminder at the same moment, whichever day it was counted from.
  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder && other.reminder == reminder && other.at == at;

  @override
  int get hashCode => Object.hash(reminder, at);

  @override
  String toString() => 'ScheduledReminder(${reminder.name}, $at)';
}

/// The routine reminders of this device. Kept in this device's preferences, not in the synced
/// document: each device rings at its own times, or not at all.
class RoutineSettings {
  final ReminderTime morning;
  final ReminderTime afternoon;

  /// How many days ahead reminders are scheduled with the system, where the system keeps them
  /// while the app is closed. Every start of the app tops them up again.
  static const daysAhead = 14;

  const RoutineSettings({
    this.morning = const ReminderTime(enabled: false, minutes: 9 * 60),
    this.afternoon = const ReminderTime(enabled: false, minutes: 17 * 60),
  });

  ReminderTime operator [](RoutineReminder r) => switch (r) {
        RoutineReminder.morning => morning,
        RoutineReminder.afternoon => afternoon,
      };

  RoutineSettings withTime(RoutineReminder r, ReminderTime time) => switch (r) {
        RoutineReminder.morning => RoutineSettings(morning: time, afternoon: afternoon),
        RoutineReminder.afternoon => RoutineSettings(morning: morning, afternoon: time),
      };

  bool get anyEnabled => morning.enabled || afternoon.enabled;

  /// The reminders due after [now] over [days] days, today included, soonest first. A reminder
  /// whose time today has passed starts tomorrow.
  ///
  /// Times are local wall-clock times, so a reminder at 09:00 stays at 09:00 across a change to or
  /// from summer time.
  List<ScheduledReminder> upcoming(DateTime now, {int days = daysAhead}) {
    final today = DateTime(now.year, now.month, now.day);
    final result = <ScheduledReminder>[];
    for (final r in RoutineReminder.values) {
      final time = this[r];
      if (!time.enabled) continue;
      for (var day = 0; day < days; day++) {
        final at = DateTime(today.year, today.month, today.day + day, time.hour, time.minute);
        if (at.isAfter(now)) result.add(ScheduledReminder(r, at, day));
      }
    }
    result.sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  /// The next reminder due after [now], if any is on.
  ScheduledReminder? next(DateTime now) {
    final soon = upcoming(now, days: 2);
    return soon.isEmpty ? null : soon.first;
  }

  static String _enabledKey(RoutineReminder r) => 'reminders.${r.name}.on';
  static String _minutesKey(RoutineReminder r) => 'reminders.${r.name}.at';

  static Future<RoutineSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    ReminderTime read(RoutineReminder r) {
      final minutes = prefs.getInt(_minutesKey(r));
      return ReminderTime(
        enabled: prefs.getBool(_enabledKey(r)) ?? false,
        minutes: minutes == null || minutes < 0 || minutes >= 24 * 60 ? r.defaultMinutes : minutes,
      );
    }

    return RoutineSettings(
        morning: read(RoutineReminder.morning), afternoon: read(RoutineReminder.afternoon));
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final r in RoutineReminder.values) {
      await prefs.setBool(_enabledKey(r), this[r].enabled);
      await prefs.setInt(_minutesKey(r), this[r].minutes);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RoutineSettings && other.morning == morning && other.afternoon == afternoon;

  @override
  int get hashCode => Object.hash(morning, afternoon);
}
