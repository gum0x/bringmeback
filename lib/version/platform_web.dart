import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const canReload = true;

void reloadApp() => web.window.location.reload();

/// `build-info.json` next to the app, written when the web app is built.
Uri? servedBuildInfo() => Uri.base.resolve('build-info.json');

Future<Object?> fetchJson(Uri url) async {
  final response = await web.window
      .fetch(url.toString().toJS, web.RequestInit(cache: 'no-store'))
      .toDart
      .timeout(const Duration(seconds: 15));
  if (!response.ok) throw StateError('HTTP ${response.status}');
  final text = (await response.text().toDart).toDart;
  if (text.length > 64 * 1024) throw const FormatException('Too big');
  return jsonDecode(text);
}
