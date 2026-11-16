import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/breaks.dart';
import '../bloc/tasks_bloc.dart';
import '../focus/pomodoro.dart';
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
              _TaskLimitTile(),
              _NoteMinutesTile(),
              _Section('Experimental'),
              _BacklogSwitch(),
              _Section('Breaks'),
              _BreakCategoriesTiles(),
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
  final int step;

  /// Shows the value; by default the number and [unit].
  final String Function(int value)? format;
  final String lessTooltip;
  final String moreTooltip;
  final ValueChanged<int> onChanged;
  final Widget? leading;

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
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
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

/// The break types holding the pause button offers, each with how long it should last.
class _BreakCategoriesTiles extends StatelessWidget {
  const _BreakCategoriesTiles();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (a, b) => !listEquals(a.breakCategories, b.breakCategories),
      builder: (context, state) {
        final categories = state.breakCategories;
        void update(List<BreakCategory> next) => bloc.add(SetBreakCategoriesEvent(next));
        return Column(
          children: [
            const ListTile(
              dense: true,
              subtitle: Text('Hold the pause button to take one of these breaks. When its time '
                  'is up, the app calls you back to your task. Double tap a break to change it.'),
            ),
            for (final (i, c) in categories.indexed)
              _StepperTile(
                key: ValueKey('break-setting-${c.name}'),
                title: c.name,
                value: c.minutes,
                min: minBreakMinutes,
                max: maxBreakMinutes,
                step: c.minutes < 10 ? 1 : 5,
                format: formatMinutes,
                lessTooltip: 'Shorter ${c.name}',
                moreTooltip: 'Longer ${c.name}',
                leading: IconButton(
                  tooltip: 'Edit ${c.name}',
                  icon: Icon(breakIcon(c.icon)),
                  onPressed: () async {
                    final edited = await _editCategory(context, c);
                    if (edited == null) return;
                    final next = [...categories];
                    if (edited.name.isEmpty) {
                      next.removeAt(i);
                    } else {
                      next[i] = edited;
                    }
                    update(next);
                  },
                ),
                onChanged: (v) {
                  final next = [...categories];
                  next[i] = c.copyWith(minutes: v);
                  update(next);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add a break type'),
              onTap: () async {
                final added = await _editCategory(
                    context, const BreakCategory(name: '', minutes: 15, icon: 'rest'),
                    adding: true);
                if (added == null || added.name.isEmpty) return;
                update([...categories, added]);
              },
            ),
            if (!listEquals(categories, defaultBreakCategories))
              ListTile(
                leading: const Icon(Icons.settings_backup_restore),
                title: const Text('Reset break types'),
                onTap: () => update(defaultBreakCategories),
              ),
          ],
        );
      },
    );
  }
}

/// Asks for a break type's name, length and icon. Returns one with an empty name to remove it,
/// or null when cancelled.
Future<BreakCategory?> _editCategory(BuildContext context, BreakCategory category,
        {bool adding = false}) =>
    showDialog<BreakCategory>(
      context: context,
      builder: (context) => _BreakCategoryDialog(category: category, adding: adding),
    );

class _BreakCategoryDialog extends StatefulWidget {
  final BreakCategory category;
  final bool adding;

  const _BreakCategoryDialog({required this.category, required this.adding});

  @override
  State<_BreakCategoryDialog> createState() => _BreakCategoryDialogState();
}

class _BreakCategoryDialogState extends State<_BreakCategoryDialog> {
  late final _name = TextEditingController(text: widget.category.name);
  late final _minutes = TextEditingController(text: '${widget.category.minutes}');
  late var _icon = widget.category.icon;

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    super.dispose();
  }

  BreakCategory _read() => BreakCategory(
      name: _name.text.trim(),
      minutes: (int.tryParse(_minutes.text.trim()) ?? widget.category.minutes)
          .clamp(minBreakMinutes, maxBreakMinutes),
      icon: _icon);

  @override
  Widget build(BuildContext context) {
    final adding = widget.adding;
    final short =
        (int.tryParse(_minutes.text.trim()) ?? recommendedBreakMinutes) < recommendedBreakMinutes;
    return AlertDialog(
      title: Text(adding ? 'Add a break type' : 'Edit break type'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: adding,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _minutes,
              decoration: InputDecoration(
                  labelText: 'Minutes',
                  helperText:
                      short ? 'Breaks under $recommendedBreakMinutes min rarely rest you' : null),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: [
                for (final MapEntry(:key, :value) in breakIcons.entries)
                  IconButton(
                    tooltip: key,
                    isSelected: key == _icon,
                    icon: Icon(value),
                    onPressed: () => setState(() => _icon = key),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (!adding)
          TextButton(
            onPressed: () => Navigator.pop(context, widget.category.copyWith(name: '')),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, _read()),
          child: Text(adding ? 'Add' : 'Save'),
        ),
      ],
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
