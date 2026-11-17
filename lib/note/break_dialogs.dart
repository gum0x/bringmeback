import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/breaks.dart';
import '../bloc/tasks_bloc.dart';
import '../timer.dart';

/// Offers the break types set in Settings, and a plain pause with no timer. Picking one pauses the
/// work and starts that break; on a break already, it changes the break under way.
Future<void> chooseBreak(BuildContext context) async {
  final bloc = context.read<TasksBloc>();
  final state = bloc.state;
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(state.onBreak ? 'Change the break' : 'Take a break',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Give it the time it needs, then get back to your tasks.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            for (final c in state.breakCategories)
              ListTile(
                key: ValueKey('break-category-${c.name}'),
                leading: Icon(breakIcon(c.icon)),
                title: Text(c.name),
                trailing: Text(formatMinutes(c.minutes)),
                onTap: () => Navigator.pop(context, _Pick(c.name, c.minutes * 60)),
              ),
            ListTile(
              key: const ValueKey('break-category-plain'),
              leading: const Icon(Icons.pause),
              title: const Text('Just pause'),
              subtitle: const Text('No timer: back when you are back'),
              onTap: () => Navigator.pop(context, const _Pick(null, null)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return;
  bloc.add(TakeBreakEvent(reason: picked.reason, plannedSeconds: picked.seconds));
}

class _Pick {
  final String? reason;
  final int? seconds;

  const _Pick(this.reason, this.seconds);
}

/// Changes what the break under way is for and how long it should last.
Future<void> editBreak(BuildContext context) async {
  final bloc = context.read<TasksBloc>();
  if (!bloc.state.onBreak) return;
  final result = await showDialog<_Pick>(
    context: context,
    builder: (context) => _EditBreakDialog(state: bloc.state),
  );
  if (result == null || !bloc.state.onBreak) return;
  bloc.add(EditBreakEvent(reason: result.reason, plannedSeconds: result.seconds));
}

class _EditBreakDialog extends StatefulWidget {
  final TasksState state;

  const _EditBreakDialog({required this.state});

  @override
  State<_EditBreakDialog> createState() => _EditBreakDialogState();
}

class _EditBreakDialogState extends State<_EditBreakDialog> {
  late final TextEditingController _reason =
      TextEditingController(text: widget.state.breakReason ?? '');
  late final TextEditingController _minutes = TextEditingController(
      text: widget.state.breakPlannedSeconds == null
          ? ''
          : '${(widget.state.breakPlannedSeconds! / 60).ceil()}');

  @override
  void dispose() {
    _reason.dispose();
    _minutes.dispose();
    super.dispose();
  }

  int? get _readMinutes => int.tryParse(_minutes.text.trim());

  void _save() {
    final minutes = _readMinutes;
    Navigator.pop(
        context,
        _Pick(_reason.text.trim().isEmpty ? null : _reason.text.trim(),
            minutes == null || minutes <= 0 ? null : minutes * 60));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _readMinutes;
    final elapsed = widget.state.breakSecondsAt(nowSeconds());
    final String? hint;
    if (minutes != null && minutes > 0 && minutes < recommendedBreakMinutes) {
      hint = 'Breaks under $recommendedBreakMinutes min rarely rest you. Take a proper one.';
    } else if (minutes != null && minutes > 0 && minutes * 60 <= elapsed) {
      hint = 'That is already over: the break has lasted ${formatClock(elapsed)}.';
    } else {
      hint = null;
    }
    return AlertDialog(
      title: const Text('Change the break'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.state.breakCategories.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in widget.state.breakCategories)
                    ChoiceChip(
                      avatar: Icon(breakIcon(c.icon), size: 18),
                      label: Text('${c.name} · ${formatMinutes(c.minutes)}'),
                      selected: _reason.text.trim() == c.name,
                      onSelected: (_) => setState(() {
                        _reason.text = c.name;
                        _minutes.text = '${c.minutes}';
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _minutes,
              decoration: const InputDecoration(
                  labelText: 'Break minutes', helperText: 'From when it started. Empty: no timer'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(hint,
                    key: const ValueKey('break-hint'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.tertiary)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
