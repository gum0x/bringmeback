import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'reminder_notifier.dart';
import 'routine_reminders.dart';

class RemindersState {
  final RoutineSettings settings;

  /// Whether the settings were read from this device yet.
  final bool loaded;

  /// Whether the last request to show notifications was refused.
  final bool denied;

  const RemindersState(
      {this.settings = const RoutineSettings(), this.loaded = false, this.denied = false});
}

/// The morning and afternoon reminders of this device.
///
/// Where the system keeps scheduled notifications, the next [RoutineSettings.daysAhead] days are
/// handed to it, and topped up whenever the app starts or comes back. Elsewhere the app keeps a
/// timer to the next reminder and shows it itself, so it rings only while the app is open.
class RemindersCubit extends Cubit<RemindersState> {
  final ReminderNotifier _notifier;
  final DateTime Function() _now;
  Timer? _timer;

  /// The last reminder shown, so a timer that fires a moment early doesn't show it twice.
  ScheduledReminder? _shown;

  /// A reminder that comes this much late, because the device slept or the tab was frozen, is
  /// dropped: the moment for it has gone.
  static const tooLate = Duration(minutes: 30);

  RemindersCubit({ReminderNotifier? notifier, DateTime Function()? now})
      : _notifier = notifier ?? SystemReminderNotifier(),
        _now = now ?? DateTime.now,
        super(const RemindersState());

  /// Whether reminders ring with the app closed on this device.
  bool get ringsInBackground => _notifier.schedulesInBackground;

  Future<void> load() async {
    final settings = await RoutineSettings.load();
    if (isClosed) return;
    emit(RemindersState(settings: settings, loaded: true));
    await _apply();
  }

  /// Turns [reminder] on or off. Turning one on asks to show notifications; if that is refused, it
  /// stays off.
  Future<void> setEnabled(RoutineReminder reminder, bool on) async {
    if (on && !await _notifier.requestPermission()) {
      if (!isClosed) {
        emit(RemindersState(settings: state.settings, loaded: state.loaded, denied: true));
      }
      return;
    }
    await _update(
        state.settings.withTime(reminder, state.settings[reminder].copyWith(enabled: on)));
  }

  /// Sets the time [reminder] rings, in minutes after midnight.
  Future<void> setMinutes(RoutineReminder reminder, int minutes) => _update(
      state.settings.withTime(reminder, state.settings[reminder].copyWith(minutes: minutes)));

  /// The app came back to the front: a timer may have slept with it, and scheduled days run out.
  Future<void> resumed() async {
    if (state.loaded) await _apply();
  }

  Future<void> _update(RoutineSettings settings) async {
    if (isClosed) return;
    emit(RemindersState(settings: settings, loaded: true));
    await settings.save();
    await _apply();
  }

  Future<void> _apply() async {
    _timer?.cancel();
    _timer = null;
    final settings = state.settings;
    if (_notifier.schedulesInBackground) {
      try {
        await _notifier.replaceScheduled(settings.upcoming(_now()));
      } on Object catch (e) {
        debugPrint('Could not schedule the reminders: $e');
      }
      return;
    }
    // Ready ahead of the first reminder: on the web that installs the worker that shows them.
    if (settings.anyEnabled) unawaited(_notifier.prepare());
    _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    final soonest = state.settings.next(_now());
    final next = soonest != null && soonest == _shown ? state.settings.next(soonest.at) : soonest;
    if (next == null || isClosed) return;
    _timer = Timer(next.at.difference(_now()), () => _fire(next));
  }

  Future<void> _fire(ScheduledReminder due) async {
    if (isClosed) return;
    final late = _now().difference(due.at);
    if (due != _shown && state.settings[due.reminder].enabled && late < tooLate) {
      _shown = due;
      await _notifier.show(due.reminder);
    }
    _armTimer();
  }

  @visibleForTesting
  bool get timerActive => _timer?.isActive ?? false;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
