import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/task_document.dart';
import '../bloc/tasks_bloc.dart';
import '../category/categoriser.dart';
import '../focus/pomodoro.dart';

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
              'Each task gets the category that fits its name best, chosen on this device. '
              'Keywords help tell categories apart. Tap a task\'s category to correct it, '
              'and later tasks like it follow. The list syncs with your other devices.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          for (final c in state.categories)
            ListTile(
              key: ValueKey('category-${c.id}'),
              leading: const Icon(Icons.label_outline),
              title: Text(c.name),
              subtitle: c.keywords.isEmpty ? null : Text(c.keywords),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, c),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add category'),
            onTap: () => _edit(context, null),
          ),
          if (state.categories.isEmpty)
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Add suggested categories'),
              subtitle: Text([for (final c in suggestedCategories) c.name].join(', ')),
              onTap: () => bloc.add(AddSuggestedCategoriesEvent()),
            ),
        ],
      ),
    );
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
      case _CategoryEdit(:final name, :final keywords) when category == null:
        bloc.add(AddCategoryEvent(name: name, keywords: keywords));
      case _CategoryEdit(:final name, :final keywords):
        bloc.add(EditCategoryEvent(id: category.id, name: name, keywords: keywords));
    }
  }
}

class _CategoryEdit {
  final String name;
  final String keywords;
  final bool delete;

  const _CategoryEdit({this.name = '', this.keywords = '', this.delete = false});
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

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    Navigator.pop(context, _CategoryEdit(name: _name.text.trim(), keywords: _keywords.text.trim()));
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
              decoration: const InputDecoration(
                labelText: 'Keywords',
                hintText: 'meeting, report, client (optional)',
                helperText: 'Words tasks in this category often use',
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
