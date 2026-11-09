import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the task dialog returns: the name and the countdown length.
typedef TaskDetails = ({String name, String notes, int timerLengthSeconds});

/// Countdown lengths offered with one tap, in minutes.
const _presetMinutes = [10, 20, 25, 45];

/// Asks for a task's name and countdown length, to write a new task or edit one. Returns null when
/// cancelled.
Future<TaskDetails?> showTaskDialog(BuildContext context,
    {String name = '',
    String notes = '',
    int timerLengthSeconds = 20 * 60,
    bool editing = false}) {
  return showDialog<TaskDetails>(
    context: context,
    builder: (context) => _TaskDialog(
        name: name,
        notes: notes,
        timerLengthSeconds: timerLengthSeconds,
        editing: editing),
  );
}

class _TaskDialog extends StatefulWidget {
  final String name;
  final String notes;
  final int timerLengthSeconds;
  final bool editing;

  const _TaskDialog(
      {required this.name,
      required this.notes,
      required this.timerLengthSeconds,
      required this.editing});

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _notes =
      TextEditingController(text: widget.notes);
  late final TextEditingController _minutes =
      TextEditingController(text: '${widget.timerLengthSeconds ~/ 60}');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _minutes.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _minutes.dispose();
    super.dispose();
  }

  int? get _validMinutes => switch (int.tryParse(_minutes.text)) {
        final m? when m > 0 => m,
        _ => null,
      };

  bool get _canSave => _name.text.trim().isNotEmpty && _validMinutes != null;

  void _save() {
    if (!_canSave) return;
    Navigator.pop<TaskDetails>(context, (
        name: _name.text.trim(),
        notes: _notes.text.trim(),
        timerLengthSeconds: _validMinutes! * 60));
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _validMinutes;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.editing ? 'Edit task' : 'New task'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              // Long names wrap onto more lines; Enter still saves.
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Task',
                hintText: 'What will you do?',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details',
                hintText: 'Notes, links, steps… (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Countdown', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final m in _presetMinutes)
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: minutes == m,
                    onSelected: (_) => _minutes.text = '$m',
                  ),
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: _canSave ? _save : null,
            child: Text(widget.editing ? 'Save' : 'Add')),
      ],
    );
  }
}
