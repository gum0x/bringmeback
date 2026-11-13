/// A link that carries a pairing code, so another device can join by opening it, scanning it as a QR
/// code, or sharing it to the app.
///
/// The code goes in the URL fragment, `https://host/app/#join=bmb1-…`, because browsers never send
/// the fragment to the server: the code is the group secret, and it stays out of server and proxy
/// logs. The fragment is read like a query string, so more parameters can follow the code, as in
/// `#join=bmb1-…&relays=wss://a,wss://b`. A `?join=` query is read too, for hosts or apps that drop
/// the fragment.
class ShareLink {
  /// The pairing code, still to be checked with `PairingCode.parse`.
  final String code;

  /// The link's other parameters, from the fragment and the query.
  final Map<String, String> params;

  const ShareLink(this.code, [this.params = const {}]);

  static const joinParam = 'join';

  /// Where links point when the app has no web address of its own (phones and desktop), set by a
  /// build with `--dart-define=SHARE_LINK_BASE=https://example.com/bringmeback/`. It should be where
  /// this app's web version is served, so a link opens it on any device, and the domain the phone
  /// apps claim, so a link opens the app where it is installed.
  static const defaultBase =
      String.fromEnvironment('SHARE_LINK_BASE', defaultValue: 'https://gum0x.github.io/bringmeback/');

  static final _code = RegExp(r'bmb1-[A-Za-z0-9_-]+');

  /// The link that opens the app at `base` and joins the group of `code`.
  static Uri build(Uri base, String code, [Map<String, String> extra = const {}]) {
    final fragment = Uri(queryParameters: {joinParam: code, ...extra}).query;
    return base.replace(fragment: fragment);
  }

  /// The address of the web app that `current` points into, without its fragment or query, so a link
  /// built on it opens the same app.
  static Uri baseOf(Uri current) =>
      Uri(scheme: current.scheme, host: current.host, port: current.port, path: current.path);

  /// Finds a pairing code in text that was typed, pasted, scanned or shared: a bare code, a link, or a
  /// message with a link in it. Returns null when there is none.
  static ShareLink? parse(String text) {
    final trimmed = text.trim();
    for (final word in trimmed.split(RegExp(r'\s+'))) {
      final uri = Uri.tryParse(word);
      if (uri == null || !uri.hasScheme) continue;
      final params = {...uri.queryParameters, ..._fragmentParams(uri)};
      final code = params.remove(joinParam);
      if (code != null && _code.hasMatch(code)) return ShareLink(code.trim(), params);
    }
    final match = _code.firstMatch(trimmed);
    return match == null ? null : ShareLink(match[0]!);
  }

  static Map<String, String> _fragmentParams(Uri uri) {
    if (!uri.hasFragment || !uri.fragment.contains('=')) return const {};
    // A Flutter route such as `#/join?join=…` puts the parameters after a `?`.
    final fragment = uri.fragment;
    final query = fragment.contains('?') ? fragment.substring(fragment.indexOf('?') + 1) : fragment;
    try {
      return Uri.splitQueryString(query);
    } on FormatException {
      return const {};
    }
  }
}
