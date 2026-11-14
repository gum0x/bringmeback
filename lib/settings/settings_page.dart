import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';
import '../focus/pomodoro.dart';
import '../reminders/reminders_cubit.dart';
import '../reminders/routine_reminders.dart';
import '../sync/peer.dart' show syncProtocol;
import '../timer.dart';
import '../version/build_info.dart';
import '../version/update_cubit.dart';

/// How the app behaves on this device. Settings are saved here and are not synced.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: const [
              _Section('Today\'s note'),
              _NoteLinesTile(),
              _NoteMinutesTile(),
              _Section('Pomodoro'),
              _PomodoroDefaults(),
              _Section('Reminders'),
              _RemindersTiles(),
              _Section('About'),
              _VersionTiles(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;

  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// A setting with a small number, changed one step at a time with − and +.
class _StepperTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final String unit;
  final int step;

  /// Shows the value; by default the number and [unit].
  final String Function(int value)? format;
  final String lessTooltip;
  final String moreTooltip;
  final ValueChanged<int> onChanged;

  const _StepperTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    this.unit = '',
    this.step = 1,
    this.format,
    required this.lessTooltip,
    required this.moreTooltip,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: lessTooltip,
            onPressed:
                value > min ? () => onChanged((value - step).clamp(min, max)) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: format != null ? 96 : (unit.isEmpty ? 32 : 64),
            child: Text(format?.call(value) ?? (unit.isEmpty ? '$value' : '$value $unit'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          IconButton(
            tooltip: moreTooltip,
            onPressed:
                value < max ? () => onChanged((value + step).clamp(min, max)) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _NoteLinesTile extends StatelessWidget {
  const _NoteLinesTile();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (a, b) => a.noteLines != b.noteLines,
      builder: (context, state) => _StepperTile(
        title: 'Tasks per note',
        subtitle: 'A small note keeps the day focused. Done tasks count too. '
            'Making it smaller keeps what is already written.',
        value: state.noteLines,
        min: minNoteLines,
        max: maxNoteLines,
        lessTooltip: 'Fewer tasks per note',
        moreTooltip: 'More tasks per note',
        onChanged: (lines) => bloc.add(SetNoteLinesEvent(lines)),
      ),
    );
  }
}

class _NoteMinutesTile extends StatelessWidget {
  const _NoteMinutesTile();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (a, b) => a.noteMinutes != b.noteMinutes,
      builder: (context, state) => _StepperTile(
        key: const Key('noteMinutes'),
        title: 'Time per note',
        subtitle: 'The expected times of the tasks on a note, added up. '
            'Committing more shows in red.',
        value: state.noteMinutes,
        min: minNoteMinutes,
        max: maxNoteMinutes,
        step: noteMinutesStep,
        format: formatMinutes,
        lessTooltip: 'Less time per note',
        moreTooltip: 'More time per note',
        onChanged: (minutes) => bloc.add(SetNoteMinutesEvent(minutes)),
      ),
    );
  }
}

/// The lengths a focus view starts with. The focus view can change them for one focus, or keep its
/// change here.
class _PomodoroDefaults extends StatefulWidget {
  const _PomodoroDefaults();

  @override
  State<_PomodoroDefaults> createState() => _PomodoroDefaultsState();
}

class _PomodoroDefaultsState extends State<_PomodoroDefaults> {
  PomodoroSettings? _settings;

  @override
  void initState() {
    super.initState();
    PomodoroSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  void _update(PomodoroSettings settings) {
    setState(() => _settings = settings);
    settings.save();
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) return const SizedBox(height: 48);
    return Column(
      children: [
        _StepperTile(
          key: const Key('pomodoroWork'),
          title: 'Focus',
          subtitle: 'How long each focus session lasts.',
          value: s.workMinutes,
          min: 1,
          max: 120,
          unit: 'min',
          lessTooltip: 'Shorter focus',
          moreTooltip: 'Longer focus',
          onChanged: (v) => _update(s.copyWith(workMinutes: v)),
        ),
        _StepperTile(
          key: const Key('pomodoroShortBreak'),
          title: 'Short break',
          value: s.shortBreakMinutes,
          min: 1,
          max: 60,
          unit: 'min',
          lessTooltip: 'Shorter short break',
          moreTooltip: 'Longer short break',
          onChanged: (v) => _update(s.copyWith(shortBreakMinutes: v)),
        ),
        _StepperTile(
          key: const Key('pomodoroLongBreak'),
          title: 'Long break',
          value: s.longBreakMinutes,
          min: 1,
          max: 120,
          unit: 'min',
          lessTooltip: 'Shorter long break',
          moreTooltip: 'Longer long break',
          onChanged: (v) => _update(s.copyWith(longBreakMinutes: v)),
        ),
        _StepperTile(
          key: const Key('pomodoroSessions'),
          title: 'Long break every',
          subtitle: 'Focus sessions before a long break.',
          value: s.sessionsBeforeLongBreak,
          min: 1,
          max: 12,
          lessTooltip: 'Fewer sessions before a long break',
          moreTooltip: 'More sessions before a long break',
          onChanged: (v) => _update(s.copyWith(sessionsBeforeLongBreak: v)),
        ),
        ListTile(
          key: const Key('pomodoroCycle'),
          leading: const Icon(Icons.timelapse),
          title: Text(describeCycle(s)),
          subtitle: const Text('Every focus session, the short breaks between them '
              'and the long break.'),
        ),
      ],
    );
  }
}

