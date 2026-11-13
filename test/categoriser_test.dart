import 'dart:io';
import 'dart:typed_data';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Categoriser categoriser;
  final categories = [
    for (final (i, s) in suggestedCategories.indexed)
      TaskCategory(id: s.name.toLowerCase(), name: s.name, keywords: s.keywords, addedAt: i),
  ];

  setUpAll(() {
    final bytes = File(wordVectorsAsset).readAsBytesSync();
    categoriser = Categoriser(WordVectors.parse(ByteData.sublistView(bytes)));
  });

  test('the bundled vectors put related words close together', () {
    final v = categoriser.vectors;
    double sim(String a, String b) {
      final x = v[a]!, y = v[b]!;
      var s = 0.0;
      for (var i = 0; i < x.length; i++) {
        s += x[i] * y[i];
      }
      return s;
    }

    expect(sim('dentist', 'doctor'), greaterThan(sim('dentist', 'invoice')));
    expect(v['zzqxj'], isNull);
  });

  test('files everyday tasks under the suggested categories', () {
    const tasks = {
      'fix login bug in the client project': 'work',
      'reply to Ana about the report': 'work',
      'prepare slides for the meeting': 'work',
      'book dentist appointment': 'health',
      'go for a run': 'health',
      'pick up prescription': 'health',
      'clean the kitchen': 'home',
      'do the laundry': 'home',
      'water the plants': 'home',
      'buy milk': 'errands',
      'get groceries': 'errands',
      'pay electricity bill': 'money',
      'file tax return': 'money',
      'read chapter 3 of the rust book': 'learning',
      'spanish lesson': 'learning',
      'call mom': 'people',
      'dinner with friends': 'people',
    };
    final wrong = <String>[];
    for (final MapEntry(key: task, value: expected) in tasks.entries) {
      final got = categoriser.categorise(task, categories);
      final s = categoriser.scores(task, categories);
      // ignore: avoid_print
      print('$task -> $got  ${[for (final e in s.entries) '${e.key}:${e.value.toStringAsFixed(2)}'].join(' ')}');
      if (got != expected) wrong.add('$task: $got, expected $expected');
    }
    // A few misses are fine: the user corrects them and the categoriser learns.
    expect(wrong.length, lessThanOrEqualTo(3), reason: wrong.join('\n'));
  });

  test('leaves a task with nothing to go on without a category', () {
    expect(categoriser.categorise('asdf qwerty', categories), isNull);
    expect(categoriser.categorise('', categories), isNull);
    expect(categoriser.categorise('buy milk', const []), isNull);
  });

  test('learns from tasks filed by hand', () {
    const text = 'standup';
    expect(categoriser.categorise(text, categories), isNot('work'));
    expect(
        categoriser.categorise('daily standup', categories,
            examples: [(text: 'standup with the team', category: 'work')]),
        'work');
    // A category's own words still win over an example that is only a bit alike.
    expect(
        categoriser.categorise('call mom', categories,
            examples: [(text: 'call the bank', category: 'money')]),
        'people');
    // An example under a category no longer in the list is ignored.
    expect(
        categoriser.categorise('standup', categories,
            examples: [(text: 'standup', category: 'gone')]),
        isNot('gone'));
  });
}
