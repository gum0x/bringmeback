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
/// The model reads the task and the list of categories, with their keywords and rules, and a few
/// tasks the user filed by hand. It doesn't write an answer freely: each category's name is scored
/// as the answer, token by token, so the answer can only be one of the user's categories, and how
/// likely each name is says how sure the model is.
class LfmCategoriser {
  /// How likely the best category has to be, from 0 to 1, for the task to be filed under it.
  static const threshold = 0.4;

  /// At most this many categories are offered.
  static const maxCategories = 40;

  /// At most this many hand-filed tasks are shown as examples, newest first.
  static const maxExamples = 12;

  final LlamaEngine _engine;

  LfmCategoriser._(this._engine);

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
    if (!engine.supportsNextTokenScoring) {
      await engine.dispose();
      throw LlamaUnsupportedException(
          'This device\'s model runtime can\'t score answers, which categorising needs.');
    }
    return LfmCategoriser._(engine);
  }

  /// The id of the category [text] belongs to, or null when the model isn't sure enough. Only the
  /// first [maxCategories] of [categories] are offered.
  Future<String?> categorise(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) async {
    final scores = await this.scores(text, categories, examples: examples);
    if (scores.isEmpty) return null;
    final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
    return best.value >= threshold ? best.key : null;
  }

  /// How likely each category is as the answer for [text], from 0 to 1, adding up to 1.
  Future<Map<String, double>> scores(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) async {
    final offered = categories.take(maxCategories).toList();
    if (text.trim().isEmpty || offered.isEmpty) return {};
    final prompt = (await _engine.chatTemplate([
      LlamaChatMessage.fromText(
          role: LlamaChatRole.system, text: instructions(offered, examples: examples)),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: text.trim()),
    ], enableThinking: false))
        .prompt;

    // Each name's probability is that of its tokens one after the other. Names that start alike
    // share the scoring of their common start, and each step reuses the prompt already read.
    final names = [
      for (final c in offered) await _engine.tokenize(c.name.trim(), addSpecial: false),
    ];
    final next = <String, Set<int>>{};
    for (final tokens in names) {
      for (var i = 0; i < tokens.length; i++) {
        (next[tokens.take(i).join(',')] ??= {}).add(tokens[i]);
      }
    }
    final logprob = <String, Map<int, double>>{};
    for (final MapEntry(key: prefix, value: candidates) in next.entries) {
      final said = prefix.isEmpty
          ? ''
          : await _engine.detokenize([for (final t in prefix.split(',')) int.parse(t)]);
      final scored = await _engine.scoreNextToken('$prompt$said', candidates: candidates.toList());
      logprob[prefix] = {for (final c in scored.candidates) c.token: c.logprob};
    }
    final total = [
      for (final tokens in names)
        tokens.isEmpty
            ? double.negativeInfinity
            : [
                for (var i = 0; i < tokens.length; i++)
                  logprob[tokens.take(i).join(',')]![tokens[i]]!
              ].reduce((a, b) => a + b),
    ];
    final probabilities = softmax(total);
    return {for (final (i, c) in offered.indexed) c.id: probabilities[i]};
  }

  Future<void> dispose() => _engine.dispose();

  /// The system prompt: the categories, with what goes in each, and examples.
  @visibleForTesting
  static String instructions(List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) {
    final nameOf = {for (final c in categories) c.id: c.name.trim()};
    final shown = [
      for (final e in examples)
        if (nameOf[e.category] case final name?) (e.text, name)
    ].take(maxExamples);
    return [
      'You sort the tasks of a personal to-do list into categories. The user sends one task. '
          'Reply with the name of the one category it belongs to, exactly as written below, '
          'and nothing else.',
      '',
      'Categories:',
      for (final c in categories)
        [
          '- ${c.name.trim()}',
          if (c.keywords.isNotEmpty) ' (for example: ${c.keywords.trim().split(RegExp(r'\s+')).join(', ')})',
          if (c.rulePhrases.isNotEmpty) '. Always for tasks that mention: ${c.rulePhrases.join(', ')}',
        ].join(),
      if (shown.isNotEmpty) ...[
        '',
        'Tasks the user sorted before:',
        for (final (text, name) in shown) '$text => $name',
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
