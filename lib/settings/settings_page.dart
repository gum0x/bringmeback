import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tasks_bloc.dart';

/// How the app behaves on this device. Settings are saved here and are not synced.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Today\'s note',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
              const _NoteLinesTile(),
            ],
          ),
        ),
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
      builder: (context, state) {
        final lines = state.noteLines;
        return ListTile(
          title: const Text('Tasks per note'),
          subtitle: const Text(
              'A small note keeps the day focused. Done tasks count too. '
              'Making it smaller keeps what is already written.'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Fewer tasks per note',
                onPressed: lines > minNoteLines
                    ? () => bloc.add(SetNoteLinesEvent(lines - 1))
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 32,
                child: Text('$lines',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              IconButton(
                tooltip: 'More tasks per note',
                onPressed: lines < maxNoteLines
                    ? () => bloc.add(SetNoteLinesEvent(lines + 1))
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        );
      },
    );
  }
}
