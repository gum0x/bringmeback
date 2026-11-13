import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/task_document.dart';
import '../bloc/tasks_bloc.dart';
import '../timer.dart';
import 'paper.dart';
import 'task_line.dart';

/// The Now view: today's note, with what is left of the last note waiting above it. When the note
/// was started on an earlier day, it has to be torn off first.
class NoteView extends StatelessWidget {
  const NoteView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(builder: (context, state) {
      if (!state.loaded) return const SizedBox.shrink();
      if (state.needsTearOff()) return TearOffView(state: state);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                if (state.pending.isNotEmpty) ...[
                  CarryOverPanel(pending: state.pending, full: state.full),
                  const SizedBox(height: 24),
                ],
                _TodayNote(state: state),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The time committed to on the note, and roughly when it will all be done. The finish is rounded
/// up to the quarter hour, so it reads as an estimate rather than another ticking clock. Breaks are
/// not counted.
class _CommittedTime extends StatelessWidget {
  final TasksState state;

  const _CommittedTime({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NoteColors.of(context);
    final over = state.overCommitted;
    final finish = state.finishAt();
    final committed = formatMinutes((state.committedSeconds / 60).round());
    final finishTime = finish == null
        ? null
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(finish * 1000))
            .format(context);
    return Text.rich(
      key: const Key('committedTime'),
      TextSpan(children: [
        TextSpan(
          text: 'Committed $committed',
          style: over
              ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)
              : null,
        ),
        if (over) TextSpan(text: ' of ${formatMinutes(state.noteMinutes)}'),
        if (finishTime != null) TextSpan(text: ' · done by ~$finishTime'),
      ]),
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.faded),
    );
  }
}

class _TodayNote extends StatelessWidget {
  final TasksState state;

  const _TodayNote({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = NoteColors.of(context);
    final theme = Theme.of(context);
    final tasks = state.tasks;
    final current = state.currentIndex;
    final done = tasks.where((t) => t.done).length;
    final left = state.noteLines - tasks.length;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDay(context, dayOf(state.noteStartedAt)),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.ink, fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    if (tasks.isNotEmpty) '$done of ${tasks.length} done',
                    if (left <= 3) left <= 0 ? 'note full' : '$left ${left == 1 ? 'line' : 'lines'} left',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.faded),
                ),
                if (tasks.isNotEmpty) _CommittedTime(state: state),
              ],
            ),
          ),
          PopupMenuButton<void>(
            tooltip: 'Note actions',
            icon: Icon(Icons.more_horiz, color: colors.faded),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: tasks.isNotEmpty,
                onTap: () => _confirmFreshNote(context),
                child: const ListTile(
                    leading: Icon(Icons.note_add_outlined),
                    title: Text('Tear off and start a fresh note')),
              ),
            ],
          ),
        ],
      ),
    );

    final list = ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: tasks.length,
      proxyDecorator: (child, index, animation) => Material(
        color: colors.paper,
        elevation: 6,
        child: child,
      ),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskLine(
          key: task.id,
          task: task,
          index: index,
          current: index == current,
          canInsert: !state.full,
        );
      },
      onReorderItem: (oldIndex, newIndex) => context
          .read<TasksBloc>()
          .add(MoveTaskEvent(fromIndex: oldIndex, toIndex: newIndex)),
    );

    // The next empty line on the paper, to write on.
    final nextLine = state.full
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Text(
              'The note is full. Finish what is on it, or start a fresh note.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.faded, fontStyle: FontStyle.italic),
            ),
          )
        : InkWell(
            onTap: () => writeTask(context, index: tasks.length),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(children: [
                SizedBox(
                  width: 30,
                  child: Text('${tasks.length + 1}.',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.faded.withValues(alpha: 0.5))),
                ),
                const SizedBox(width: 16),
                Icon(Icons.add, size: 20, color: colors.faded),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    tasks.isEmpty ? 'Write your first task' : 'Add a task',
                    style: theme.textTheme.titleMedium?.copyWith(color: colors.faded),
                  ),
                ),
              ]),
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        NotePaper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Text(
                    'A short list keeps the day focused. Write what you will do today, the most '
                    'important first. The first task not done is the one being timed.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: colors.faded),
                  ),
                ),
              if (state.onBreak) BreakLine(state: state),
              list,
              nextLine,
            ],
          ),
        ),
        if (state.allDone)
          const Positioned(top: 10, right: 52, child: _DoneStamp()),
      ],
    );
  }

  Future<void> _confirmFreshNote(BuildContext context) async {
    final bloc = context.read<TasksBloc>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a fresh note?'),
        content: const Text(
            'This note is kept in History. What is not done yet waits for you to write it '
            'again on the fresh note, or let it go.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tear it off')),
        ],
      ),
    );
    if (yes == true) bloc.add(TearOffNoteEvent());
  }
}

