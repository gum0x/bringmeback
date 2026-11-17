// Categorises real tasks with the real LFM2.5 model. Needs the model on disk, so it runs only
// when LFM_MODEL_PATH names it: the "LFM2.5" job in .github/workflows/cicd.yaml downloads it.
@TestOn('vm')
library;

import 'dart:io';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/category/default_categories.dart';
import 'package:bringmeback/category/lfm_categoriser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  final path = Platform.environment['LFM_MODEL_PATH'];

  test('LFM2.5 files everyday tasks where a person would', () async {
    final lfm = await LfmCategoriser.load(model: ModelSource.path(path!));
    addTearDown(lfm.dispose);
    final categories = [
      for (final c in defaultCategories)
        TaskCategory(id: c.id, name: c.name, keywords: c.keywords, rules: c.rules),
    ];
    const tasks = {
      'Read work emails': 'work-planning',
      'Prepare tomorrow\'s work': 'work-planning',
      'Weekly KPIs': 'work-planning',
      'Fix the login bug': 'focused-work',
      'Standup with the team': 'meetings',
      'Clean the bathroom': 'housekeeping',
      'Do the laundry': 'housekeeping',
      'Buy milk and bread': 'errands',
      'Pay the electricity bill': 'money-paperwork',
      'Go to the gym': 'workout-self-care',
      'Book a dentist appointment': 'workout-self-care',
      'Call mom': 'family-friends',
      'Spanish lesson': 'learning',
      'Watch a movie': 'leisure',
    };
    var right = 0;
    final watch = Stopwatch()..start();
    for (final MapEntry(key: task, value: expected) in tasks.entries) {
      final scores = await lfm.scores(task, categories);
      final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final got = await lfm.categorise(task, categories);
      if (got == expected) right++;
      // ignore: avoid_print
      print('${got == expected ? 'ok  ' : 'MISS'} $task => $got (expected $expected; '
          '${ranked.take(3).map((e) => '${e.key} ${(e.value * 100).round()}%').join(', ')})');
    }
    // ignore: avoid_print
    print('$right of ${tasks.length} right, '
        '${watch.elapsedMilliseconds ~/ tasks.length} ms a task on ${await lfm.backendName}');
    expect(right, greaterThanOrEqualTo(tasks.length * 0.7));
  }, skip: path == null ? 'Set LFM_MODEL_PATH to a downloaded LFM2.5 GGUF file' : null,
      timeout: const Timeout(Duration(minutes: 10)));
}
