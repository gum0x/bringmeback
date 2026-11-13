import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bloc/task_document.dart';
import '../bloc/tasks_bloc.dart';

/// What the task dialog returns: the name, details, countdown length and category.
typedef TaskDetails = ({
  String name,
  String notes,
  int timerLengthSeconds,
  CategoryPick category
});

/// Countdown lengths offered with one tap, in minutes.
const _presetMinutes = [10, 20, 25, 45];

/// Asks for a task's name, countdown length and category, to write a new task or edit one. Returns
/// null when cancelled.
///
/// The category is picked from [categories], and left to the categoriser by default. [autoCategory]
/// is the one the categoriser chose for the task being edited, shown on that choice.
Future<TaskDetails?> showTaskDialog(BuildContext context,
    {String name = '',
    String notes = '',
    int timerLengthSeconds = 20 * 60,
    List<TaskCategory> categories = const [],
    CategoryPick category = const CategoryPick.auto(),
    String? autoCategory,
    bool editing = false}) {
  return showDialog<TaskDetails>(
    context: context,
    builder: (context) => _TaskDialog(
        name: name,
        notes: notes,
        timerLengthSeconds: timerLengthSeconds,
        categories: categories,
        category: category,
        autoCategory: autoCategory,
        editing: editing),
  );
}

class _TaskDialog extends StatefulWidget {
  final String name;
  final String notes;
  final int timerLengthSeconds;
  final List<TaskCategory> categories;
  final CategoryPick category;
  final String? autoCategory;
  final bool editing;

  const _TaskDialog(
      {required this.name,
      required this.notes,
      required this.timerLengthSeconds,
      required this.categories,
      required this.category,
      required this.autoCategory,
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
  late CategoryPick _category = widget.category;

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
        timerLengthSeconds: _validMinutes! * 60,
        category: _category));
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
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Category', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _CategoryChoice(
                categories: widget.categories,
                value: _category,
                autoCategory: widget.autoCategory,
                onChanged: (pick) => setState(() => _category = pick),
              ),
            ],
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

/// Chips to pick a task's category: automatic (the categoriser picks), one of the list, or none.
class _CategoryChoice extends StatelessWidget {
  final List<TaskCategory> categories;
  final CategoryPick value;
  final String? autoCategory;
  final ValueChanged<CategoryPick> onChanged;

  const _CategoryChoice(
      {required this.categories,
      required this.value,
      required this.autoCategory,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Tooltip(
          message: 'Chosen on this device from the task\'s name',
          child: ChoiceChip(
            avatar: const Icon(Icons.auto_awesome, size: 18),
            label: Text(autoCategory == null ? 'Automatic' : 'Automatic: $autoCategory'),
            selected: !value.byHand,
            onSelected: (_) => onChanged(const CategoryPick.auto()),
          ),
        ),
        for (final c in categories)
          ChoiceChip(
            label: Text(c.name),
            selected: value.byHand && value.id == c.id,
            onSelected: (_) => onChanged(CategoryPick.hand(c.id)),
          ),
        ChoiceChip(
          label: const Text('None'),
          selected: value.byHand && value.id == null,
          onSelected: (_) => onChanged(const CategoryPick.hand(null)),
        ),
      ],
    );
  }
}
