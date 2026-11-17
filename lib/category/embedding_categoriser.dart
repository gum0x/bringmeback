import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../bloc/task_document.dart';
import 'categoriser.dart';
import 'default_categories.dart';

/// The multilingual model Settings offers to download: sentence-transformers'
/// paraphrase-multilingual-MiniLM-L12-v2 (Apache 2.0), converted to GGUF and quantised to 8 bits.
/// It knows 50+ languages, Spanish, Portuguese, Chinese, Hindi and Arabic among them. Of the small
/// models compared in .github/workflows/category-bench.yaml it filed the most tasks right, and it
/// takes about 10 ms a task.
final multilingualModel = ModelSource.huggingFace(
  repoId: 'mykor/paraphrase-multilingual-MiniLM-L12-v2.gguf',
  filePath: multilingualModelFile,
);

const multilingualModelFile = 'paraphrase-multilingual-MiniLM-L12-118M-v2-Q8_0.gguf';

/// [multilingualModelFile]'s SHA-256, checked after downloading, since the conversion is a third
/// party's. Checked by the category-bench workflow too.
const multilingualModelSha256 =
    '1bcc1fd3f65d1269f8e733218d77ac5a479796fade0e87257606c2c4f2854662';

/// About how big [multilingualModel] is, for Settings to say before downloading.
const multilingualModelMegabytes = 132;

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

  /// Loads [model], [multilingualModel] by default, downloading it first when it isn't on the device
  /// yet.
  static Future<EmbeddingCategoriser> load(ModelSource? model,
      {String queryPrefix = '',
      String documentPrefix = '',
      bool describe = true,
      ModelDownloadProgressCallback? onProgress}) async {
    final engine = await LlamaEngine.load(LlamaModel(model ?? multilingualModel),
        params: const ModelParams(contextSize: 512),
        // Browsers load the file themselves and can't check it.
        download: model == null && !kIsWeb && multilingualModelSha256.isNotEmpty
            ? ModelLoadOptions(sha256: multilingualModelSha256)
            : ModelLoadOptions.defaults,
        onProgress: onProgress);
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

  /// Removes the downloaded [multilingualModel] from this device. Browsers keep it in their own
  /// cache, which the app can't clear.
  static Future<void> deleteDownload() async {
    if (kIsWeb) return;
    final manager = DefaultModelDownloadManager();
    try {
      final entry = await manager.ensureModel(multilingualModel,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly));
      await manager.remove(entry.cacheKey);
    } on Object catch (e) {
      // Nothing downloaded, or already gone.
      debugPrint('No model download to delete: $e');
    }
  }
}
