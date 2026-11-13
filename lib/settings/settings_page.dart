import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/task_document.dart';
import '../bloc/tasks_bloc.dart';
import '../category/default_categories.dart';
import '../focus/pomodoro.dart';
import '../sync/peer.dart' show syncProtocol;
import '../version/build_info.dart';
import '../version/update_cubit.dart';

/// How the app behaves. The note size and Pomodoro lengths are saved on this device only; the
/// categories are kept with the tasks and synced with the group's other devices.
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
              _Section('Pomodoro'),
              _PomodoroDefaults(),
              _Section('Categories'),
              _Categories(),
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

/// The categories tasks are filed under. Each task written or renamed gets the one that fits it
/// best, chosen on this device; the list syncs with the group's other devices.
class _Categories extends StatelessWidget {
  const _Categories();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TasksBloc>();
    final theme = Theme.of(context);
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (a, b) => !listEquals(a.categories, b.categories),
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Each task gets one category: the one whose rules it mentions, or else the one '
              'that fits its name best, chosen on this device. Keywords help tell categories '
              'apart. Tap a task\'s category to correct it, and later tasks like it follow. '
              'Changes sync with your other devices.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          for (final c in state.categories)
            ListTile(
              key: ValueKey('category-${c.id}'),
              leading: const Icon(Icons.label_outline),
              title: Text(c.name),
              subtitle: switch ([
                if (c.rulePhrases.isNotEmpty) 'Always: ${c.rulePhrases.join(', ')}',
                if (c.keywords.isNotEmpty) c.keywords,
              ]) {
                [] => null,
                final lines => Text(lines.join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
              },
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, c),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add category'),
            onTap: () => _edit(context, null),
          ),
          if (_deletedDefaults(state) case final deleted when deleted.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore default categories'),
              subtitle: Text(deleted.join(', ')),
              onTap: () => bloc.add(RestoreDefaultCategoriesEvent()),
            ),
        ],
      ),
    );
  }

  /// The names of the default categories the user deleted.
  static List<String> _deletedDefaults(TasksState state) {
    final shown = {for (final c in state.categories) c.id};
    return [for (final d in defaultCategories) if (!shown.contains(d.id)) d.name];
  }

  Future<void> _edit(BuildContext context, TaskCategory? category) async {
    final bloc = context.read<TasksBloc>();
    final result = await showDialog<_CategoryEdit>(
      context: context,
      builder: (context) => _CategoryDialog(category: category),
    );
    switch (result) {
      case null:
        return;
      case _CategoryEdit(delete: true):
        if (category != null) bloc.add(RemoveCategoryEvent(id: category.id));
      case _CategoryEdit(:final name, :final keywords, :final rules) when category == null:
        bloc.add(AddCategoryEvent(name: name, keywords: keywords, rules: rules));
      case _CategoryEdit(:final name, :final keywords, :final rules):
        bloc.add(EditCategoryEvent(id: category.id, name: name, keywords: keywords, rules: rules));
    }
  }
}

class _CategoryEdit {
  final String name;
  final String keywords;
  final String rules;
  final bool delete;

  const _CategoryEdit({this.name = '', this.keywords = '', this.rules = '', this.delete = false});
}

/// Names a category and its keywords, or deletes it.
class _CategoryDialog extends StatefulWidget {
  final TaskCategory? category;

  const _CategoryDialog({required this.category});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late final _keywords = TextEditingController(text: widget.category?.keywords ?? '');
  late final _rules = TextEditingController(text: widget.category?.rules ?? '');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _rules.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
        context,
        _CategoryEdit(
            name: _name.text.trim(), keywords: _keywords.text.trim(), rules: _rules.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.category != null;
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(editing ? 'Edit category' : 'New category'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Work, Health, Home…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keywords,
              minLines: 1,
              maxLines: 3,
              // Enter saves, as in the name.
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Keywords',
                hintText: 'meeting, report, client (optional)',
                helperText: 'Words tasks in this category often use',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rules,
              minLines: 1,
              maxLines: 3,
              // Enter saves, as in the name.
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Always for tasks that mention',
                hintText: 'bringmeback, Acme (optional)',
                helperText: 'Names or phrases, separated by commas. A task that mentions one '
                    'goes here, whatever else it says.',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () => Navigator.pop(context, const _CategoryEdit(delete: true)),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _canSave ? _save : null, child: Text(editing ? 'Save' : 'Add')),
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
