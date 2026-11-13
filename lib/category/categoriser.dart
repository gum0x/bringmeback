import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../bloc/task_document.dart';

/// The word vectors the categoriser runs on, bundled with the app (see `tool/build_word_vectors.py`).
const wordVectorsAsset = 'assets/word_vectors.bin';

/// Word vectors: each word as a point in space, where words used alike sit close together, so
/// "dentist" lands near "health" without either being told about the other.
///
/// Read from [wordVectorsAsset]. Everything runs on the device, in Dart, on every platform.
class WordVectors {
  final int dims;
  final Int8List _vectors;
  final Map<String, int> _rows;

  WordVectors._(this.dims, this._vectors, this._rows);

  /// Reads the format `tool/build_word_vectors.py` writes.
  factory WordVectors.parse(ByteData data) {
    String magic() => String.fromCharCodes([for (var i = 0; i < 4; i++) data.getUint8(i)]);
    if (data.lengthInBytes < 15 || magic() != 'BMBV' || data.getUint8(4) != 1) {
      throw const FormatException('Not a word vectors file');
    }
    final dims = data.getUint16(5, Endian.little);
    final rows = data.getUint32(7, Endian.little);
    final words = data.getUint32(11, Endian.little);
    var at = 15;
    final vectors = Int8List.sublistView(data, at, at + rows * dims);
    at += rows * dims;
    final rowOf = Uint16List(words);
    for (var i = 0; i < words; i++) {
      rowOf[i] = data.getUint16(at + i * 2, Endian.little);
    }
    at += words * 2;
    // The words are plain a to z, one byte each.
    final list = String.fromCharCodes(Uint8List.sublistView(data, at)).split('\n');
    if (list.length != words) throw const FormatException('Word count does not match');
    return WordVectors._(dims, vectors, {for (var i = 0; i < words; i++) list[i]: rowOf[i]});
  }

  /// The word's vector, scaled to length 1, or null when the word isn't known.
  Float32List? operator [](String word) {
    final row = _rows[word];
    if (row == null) return null;
    final v = Float32List(dims);
    var norm = 0.0;
    for (var i = 0; i < dims; i++) {
      final x = _vectors[row * dims + i].toDouble();
      v[i] = x;
      norm += x * x;
    }
    if (norm == 0) return null;
    final scale = 1 / sqrt(norm);
    for (var i = 0; i < dims; i++) {
      v[i] *= scale;
    }
    return v;
  }
}

/// A task the user filed by hand, which the categoriser learns from.
typedef CategoryExample = ({String text, String category});

/// Picks a category for a task from the user's list, on the device.
///
/// Each word of the task is matched with the closest word of a category's name and keywords, by
/// word vectors, and the category whose words match best wins. Tasks the user filed by hand count as
/// examples: a new task much like one of them goes where it went. When nothing matches well enough
/// the task gets no category, rather than a wrong one.
class Categoriser {
  /// How well a task has to match a category to be filed under it, from 0 to 1.
  static const threshold = 0.45;

  /// How strongly a word's vote goes to the category it matches best.
  static const sharpness = 10.0;

  /// The most examples compared, newest first, so a long history doesn't slow writing a task.
  static const maxExamples = 300;

  final WordVectors vectors;

  Categoriser(this.vectors);

  static Future<Categoriser>? _bundled;

  /// The categoriser with the bundled vectors, read once on first use.
  static Future<Categoriser> bundled() => _bundled ??= rootBundle
      .load(wordVectorsAsset)
      .then((data) => Categoriser(WordVectors.parse(data)));

