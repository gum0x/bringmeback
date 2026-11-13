import 'dart:convert';
import 'dart:io';

/// The web app reloads itself to update; other builds can't.
const canReload = false;

void reloadApp() {}

/// Where the server says which build it serves. Only the web app has one.
Uri? servedBuildInfo() => null;

/// Fetches a small JSON document, or throws.
Future<Object?> fetchJson(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'bringmeback');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: url);
    final body = await response.transform(utf8.decoder).take(64 * 1024).join();
    return jsonDecode(body);
  } finally {
    client.close(force: true);
  }
}
