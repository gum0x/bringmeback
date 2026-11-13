import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/task_transfer.dart';
import '../bloc/tasks_bloc.dart';
import '../focus/pomodoro.dart';

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
              _Section('Pomodoro'),
              _PomodoroDefaults(),
              _Section('Tasks'),
              _ExportTasksTile(),
              _ImportTasksTile(),
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

/// The kind of file tasks are exported to and imported from.
const _tasksFiles = XTypeGroup(
  label: 'bringmeback tasks',
  extensions: ['json'],
  mimeTypes: ['application/json'],
  uniformTypeIdentifiers: ['public.json'],
);

/// A tasks file bigger than this is refused before it is read: the most tasks a file may hold fit
/// in far less.
const _maxTasksFileBytes = 5 * 1024 * 1024;

void _tell(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Saves today's note and the tasks waiting from earlier notes to a file, to keep or to import on
/// another device.
class _ExportTasksTile extends StatelessWidget {
  const _ExportTasksTile();

  Future<void> _export(BuildContext context) async {
    final text = context.read<TasksBloc>().exportTasksFile();
    if (text == null) return;
    final now = DateTime.now();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final name = 'bringmeback-tasks-$day.json';
    final file = XFile.fromData(Uint8List.fromList(utf8.encode(text)),
        mimeType: 'application/json', name: name);
    try {
      if (kIsWeb) {
        // A browser downloads the file; there is no save dialog to ask where.
        await file.saveTo(name);
      } else {
        final location = await getSaveLocation(
            suggestedName: name, acceptedTypeGroups: const [_tasksFiles]);
        if (location == null) return;
        await file.saveTo(location.path);
      }
      if (context.mounted) _tell(context, 'Tasks exported to $name.');
    } on UnimplementedError {
      // Phones running the app natively have no save dialog: hand the text over another way.
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        _tell(context, 'Saving files isn\'t possible here, so the tasks were copied instead.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('exportTasks'),
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Export tasks'),
        subtitle: const Text('Save today\'s note and the tasks waiting from earlier notes '
            'to a file.'),
        onTap: () => _export(context),
      );
}

/// Adds the tasks of an exported file. Tasks this device already has are left out.
class _ImportTasksTile extends StatelessWidget {
  const _ImportTasksTile();

  Future<void> _import(BuildContext context) async {
    final bloc = context.read<TasksBloc>();
    final picked = await openFile(acceptedTypeGroups: const [_tasksFiles]);
    if (picked == null || !context.mounted) return;
    final TasksFile file;
    try {
      if (await picked.length() > _maxTasksFileBytes) {
        throw const FormatException('This file is too big to be a tasks file.');
      }
      file = parseTasksFile(await picked.readAsString());
    } on FormatException catch (e) {
      if (context.mounted) _tell(context, e.message);
      return;
    }
    final event = ImportTasksEvent(file);
    bloc.add(event);
    final result = await event.result.future;
    if (context.mounted) _tell(context, result.summary);
  }

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('importTasks'),
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('Import tasks'),
        subtitle: const Text('Add the tasks of an exported file. They go below what you are '
            'doing; any that don\'t fit wait with the tasks of earlier notes.'),
        onTap: () => _import(context),
      );
}
