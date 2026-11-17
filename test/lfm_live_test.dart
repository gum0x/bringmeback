// Categorises real tasks with the real LFM2.5 model. Needs the models on disk, so it runs only
// when LFM_MODEL_PATHS names them: the "LFM2.5" job in .github/workflows/cicd.yaml downloads them.
@TestOn('vm')
library;

import 'dart:io';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/category/default_categories.dart';
import 'package:bringmeback/category/lfm_categoriser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  final paths = Platform.environment['LFM_MODEL_PATHS']?.split(',');

  for (final path in paths ?? ['(none)']) {
    test('LFM2.5 at $path files everyday tasks where a person would', () async {
      final lfm = await LfmCategoriser.load(model: ModelSource.path(path));
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
        'Water the plants': 'housekeeping',
        'Renew my passport': 'money-paperwork',
        'Birthday gift for Ana': 'family-friends',
        'Run 5k': 'workout-self-care',
        'Plan the next sprint': 'work-planning',
        'Concert tickets': 'leisure',
        // The word vectors only know English: these are what the model is for.
        'Leer los correos del trabajo': 'work-planning',
        'Preparar la reunión con el cliente': 'meetings',
        'Limpiar la cocina': 'housekeeping',
        'Comprar pan y leche': 'errands',
        'Pagar la factura de la luz': 'money-paperwork',
        'Ir al gimnasio': 'workout-self-care',
        'Llamar a mamá': 'family-friends',
        'Clase de inglés': 'learning',
        'Ver una película': 'leisure',
        'Arreglar el bug del login': 'focused-work',
      };
      final right = <PromptStyle, int>{};
      for (final style in PromptStyle.values) {
        LfmCategoriser.style = style;
        var n = 0;
        final misses = <String>[];
        final watch = Stopwatch()..start();
        for (final MapEntry(key: task, value: expected) in tasks.entries) {
          final scores = await lfm.scores(task, categories);
          final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final top = ranked.first;
          final got = top.value >= LfmCategoriser.threshold ? top.key : null;
          if (got == expected) {
            n++;
          } else {
            misses.add('$task => $got (expected $expected; '
                '${ranked.take(3).map((e) => '${e.key} ${(e.value * 100).round()}%').join(', ')})');
          }
        }
        right[style] = n;
        // ignore: avoid_print
        print('${style.name}: $n of ${tasks.length} right, '
            '${watch.elapsedMilliseconds ~/ tasks.length} ms a task on ${await lfm.backendName}\n'
            '${misses.map((m) => '  MISS $m').join('\n')}');
      }
      LfmCategoriser.style = PromptStyle.turns;
      // ignore: avoid_print
      print(await lfm.explain('Watch a movie', categories));
      expect(right[LfmCategoriser.style], greaterThanOrEqualTo(tasks.length * 0.6));
    },
        skip: paths == null ? 'Set LFM_MODEL_PATHS to downloaded LFM2.5 GGUF files' : null,
        timeout: const Timeout(Duration(minutes: 20)));
  }
}
