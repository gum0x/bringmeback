import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the task dialog returns: the name and the countdown length.
typedef TaskDetails = ({String name, String notes, int timerLengthSeconds});

/// Countdown lengths offered with one tap, in minutes.
const _presetMinutes = [10, 20, 25, 45];

/// The countdown a new task starts with when picking one isn't required.
const defaultTimerLengthSeconds = 20 * 60;

/// Asks for a task's name and countdown length, to write a new task or edit one. Returns null when
/// cancelled. A null [timerLengthSeconds] leaves the countdown unpicked: the task can't be saved
/// until one is chosen.
Future<TaskDetails?> showTaskDialog(BuildContext context,
    {String name = '',
    String notes = '',
    int? timerLengthSeconds = defaultTimerLengthSeconds,
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
  final int? timerLengthSeconds;
  final bool editing;

  const _TaskDialog(
      {required this.name,
      required this.notes,
      this.timerLengthSeconds,
      required this.editing});

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _notes =
      TextEditingController(text: widget.notes);
  late final TextEditingController _minutes = TextEditingController(
      text: switch (widget.timerLengthSeconds) {
    final s? => '${s ~/ 60}',
    null => '',
  });
  final _countdownKey = GlobalKey();

  /// Set once saving was tried without a countdown, to say what is missing.
  bool _askedForTime = false;

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
    if (_name.text.trim().isNotEmpty && _validMinutes == null) {
      // The keyboard can hide the countdown on a phone: put it away and bring the choice in view.
      FocusScope.of(context).unfocus();
      setState(() => _askedForTime = true);
      final countdown = _countdownKey.currentContext;
      if (countdown != null) {
        Scrollable.ensureVisible(countdown, duration: const Duration(milliseconds: 200));
      }
      return;
    }
    if (!_canSave) return;
    Navigator.pop<TaskDetails>(context, (
        name: _name.text.trim(),
        notes: _notes.text.trim(),
        timerLengthSeconds: _validMinutes! * 60));
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _validMinutes;
    final missingTime = minutes == null;
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
            Row(
              key: _countdownKey,
              children: [
                Text('How long?', style: Theme.of(context).textTheme.labelLarge),
                if (missingTime) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                        _askedForTime
                            ? 'Pick a countdown to ${widget.editing ? 'save' : 'add'} the task'
                            : 'Required',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _askedForTime
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                ],
              ],
            ),
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
                    onSelected: (_) {
                      _minutes.text = '$m';
                      setState(() => _askedForTime = false);
                    },
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
                      hintText: 'other',
                      // Floating, the label fits the narrow field even while it is empty.
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            // With a name but no countdown, Add stays tappable to point to what is missing.
            onPressed: _name.text.trim().isNotEmpty ? _save : null,
            child: Text(widget.editing ? 'Save' : 'Add')),
      ],
    );
  }
}
