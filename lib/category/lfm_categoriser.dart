import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../bloc/task_document.dart';
import 'categoriser.dart';

/// Liquid AI's LFM2.5-350M, quantised to 4 bits: a small language model made for phones and
/// browsers. Downloaded once, on the user's say-so, and kept on the device. Licensed under Liquid
/// AI's LFM Open License v1.0.
final lfmModel = ModelSource.huggingFace(
  repoId: 'LiquidAI/LFM2.5-350M-GGUF',
  filePath: lfmModelFile,
);

/// The model's file in [lfmModel]'s repository.
const lfmModelFile = String.fromEnvironment('LFM_MODEL_FILE', defaultValue: 'LFM2.5-350M-Q4_K_M.gguf');

/// About how big [lfmModel] is, for Settings to say before downloading.
const lfmModelMegabytes = 230;

/// Picks a category for a task with [lfmModel], on the device.
///
/// The model reads the task and a lettered list of the categories, with their keywords and rules,
/// and a few tasks the user filed by hand. It doesn't write an answer: the probability of each
/// letter as the next token says how likely each category is, so one pass over the prompt
/// decides, and the answer can only be one of the user's categories.
class LfmCategoriser {
  /// How likely the best category has to be, from 0 to 1, for the task to be filed under it.
  static const threshold = 0.4;

  /// At most this many categories are offered, one per letter.
  static const maxCategories = 26;

  /// At most this many hand-filed tasks are shown as examples, newest first.
  static const maxExamples = 12;

  final LlamaEngine _engine;
  final List<int> _letters;

  LfmCategoriser._(this._engine, this._letters);

  /// The backend the model runs on, such as Metal, Vulkan, CPU or WebGPU.
  Future<String> get backendName => _engine.getBackendName();

  /// Loads [model], downloading it first when it isn't on the device yet.
  static Future<LfmCategoriser> load(
      {ModelSource? model, ModelDownloadProgressCallback? onProgress}) async {
    final engine = await LlamaEngine.load(
      LlamaModel(model ?? lfmModel),
      // Prompts are a few hundred tokens: a category list and one task.
      params: const ModelParams(contextSize: 2048),
      onProgress: onProgress,
    );
    try {
      if (!engine.supportsNextTokenScoring) {
        throw LlamaUnsupportedException(
            'This device\'s model runtime can\'t score answers, which categorising needs.');
      }
      final letters = [
        for (var i = 0; i < maxCategories; i++)
          (await engine.tokenize(String.fromCharCode(65 + i), addSpecial: false)).first,
      ];
      if (letters.toSet().length != letters.length) {
        throw StateError('Two answer letters share a token in this model.');
      }
      return LfmCategoriser._(engine, letters);
    } catch (_) {
      await engine.dispose();
      rethrow;
    }
  }

  /// The id of the category [text] belongs to, or null when the model isn't sure enough. Only the
  /// first [maxCategories] of [categories] are offered.
  Future<String?> categorise(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) async {
    final offered = categories.take(maxCategories).toList();
    if (text.trim().isEmpty || offered.isEmpty) return null;
    final prompt = (await _engine.chatTemplate([
      LlamaChatMessage.fromText(
          role: LlamaChatRole.system, text: instructions(offered, examples: examples)),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: text.trim()),
    ], enableThinking: false))
        .prompt;
    final scores = await _engine.scoreNextToken(prompt,
        candidates: _letters.sublist(0, offered.length));
    final probabilities = softmax([for (final c in scores.candidates) c.logprob]);
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    return probabilities[best] >= threshold ? offered[best].id : null;
  }

  Future<void> dispose() => _engine.dispose();

  /// The system prompt: the categories by letter, with what goes in each, and examples.
  @visibleForTesting
  static String instructions(List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) {
    String letter(int i) => String.fromCharCode(65 + i);
    final letterOf = {for (final (i, c) in categories.indexed) c.id: letter(i)};
    final shown = [
      for (final e in examples)
        if (letterOf[e.category] case final l?) (e.text, l)
    ].take(maxExamples);
    return [
      'You file the tasks of a personal to-do list under categories. The user sends one task. '
          'Reply with the letter of the one category it belongs to, and nothing else.',
      '',
      'Categories:',
      for (final (i, c) in categories.indexed)
        [
          '${letter(i)}) ${c.name}',
          if (c.keywords.isNotEmpty) ': ${c.keywords}',
          if (c.rulePhrases.isNotEmpty) '. Always for tasks that mention: ${c.rulePhrases.join(', ')}',
        ].join(),
      if (shown.isNotEmpty) ...[
        '',
        'Tasks the user filed before:',
        for (final (text, l) in shown) '$text => $l',
      ],
    ].join('\n');
  }

  /// Turns log-probabilities into probabilities that add up to 1.
  @visibleForTesting
  static List<double> softmax(List<double> logprobs) {
    final top = logprobs.reduce(math.max);
    final exps = [for (final l in logprobs) math.exp(l - top)];
    final sum = exps.reduce((a, b) => a + b);
    return [for (final e in exps) e / sum];
  }

  /// Removes the downloaded model from this device. Browsers keep it in their own cache, which the
  /// app can't clear.
  static Future<void> deleteDownload() async {
    if (kIsWeb) return;
    final manager = DefaultModelDownloadManager();
    try {
      final entry = await manager.ensureModel(lfmModel,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly));
      await manager.remove(entry.cacheKey);
    } on Object catch (e) {
      // Nothing downloaded, or already gone.
      debugPrint('No LFM download to delete: $e');
    }
  }
}
