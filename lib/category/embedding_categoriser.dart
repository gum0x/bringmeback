import 'dart:math' as math;

import 'package:llamadart/llamadart.dart';

import '../bloc/task_document.dart';
import 'categoriser.dart';
import 'default_categories.dart';

/// Picks a category for a task with a sentence embedding model, on the device.
///
/// An embedding model turns a text into a point in space where texts that mean alike sit close,
/// whatever their language. Each category is described by its name and keywords, sample tasks
/// and the tasks the user filed under it; a task goes to the category with the closest description.
/// It ranks rather than writes, so it is much smaller and quicker than a chat model.
class EmbeddingCategoriser {
  /// How much closer the best category has to be than the next one, in cosine, to be sure.
  static const margin = 0.02;

  final LlamaEngine _engine;

  /// Put before a task, as the model was trained to see queries.
  final String queryPrefix;

  /// Put before a category's description.
  final String documentPrefix;

  /// Whether a category's name and keywords count, besides its sample and hand-filed tasks.
  final bool describe;

  EmbeddingCategoriser._(this._engine, this.queryPrefix, this.documentPrefix, this.describe);

  static Future<EmbeddingCategoriser> load(ModelSource model,
      {String queryPrefix = '', String documentPrefix = '', bool describe = true}) async {
    final engine = await LlamaEngine.load(LlamaModel(model),
        params: const ModelParams(contextSize: 512));
    if (!engine.supportsEmbeddings) {
      await engine.dispose();
      throw LlamaUnsupportedException('This model can\'t embed text.');
    }
    return EmbeddingCategoriser._(engine, queryPrefix, documentPrefix, describe);
  }

  Future<String> get backendName => _engine.getBackendName();

  final _cache = <String, List<double>>{};

  Future<List<double>> _embed(String text) async =>
      _cache[text] ??= await _engine.embed(text);

  /// The id of the best category for [text], or null when two are about as close.
  Future<String?> categorise(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) async {
    final ranked = (await scores(text, categories, examples: examples)).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty) return null;
    if (ranked.length > 1 && ranked[0].value - ranked[1].value < margin) return null;
    return ranked.first.key;
  }

  /// How close [text] comes to each category, as cosine similarity: the best of its description,
  /// its sample tasks and the tasks filed under it.
  Future<Map<String, double>> scores(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) async {
    if (text.trim().isEmpty || categories.isEmpty) return {};
    final task = await _embed('$queryPrefix${text.trim()}');
    final result = <String, double>{};
    for (final c in categories) {
      final texts = [
        if (describe || !sampleTasks.containsKey(c.id))
          '$documentPrefix${c.name.trim()}: ${c.keywords.trim().split(RegExp(r'\s+')).join(', ')}',
        for (final sample in sampleTasks[c.id] ?? const <String>[]) '$queryPrefix$sample',
        for (final e in examples.take(30))
          if (e.category == c.id) '$queryPrefix${e.text.trim()}',
      ];
      var best = -1.0;
      for (final t in texts) {
        best = math.max(best, _cosine(task, await _embed(t)));
      }
      result[c.id] = best;
    }
    return result;
  }

  static double _cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na == 0 || nb == 0 ? 0 : dot / math.sqrt(na * nb);
  }

  Future<void> dispose() => _engine.dispose();
}
