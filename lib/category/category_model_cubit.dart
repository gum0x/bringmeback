import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bloc/task_document.dart';
import 'categoriser.dart';
import 'embedding_categoriser.dart';

enum CategoryModelStatus {
  /// Not turned on, on this device.
  off,

  /// Downloading the model; [CategoryModelState.fraction] says how far.
  downloading,

  /// Loading the downloaded model.
  loading,

  /// Categorising tasks.
  ready,

  /// Turned on, but the model couldn't be downloaded or loaded; [CategoryModelState.error] says why.
  failed,
}

class CategoryModelState {
  final CategoryModelStatus status;

  /// How much of the model has downloaded, from 0 to 1, or null while the size isn't known.
  final double? fraction;
  final int receivedBytes;

  /// What went wrong, when [status] is [CategoryModelStatus.failed].
  final String? error;

  /// What the model runs on once ready, such as Metal, Vulkan, CPU or WebGPU.
  final String? backend;

  const CategoryModelState(this.status,
      {this.fraction, this.receivedBytes = 0, this.error, this.backend});

  bool get on => status != CategoryModelStatus.off;
}

/// Whether this device categorises tasks with the multilingual model, and the model when it does.
///
/// The choice is per device and not synced: the model is a download each device makes for itself.
/// Turned on, the model loads at start, from the download kept on the device.
class CategoryModelCubit extends Cubit<CategoryModelState> {
  static const _prefKey = 'multilingualCategories';

  final Future<EmbeddingCategoriser> Function({ModelDownloadProgressCallback? onProgress}) _load;
  EmbeddingCategoriser? _categoriser;
  AppLifecycleListener? _exit;

  CategoryModelCubit({Future<EmbeddingCategoriser> Function({ModelDownloadProgressCallback? onProgress})? load})
      : _load = load ?? (({onProgress}) => EmbeddingCategoriser.load(null, onProgress: onProgress)),
        super(const CategoryModelState(CategoryModelStatus.off));

  /// Turns the model on when it was on last time.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) ?? false) await _start();
  }

  /// Turns the multilingual model on, downloading it if needed.
  Future<void> turnOn() async {
    if (state.status == CategoryModelStatus.downloading ||
        state.status == CategoryModelStatus.loading ||
        state.status == CategoryModelStatus.ready) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    await _start();
  }

  /// Turns the multilingual model off and deletes the download from this device.
  Future<void> turnOff() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    final categoriser = _categoriser;
    _categoriser = null;
    emit(const CategoryModelState(CategoryModelStatus.off));
    await categoriser?.dispose();
    await EmbeddingCategoriser.deleteDownload();
  }

  Future<void> _start() async {
    emit(const CategoryModelState(CategoryModelStatus.downloading));
    try {
      final categoriser = await _load(onProgress: (p) {
        if (isClosed || state.status == CategoryModelStatus.off) return;
        emit(p.fraction == 1
            ? const CategoryModelState(CategoryModelStatus.loading)
            : CategoryModelState(CategoryModelStatus.downloading, fraction: p.fraction, receivedBytes: p.receivedBytes));
      });
      if (isClosed || state.status == CategoryModelStatus.off) {
        await categoriser.dispose();
        return;
      }
      _categoriser = categoriser;
      // Desktop apps can quit without disposing widgets; free the model first.
      _exit ??= AppLifecycleListener(onExitRequested: () async {
        await _categoriser?.dispose();
        _categoriser = null;
        return AppExitResponse.exit;
      });
      emit(CategoryModelState(CategoryModelStatus.ready, backend: await _backendName(categoriser)));
    } on Object catch (e) {
      debugPrint('Multilingual model unavailable: $e');
      if (!isClosed && state.status != CategoryModelStatus.off) {
        emit(CategoryModelState(CategoryModelStatus.failed, error: describeError(e)));
      }
    }
  }

  static Future<String?> _backendName(EmbeddingCategoriser categoriser) async {
    try {
      return await categoriser.backendName;
    } on Object {
      return null;
    }
  }

  /// The category the multilingual model picks for [text], or null when it isn't sure. Throws
  /// [StateError] when
  /// the model isn't ready, so the caller falls back to the word vectors.
  Future<String?> categorise(String text, List<TaskCategory> categories,
      List<CategoryExample> examples) {
    final categoriser = _categoriser;
    if (categoriser == null) throw StateError('The multilingual model is not ready');
    return categoriser.categorise(text, categories, examples: examples);
  }

  /// A short reason the user can act on.
  @visibleForTesting
  static String describeError(Object e) {
    final text = '$e';
    if (text.contains('COOP') || text.contains('COEP') || text.contains('cross-origin')) {
      return 'This web page isn\'t served with the cross-origin isolation the model needs. '
          'The installed app, or the Docker build, can run it.';
    }
    if (text.contains('WebGPU') || text.contains('bridge')) {
      return 'This browser can\'t run the model.';
    }
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('HttpException') ||
        text.contains('Failed host lookup')) {
      return 'The download failed. Check the connection and try again.';
    }
    return 'The model couldn\'t load: ${text.length > 160 ? '${text.substring(0, 160)}…' : text}';
  }

  @override
  Future<void> close() async {
    _exit?.dispose();
    await _categoriser?.dispose();
    _categoriser = null;
    return super.close();
  }
}