/// A rubber stamp that lands on the note when every task on it is done.
class _DoneStamp extends StatelessWidget {
  const _DoneStamp();

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.rotate(
          angle: -0.18,
          child: Transform.scale(scale: 2 - t, child: child),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: green.withValues(alpha: 0.8), width: 2.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'ALL DONE',
          style: TextStyle(
            color: green.withValues(alpha: 0.85),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

/// The unfinished tasks of the last note, waiting to be written again on today's note, in the order
/// they will be done, or let go.
class CarryOverPanel extends StatelessWidget {
  final List<TaskState> pending;
  final bool full;

  const CarryOverPanel({super.key, required this.pending, required this.full});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<TasksBloc>();
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not finished on your last note', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                full
                    ? 'Today\'s note is full. Let go of these, or make room first.'
                    : 'Write again what still matters, in the order you will do it. '
                        'Let go of the rest.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            for (final task in pending)
              Padding(
                key: task.id,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(task.name.isEmpty ? 'Untitled task' : task.name,
                          style: theme.textTheme.bodyLarge),
                    ),
                    IconButton(
                      tooltip: 'Let go',
                      onPressed: () => bloc.add(LetGoEvent(id: task.id.value)),
                      icon: const Icon(Icons.close),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: full
                          ? null
                          : () => bloc.add(CarryTaskEvent(id: task.id.value)),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Write again'),
                    ),
                  ],
                ),
              ),
            if (pending.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => bloc.add(LetGoEvent()),
                  child: const Text('Let go of all'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the note was started on an earlier day: tear it off, by swiping it away or with the
/// button, to start today's.
class TearOffView extends StatefulWidget {
  final TasksState state;

  const TearOffView({super.key, required this.state});

  @override
  State<TearOffView> createState() => _TearOffViewState();
}

class _TearOffViewState extends State<TearOffView> {
  bool _tearing = false;

  void _tearOff() {
    if (_tearing) return;
    setState(() => _tearing = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final unfinished = state.tasks.where((t) => !t.done).length;
    final done = state.tasks.length - unfinished;

    final sheet = NoteSheet(
      title: formatDay(context, dayOf(state.noteStartedAt)),
      subtitle: '$done of ${state.tasks.length} done',
      lines: [
        for (final t in state.tasks)
          NoteSheetLine(
              name: t.name, status: t.done ? TaskStatus.done : TaskStatus.open)
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Text('A new day', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                unfinished == 0
                    ? 'Everything on your last note is done. Tear it off and start today\'s.'
                    : 'Tear off your last note to start today\'s. The $unfinished '
                        '${unfinished == 1 ? 'task' : 'tasks'} not done will wait for you to '
                        'write ${unfinished == 1 ? 'it' : 'them'} again, or let go.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              Dismissible(
                key: ValueKey('note-${state.noteStartedAt}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) =>
                    context.read<TasksBloc>().add(TearOffNoteEvent()),
                child: AnimatedSlide(
                  offset: _tearing ? const Offset(1.4, -0.4) : Offset.zero,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeInCubic,
                  onEnd: () {
                    if (_tearing) context.read<TasksBloc>().add(TearOffNoteEvent());
                  },
                  child: AnimatedRotation(
                    turns: _tearing ? 0.06 : 0,
                    duration: const Duration(milliseconds: 420),
                    child: sheet,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _tearOff,
                icon: const Icon(Icons.swipe_right_alt),
                label: const Text('Tear it off'),
              ),
              const SizedBox(height: 8),
              Text('or swipe the note away',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line of a read-only note.
class NoteSheetLine {
  final String name;
  final TaskStatus status;
  final String? trailing;

  const NoteSheetLine({required this.name, required this.status, this.trailing});
}

/// A note as it was written, read-only: for tearing off and for History.
class NoteSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<NoteSheetLine> lines;

  const NoteSheet({super.key, required this.title, this.subtitle, required this.lines});

  @override
  Widget build(BuildContext context) {
    final colors = NoteColors.of(context);
    final theme = Theme.of(context);
    return NotePaper(
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600)),
          if (subtitle != null)
            Text(subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.faded)),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing written',
                  style: TextStyle(color: colors.faded, fontStyle: FontStyle.italic)),
            ),
          for (final (i, line) in lines.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.rule))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    child: Text('${i + 1}.',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: colors.faded)),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(statusIcon(line.status), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StrikeText(
                      line.name.isEmpty ? 'Untitled task' : line.name,
                      struck: line.status == TaskStatus.done,
                      animate: false,
                      style: TextStyle(
                        color: line.status == TaskStatus.letGo ||
                                line.status == TaskStatus.carried
                            ? colors.faded
                            : colors.ink,
                      ),
                    ),
                  ),
                  if (line.trailing != null) ...[
                    const SizedBox(width: 8),
                    Text(line.trailing!,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.faded)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

IconData statusIcon(TaskStatus status) => switch (status) {
      TaskStatus.done => Icons.check_box_outlined,
      TaskStatus.open => Icons.check_box_outline_blank,
      TaskStatus.pending => Icons.hourglass_empty,
      TaskStatus.carried => Icons.redo,
      TaskStatus.letGo => Icons.close,
      TaskStatus.deleted => Icons.delete_outline,
    };

/// "Monday, 9 November 2026" in the app's locale, or "Today" and "Yesterday".
String formatDay(BuildContext context, DateTime day) {
  final today = dayOf(nowSeconds());
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return MaterialLocalizations.of(context).formatFullDate(day);
}
