import 'dart:io';
import 'dart:typed_data';

import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:bringmeback/category/default_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Categoriser categoriser;
  final categories = [
    for (final d in defaultCategories) TaskCategory(id: d.id, name: d.name, keywords: d.keywords),
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
      'read work emails': 'work-planning',
      'prepare tomorrow\'s work': 'work-planning',
      'weekly KPIs': 'work-planning',
      'fix login bug': 'focused-work',
      'write the design doc': 'focused-work',
      'standup with the team': 'meetings',
      'call with the client': 'meetings',
      'read chapter 3 of the rust book': 'learning',
      'spanish lesson': 'learning',
      'clean the kitchen': 'housekeeping',
      'do the laundry': 'housekeeping',
      'water the plants': 'housekeeping',
      'buy milk': 'errands',
      'get groceries': 'errands',
      'pay electricity bill': 'money-paperwork',
      'file tax return': 'money-paperwork',
      'go for a run': 'workout-self-care',
      'book dentist appointment': 'workout-self-care',
      'yoga class': 'workout-self-care',
      'call mom': 'family-friends',
      'dinner with friends': 'family-friends',
      'watch a movie': 'leisure',
      'plan the summer trip': 'leisure',
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

  test('a rule files a task whatever else it says, longest phrase first', () {
    final withRules = [
      for (final c in categories)
        if (c.id == 'personal-projects')
          TaskCategory(id: c.id, name: c.name, keywords: c.keywords, rules: 'bringmeback, BMB')
        else if (c.id == 'meetings')
          TaskCategory(id: c.id, name: c.name, keywords: c.keywords, rules: 'bringmeback sync call')
        else
          c,
    ];
    expect(categoriser.categorise('Fix the login bug in Bringmeback', withRules),
        'personal-projects');
    expect(categoriser.categorise('bmb: review PR', withRules), 'personal-projects');
    expect(categoriser.categorise('Bringmeback sync call', withRules), 'meetings');
    // Whole words only.
    expect(Categoriser.byRule('bringmebacks', withRules), isNull);
    expect(Categoriser.byRule('café run', [
      const TaskCategory(id: 'x', name: 'X', rules: 'Café'),
    ]), 'x');
  });

  test('leaves a task with nothing to go on without a category', () {
    expect(categoriser.categorise('asdf qwerty', categories), isNull);
    expect(categoriser.categorise('', categories), isNull);
    expect(categoriser.categorise('buy milk', const []), isNull);
  });

  test('learns from tasks filed by hand', () {
    expect(categoriser.categorise('groom the backlog', categories), isNot('personal-projects'));
    expect(
        categoriser.categorise('groom the backlog', categories,
            examples: [(text: 'backlog grooming', category: 'personal-projects')]),
        'personal-projects');
    // A category's own words still win over an example that is only a bit alike.
    expect(
        categoriser.categorise('call mom', categories,
            examples: [(text: 'call the bank', category: 'money-paperwork')]),
        'family-friends');
    // An example under a category no longer in the list is ignored.
    expect(
        categoriser.categorise('standup', categories,
            examples: [(text: 'standup', category: 'gone')]),
        isNot('gone'));
  });
}
