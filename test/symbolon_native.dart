import 'dart:io';

import 'package:symbolon_flutter/symbolon_flutter.dart';

/// Loads the native library that `tool/build_symbolon.sh native` builds, since unit tests run outside
/// an app build.
Future<Symbolon> loadSymbolonForTests() {
  final name = Platform.isWindows
      ? 'symbolon_flutter.dll'
      : Platform.isMacOS
          ? 'libsymbolon_flutter.dylib'
          : 'libsymbolon_flutter.so';
  return loadSymbolon(nativeLibrary: 'build/symbolon-native/release/$name');
}
