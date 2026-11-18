/// Keeps the app active in one browser tab at a time. See `tab_lock_web.dart`.
library;

export 'tab_lock_io.dart' if (dart.library.js_interop) 'tab_lock_web.dart';
