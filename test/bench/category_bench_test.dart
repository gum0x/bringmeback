// Measures categorisers on the tasks in bench_tasks.dart, in several languages. Needs the models on
// disk, so it runs only when BENCH_MODELS names them: .github/workflows/category-bench.yaml
// downloads them. Each entry is kind##name##path[##query prefix##document prefix], separated by ';',
// where kind is llm (a chat model) or embed (an embedding model).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:bringmeback/category/default_categories.dart';
import 'package:bringmeback/category/embedding_categoriser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'bench_tasks.dart';
import 'llm_categoriser.dart';

typedef Scorer = Future<Map<String, double>> Function(String text, List<TaskCategory> categories);

final categories = [
  for (final c in defaultCategories)
    TaskCategory(id: c.id, name: c.name, keywords: c.keywords, rules: c.rules),
];

void report(String text) {
  // ignore: avoid_print
  print(text);
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) File(summary).writeAsStringSync('$text\n', mode: FileMode.append);
}

/// Runs [score] over every task and reports accuracy per language: the top pick, and the top pick
/// when the categoriser is sure ([sure] says when).
Future<void> bench(String name, Scorer score, bool Function(List<double> ranked) sure,
    {String? size}) async {
  final rows = <String>[];
  var total = 0, totalSure = 0, sureRight = 0, n = 0;
  final watch = Stopwatch()..start();
  final misses = <String>[];
  for (final MapEntry(key: language, value: tasks) in benchTasks.entries) {
    var right = 0, confident = 0, confidentRight = 0;
    for (final (i, task) in tasks.indexed) {
      final expected = benchCategories[i];
      final scores = await score(task, categories);
      final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final got = ranked.isEmpty ? null : ranked.first.key;
      final isSure = ranked.isNotEmpty && sure([for (final e in ranked) e.value]);
      if (got == expected) right++;
      if (isSure) {
        confident++;
        if (got == expected) confidentRight++;
      }
      if (got != expected) {
        misses.add('$language: $task => $got, expected $expected '
            '(${ranked.take(3).map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(', ')})');
      }
      n++;
    }
    total += right;
    totalSure += confident;
    sureRight += confidentRight;
    rows.add('| $language | $right/${tasks.length} | $confidentRight/$confident |');
  }
  report([
    '',
    '### $name${size == null ? '' : ' ($size)'}',
    '',
    'Top pick right: **$total/$n**. When sure: $sureRight right of $totalSure picks. '
        '${watch.elapsedMilliseconds ~/ n} ms a task.',
    '',
    '| Language | Top pick right | Right when sure |',
    '| --- | --- | --- |',
    ...rows,
    '',
    '<details><summary>Misses</summary>',
    '',
    ...misses.map((m) => '- $m'),
    '',
    '</details>',
  ].join('\n'));
}

String sizeOf(String path) => '${(File(path).lengthSync() / 1e6).round()} MB';

void main() {
  final models = Platform.environment['BENCH_MODELS'];

  test('word vectors', () async {
    final words = Categoriser(WordVectors.parse(
        ByteData.sublistView(File('assets/word_vectors.bin').readAsBytesSync())));
    await bench('Word vectors (built in)', (text, categories) async {
      final s = words.scores(text, categories);
      return s;
    }, (ranked) => ranked.first >= Categoriser.threshold, size: '4 MB');
  });

  for (final entry in (models ?? '').split(';').where((e) => e.trim().isNotEmpty)) {
    final [kind, name, path, ...prefixes] = entry.split('##');
    test(name, () async {
      if (!File(path).existsSync()) {
        report('\n### $name\n\nNot downloaded.');
        return;
      }
      try {
        if (kind == 'llm') {
          final llm = await LlmCategoriser.load(model: ModelSource.path(path));
          try {
            await bench(name, (text, categories) => llm.scores(text, categories),
                (ranked) => ranked.first >= LlmCategoriser.threshold,
                size: sizeOf(path));
            for (final task in ['Fix the login bug', 'Standup with the team']) {
              report('\n<details><summary>What $name sees for "$task"</summary>\n\n```\n'
                  '${await llm.explain(task, categories)}\n```\n</details>');
            }
          } finally {
            await llm.dispose();
          }
        } else {
          for (final describe in [true, false]) {
            final embed = await EmbeddingCategoriser.load(ModelSource.path(path),
                queryPrefix: (prefixes.elementAtOrNull(0) ?? '').replaceAll(r'\n', '\n'),
                documentPrefix: (prefixes.elementAtOrNull(1) ?? '').replaceAll(r'\n', '\n'),
                describe: describe);
            try {
              await bench(
                  '$name, ${describe ? 'keywords and samples' : 'samples only'}',
                  (text, categories) => embed.scores(text, categories),
                  (ranked) =>
                      ranked.length < 2 || ranked[0] - ranked[1] >= EmbeddingCategoriser.margin,
                  size: sizeOf(path));
            } finally {
              await embed.dispose();
            }
          }
        }
      } on Object catch (e) {
        report('\n### $name\n\nFailed: $e');
      }
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}
