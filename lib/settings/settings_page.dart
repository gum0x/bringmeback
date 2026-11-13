import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';
import '../focus/pomodoro.dart';
import '../sync/peer.dart' show syncProtocol;
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
              _TaskLimitTile(),
              _Section('Experimental'),
              _BacklogSwitch(),
              _Section('Pomodoro'),
              _PomodoroDefaults(),
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
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: unit.isEmpty ? 32 : 64,
            child: Text(unit.isEmpty ? '$value' : '$value $unit',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          IconButton(
            tooltip: moreTooltip,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// The backlog is a trial: it may change, or move elsewhere.
class _BacklogSwitch extends StatelessWidget {
  const _BacklogSwitch();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (a, b) => a.backlogEnabled != b.backlogEnabled,
      builder: (context, state) => SwitchListTile(
        title: const Text('Backlog'),
        subtitle: const Text('Past the limit, offer to keep a new task for later, in a backlog '
            'under the note. A trial: it may change or move.'),
        value: state.backlogEnabled,
        onChanged: (on) => bloc.add(SetBacklogEnabledEvent(on)),
      ),
    );
  }
}

class _TaskLimitTile extends StatelessWidget {
  const _TaskLimitTile();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (a, b) => a.taskLimit != b.taskLimit,
      builder: (context, state) => _StepperTile(
        title: 'Open tasks before asking',
        subtitle: 'A short list keeps the day focused. Past this many tasks not done yet, a new '
            'task asks first: write it anyway, or let it go. Done tasks don\'t count.',
        value: state.taskLimit,
        min: minTaskLimit,
        max: maxTaskLimit,
        lessTooltip: 'Lower task limit',
        moreTooltip: 'Higher task limit',
        onChanged: (limit) => bloc.add(SetTaskLimitEvent(limit)),
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
