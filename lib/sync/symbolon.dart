import 'package:flutter/foundation.dart';

import '../src/rust/frb_generated.dart';

/// Whether this build can sync yet. The web build gets Symbolon through its own wasm binding, which is
/// not wired in yet.
const bool syncSupported = !kIsWeb;

Future<void>? _loading;

/// Loads the Symbolon library once. Safe to call from anywhere that needs it.
Future<void> loadSymbolon() {
  if (!syncSupported) {
    throw UnsupportedError('Sync is not available in the browser yet.');
  }
  return _loading ??= RustLib.init();
}