/// The morning and afternoon reminders: on or off, and when, on this device only.
class _RemindersTiles extends StatelessWidget {
  const _RemindersTiles();

  static const _what = {
    RoutineReminder.morning: 'Update the note with what you will do today.',
    RoutineReminder.afternoon: 'Start closing today\'s open tasks.',
  };

  static bool _hasReminders(BuildContext context) {
    try {
      context.read<RemindersCubit>();
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _pickTime(BuildContext context, RoutineReminder reminder, ReminderTime time) async {
    final reminders = context.read<RemindersCubit>();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
      helpText: reminder.label,
    );
    if (picked != null) await reminders.setMinutes(reminder, picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    // Pages opened on their own, as in tests, may have no reminders above them.
    if (!_hasReminders(context)) return const SizedBox.shrink();
    return BlocBuilder<RemindersCubit, RemindersState>(
      builder: (context, state) {
        final reminders = context.read<RemindersCubit>();
        if (!state.loaded) return const SizedBox(height: 48);
        return Column(children: [
          for (final r in RoutineReminder.values)
            ListTile(
              key: Key('reminder.${r.name}'),
              title: Text(r.label),
              subtitle: Text(_what[r]!),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  key: Key('reminder.${r.name}.time'),
                  onPressed: () => _pickTime(context, r, state.settings[r]),
                  child: Text(state.settings[r].label,
                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                ),
                Switch(
                  key: Key('reminder.${r.name}.on'),
                  value: state.settings[r].enabled,
                  onChanged: (on) => reminders.setEnabled(r, on),
                ),
              ]),
            ),
          ListTile(
            leading: Icon(state.denied ? Icons.notifications_off : Icons.info_outline),
            subtitle: Text(state.denied
                ? 'Notifications are blocked for bringmeback. Allow them in this '
                    '${kIsWeb ? 'browser\'s site settings' : 'device\'s settings'}, then turn the '
                    'reminder on again.'
                : reminders.ringsInBackground
                    ? 'Reminders ring every day, with the app closed too. They are set on this '
                        'device only.'
                    : 'Reminders ring every day while bringmeback is open${kIsWeb ? ' in a tab' : ''}. '
                        'They are set on this device only.'),
          ),
        ]);
      },
    );
  }
}

/// This build's version, and whether a newer one is out.
class _VersionTiles extends StatelessWidget {
  const _VersionTiles();

  static bool _hasUpdates(BuildContext context) {
    try {
      context.read<UpdateCubit>();
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final build = BuildInfo.current;
    // Pages opened on their own, as in tests, may have no update check above them.
    if (!_hasUpdates(context)) {
      return ListTile(
          title: Text('Version ${build.label}'), subtitle: Text('Sync version $syncProtocol'));
    }
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (context, state) {
        final updates = context.read<UpdateCubit>();
        final latest = state.latest;
        final String status;
        if (!UpdateCubit.supported) {
          status = 'Local builds aren\'t checked for newer versions.';
        } else if (!kIsWeb && !state.checkReleases) {
          status = 'Checking for new releases is off.';
        } else if (state.newer) {
          status = 'A newer version is out: ${latest!.label}.';
        } else if (state.error != null && state.checkedAt != null) {
          status = 'The last check failed: ${state.error}';
        } else if (state.checkedAt != null) {
          status = 'This is the latest version.';
        } else {
          status = 'Checking…';
        }
        return Column(children: [
          ListTile(
            title: Text('Version ${build.label}'),
            subtitle: Text('${build.isRelease ? 'Release' : build.isKnown ? 'Built from commit ${build.commit}' : 'Run it with tool/run.sh to show the commit'}'
                ', sync version $syncProtocol\n$status'),
            isThreeLine: true,
            trailing: UpdateCubit.supported && (kIsWeb || state.checkReleases)
                ? IconButton(
                    tooltip: 'Check now', icon: const Icon(Icons.refresh), onPressed: updates.check)
                : null,
          ),
          if (!kIsWeb && build.isRelease)
            SwitchListTile(
              title: const Text('Check for new releases'),
              subtitle: const Text('Asks GitHub for the latest release when the app starts, '
                  'and every half hour. GitHub sees this device\'s address.'),
              value: state.checkReleases,
              onChanged: updates.setCheckReleases,
            ),
        ]);
      },
    );
  }
}
