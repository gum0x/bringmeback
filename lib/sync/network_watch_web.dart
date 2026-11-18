import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Calls [onChange] when the browser comes back online, as after a switch from one Wi-Fi network
/// to another or to mobile data. Returns a function that stops watching.
void Function() watchNetwork(void Function() onChange) {
  final listener = ((web.Event _) => onChange()).toJS;
  web.window.addEventListener('online', listener);
  return () => web.window.removeEventListener('online', listener);
}