  /// The id of the category [text] fits best, or null when none fits well enough.
  String? categorise(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) {
    final task = _words(text);
    if (task.isEmpty || categories.isEmpty) return null;
    final ids = {for (final c in categories) c.id};
    final best = {for (final c in categories) c.id: _best(task, _words('${c.name} ${c.keywords}'))};

    // How alike the task is to the ones filed by hand, best per category.
    final byExample = <String, double>{};
    for (final e in examples.take(maxExamples)) {
      if (!ids.contains(e.category)) continue;
      final example = _words(e.text);
      if (example.isEmpty) continue;
      // Both ways, so a short example doesn't match every long task that contains it.
      final s = min(_mean(_best(task, example)), _mean(_best(example, task)));
      if (s > (byExample[e.category] ?? 0)) byExample[e.category] = s;
    }

    // A word that matches every category alike says little; one that matches one category much
    // better than the rest says a lot. So each word shares its vote among the categories by how
    // well it matches them (a softmax), the votes are added up, and the absolute fit of the winner
    // still has to reach the threshold.
    final rank = {for (final id in best.keys) id: 0.0};
    for (var w = 0; w < task.length; w++) {
      var total = 0.0;
      final votes = <String, double>{};
      for (final MapEntry(key: id, value: b) in best.entries) {
        if (b[w] case final s?) total += votes[id] = exp(sharpness * s);
      }
      for (final MapEntry(key: id, value: v) in votes.entries) {
        rank[id] = rank[id]! + v / total;
      }
    }
    final (id, _) = _top(rank);
    final fit = id == null ? 0.0 : _mean(best[id]!);

    // A task that matches one filed by hand better than any category's words goes where that one
    // went.
    final (exampleId, exampleFit) = _top(byExample);
    if (exampleId != null && exampleFit > fit) {
      return exampleFit >= threshold ? exampleId : null;
    }
    return fit >= threshold ? id : null;
  }

  /// How well [text] fits each category by its name and keywords, from 0 to 1.
  Map<String, double> scores(String text, List<TaskCategory> categories) {
    final task = _words(text);
    return {for (final c in categories) c.id: _mean(_best(task, _words('${c.name} ${c.keywords}')))};
  }

  (String?, double) _top(Map<String, double> scores) {
    String? id;
    var best = double.negativeInfinity;
    for (final MapEntry(:key, :value) in scores.entries) {
      if (value > best) (id, best) = (key, value);
    }
    return (id, best);
  }

  double _mean(List<double?> values) {
    var sum = 0.0;
    var n = 0;
    for (final v in values) {
      if (v == null) continue;
      sum += v;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  /// For each word of [a], how close it comes to its closest word in [b], from 0 to 1. A word with
  /// no vector matches only itself, and is null when it matches nothing, so a name or typo the
  /// vectors don't know doesn't count against any category.
  List<double?> _best(List<_Word> a, List<_Word> b) => [
        for (final x in a)
          switch ([for (final y in b) x.text == y.text ? 1.0 : _cosine(x.vector, y.vector)]
              .fold(0.0, max)) {
            0.0 when x.vector == null => null,
            final s => s,
          }
      ];

  double _cosine(Float32List? a, Float32List? b) {
    if (a == null || b == null) return 0;
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  final _cache = <String, _Word>{};

  List<_Word> _words(String text) => [
        for (final m in _wordPattern.allMatches(text.toLowerCase()))
          if (m[0]!.length > 1 && !_stopWords.contains(m[0]))
            _cache[m[0]!] ??= _Word(m[0]!, vectors[m[0]!]),
      ];
}

class _Word {
  final String text;
  final Float32List? vector;

  _Word(this.text, this.vector);
}

final _wordPattern = RegExp(r'[a-z]+');

/// Words that say little about what a task is about.
const _stopWords = {
  'a', 'about', 'after', 'all', 'an', 'and', 'any', 'are', 'as', 'at', 'be', 'before', 'but', 'by',
  'can', 'do', 'for', 'from', 'get', 'go', 'has', 'have', 'if', 'in', 'into', 'is', 'it', 'its',
  'me', 'more', 'my', 'new', 'next', 'not', 'of', 'off', 'on', 'or', 'our', 'out', 'over', 'some',
  'that', 'the', 'their', 'them', 'then', 'this', 'to', 'up', 'us', 'we', 'what', 'when', 'with',
  'you', 'your',
};

/// Categories offered in Settings when the list is empty, as a start to edit.
const suggestedCategories = [
  (name: 'Work', keywords: 'job office meeting project email client colleague report deadline'),
  (name: 'Health', keywords: 'doctor dentist exercise gym run sport medicine sleep'),
  (name: 'Home', keywords: 'house cleaning laundry kitchen repair garden cooking'),
  (name: 'Errands', keywords: 'shopping buy groceries store order post office'),
  (name: 'Money', keywords: 'bank bill pay tax budget invoice insurance rent'),
  (name: 'Learning', keywords: 'study read book course practice language tutorial'),
  (name: 'People', keywords: 'family friends call visit birthday partner kids mom dad'),
];
