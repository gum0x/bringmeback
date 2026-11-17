import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../bloc/task_document.dart';
import 'categoriser.dart';
import 'default_categories.dart';

/// Liquid AI's LFM2.5-1.2B Instruct, quantised to 4 bits: a small language model made for phones
/// and browsers. On real tasks the 350M size got too many wrong (4 of 10 in Spanish, against 8 of
/// 10 for this one) to be worth a download. Downloaded once, on the user's say-so, and kept on the device. Licensed under Liquid
/// AI's LFM Open License v1.0.
final lfmModel = ModelSource.huggingFace(
  repoId: lfmModelRepo,
  filePath: lfmModelFile,
);

/// [lfmModel]'s repository on Hugging Face.
const lfmModelRepo = 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF';

/// The model's file in [lfmModelRepo].
const lfmModelFile =
    String.fromEnvironment('LFM_MODEL_FILE', defaultValue: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf');

/// About how big [lfmModel] is, for Settings to say before downloading.
const lfmModelMegabytes = 700;

/// Picks a category for a task with [lfmModel], on the device.
///
/// The model reads the list of categories, with their keywords and rules, then a few tasks already
/// sorted (the user's own, and one example for each default category), as earlier turns of the
/// chat, and then the task. It doesn't write an answer freely: the categories' names are scored as
/// its reply, so the answer can only be one of them, and the scores say how sure it is.
///
/// Reading the prompt is what takes time (around a second on a laptop's CPU), and this model can't
/// reuse a prompt it read before, so names are told apart by their first token in one pass. Only
/// when names start alike does it read again, with the shared start, to tell those apart.
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
      // Prompts are several hundred tokens: a category list, examples and one task.
      params: const ModelParams(contextSize: 4096),
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

  /// How likely the model's answer for [text] is each category, from 0 to 1. Categories whose names
  /// start like the most likely one's share a score until the names part.
  Future<Map<String, double>> scores(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) async {
    final offered = categories.take(maxCategories).toList();
    if (text.trim().isEmpty || offered.isEmpty) return {};
    final prompt =
        (await _engine.chatTemplate(chat(text, offered, examples: examples), enableThinking: false))
            .prompt;
    final names = [
      for (final c in offered) await _engine.tokenize(c.name.trim(), addSpecial: false),
    ];

    // Walks down the names token by token, following the most likely start. A name that ends
    // where others go on (say "Work" beside "Work planning") is scored by how unlikely it is that
    // the reply goes on with any of theirs.
    final scores = <String, double>{};
    var group = [
      for (var i = 0; i < offered.length; i++)
        if (names[i].isNotEmpty) i
    ];
    var weight = 1.0;
    for (var depth = 0; group.length > 1; depth++) {
      final ended = [
        for (final i in group)
          if (names[i].length == depth) i
      ];
      final byToken = <int, List<int>>{};
      for (final i in group) {
        if (names[i].length > depth) (byToken[names[i][depth]] ??= []).add(i);
      }
      final tokens = byToken.keys.toList();
      var probabilities = [1.0];
      if (tokens.length > 1 || ended.isNotEmpty) {
        final said =
            depth == 0 ? '' : await _engine.detokenize(names[group.first].sublist(0, depth));
        final scored = await _engine.scoreNextToken('$prompt$said', candidates: tokens);
        final logprobs = [for (final c in scored.candidates) c.logprob];
        probabilities = softmax(logprobs);
        if (ended.isNotEmpty) {
          final goesOn = logprobs.map(math.exp).fold(0.0, (a, b) => a + b).clamp(0.0, 1.0);
          for (final i in ended) {
            scores[offered[i].id] = weight * (1 - goesOn) / ended.length;
          }
          weight *= goesOn;
        }
      }
      var best = 0;
      for (var k = 1; k < tokens.length; k++) {
        if (probabilities[k] > probabilities[best]) best = k;
      }
      for (var k = 0; k < tokens.length; k++) {
        if (k == best) continue;
        final members = byToken[tokens[k]]!;
        for (final i in members) {
          scores[offered[i].id] = weight * probabilities[k] / members.length;
        }
      }
      weight *= probabilities[best];
      group = byToken[tokens[best]]!;
    }
    if (group.length == 1) scores[offered[group.single].id] = weight;
    return scores;
  }

  /// What the model sees and would say next for [text], to look into its picks.
  @visibleForTesting
  Future<String> explain(String text, List<TaskCategory> categories) async {
    final prompt =
        (await _engine.chatTemplate(chat(text, categories), enableThinking: false)).prompt;
    final names = [
      for (final c in categories) await _engine.tokenize(c.name.trim(), addSpecial: false),
    ];
    final scored = await _engine.scoreNextToken(prompt,
        candidates: {for (final n in names) n.first}.toList(), topK: 8);
    String show(Iterable<LlamaTokenLogprob> l) => l
        .map((t) => '${t.token}:${jsonEncode(t.text)} ${(t.probability * 100).toStringAsFixed(1)}%')
        .join(', ');
    return [
      'prompt ends: ${jsonEncode(prompt.substring(math.max(0, prompt.length - 120)))}',
      'name tokens: ${[
        for (final (i, c) in categories.indexed) '${c.name}=${names[i]}'
      ].join(' ')}',
      'top: ${show(scored.top)}',
      'candidates: ${show(scored.candidates)}',
    ].join('\n');
  }

  Future<void> dispose() => _engine.dispose();

  /// The chat the model reads: instructions, then sorted tasks as earlier turns, then [text].
  @visibleForTesting
  static List<LlamaChatMessage> chat(String text, List<TaskCategory> categories,
      {List<CategoryExample> examples = const []}) {
    final nameOf = {for (final c in categories) c.id: c.name.trim()};
    final user = [
      for (final e in examples)
        if (nameOf[e.category] case final name?) (e.text.trim(), name)
    ].take(maxExamples).toList().reversed;
    final starters = [
      for (final MapEntry(key: id, value: task) in sampleTasks.entries)
        if (nameOf[id] case final name?) (task, name)
    ];
    final sorted = [...starters, ...user];
    LlamaChatMessage say(LlamaChatRole role, String text) =>
        LlamaChatMessage.fromText(role: role, text: text);
    return [
      say(LlamaChatRole.system, instructions(categories)),
      for (final (task, name) in sorted) ...[
        say(LlamaChatRole.user, task),
        say(LlamaChatRole.assistant, name),
      ],
      say(LlamaChatRole.user, text.trim()),
    ];
  }



  /// The system prompt: the categories, with what goes in each.
  @visibleForTesting
  static String instructions(List<TaskCategory> categories) => [
        'You sort the tasks of a personal to-do list into categories. The user sends one task. '
            'Reply with the name of the one category it belongs to, exactly as written below, '
            'and nothing else.',
        '',
        'Categories:',
        for (final c in categories)
          [
            '- ${c.name.trim()}',
            if (c.keywords.trim().isNotEmpty)
              ' (${c.keywords.trim().split(RegExp(r'\s+')).join(', ')})',
            if (c.rulePhrases.isNotEmpty)
              '. Always for tasks that mention: ${c.rulePhrases.join(', ')}',
          ].join(),
      ].join('\n');

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
