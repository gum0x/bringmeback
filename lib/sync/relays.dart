import 'dart:convert';

/// The Nostr relays this device uses to find the group's other devices: the published relays it
/// keeps on, then the ones added on this device. Saved on the device, not synced.
class RelayList {
  /// The relays the app is built with (`SyncConfig.relays`), in their order.
  final List<String> published;

  /// Published relays turned off on this device.
  final Set<String> off;

  /// Relays added on this device, in the order they were added.
  final List<String> custom;

  const RelayList({required this.published, this.off = const {}, this.custom = const []});

  /// The relays to connect to, without repeats.
  List<String> get active => {
        for (final r in published)
          if (!off.contains(r)) r,
        ...custom,
      }.toList();

  bool isOn(String relay) => !off.contains(relay);

  /// Whether this is the list the app starts with: every published relay on and none added.
  bool get isDefault => off.isEmpty && custom.isEmpty;

  RelayList turn(String relay, {required bool on}) => RelayList(
      published: published,
      off: on ? ({...off}..remove(relay)) : {...off, relay},
      custom: custom);

  /// Adds `relay` (already normalised), or turns it back on if it is published.
  RelayList add(String relay) {
    if (published.contains(relay)) return turn(relay, on: true);
    if (custom.contains(relay)) return this;
    return RelayList(published: published, off: off, custom: [...custom, relay]);
  }

  RelayList remove(String relay) => RelayList(
      published: published, off: off, custom: [...custom]..remove(relay));

  /// Exactly `relays` on: the published ones among them stay on, the rest are added.
  RelayList only(List<String> relays) => RelayList(
      published: published,
      off: {...published.where((r) => !relays.contains(r))},
      custom: [
        ...{...custom.where(relays.contains), ...relays.where((r) => !published.contains(r))}
      ]);

  RelayList reset() => RelayList(published: published);

  /// The saved form. Only what this device changed is kept, so relays published later show up on
  /// their own.
  String encode() => jsonEncode({'off': off.toList(), 'custom': custom});

  /// The list saved with [encode], over the current `published` relays. Anything unreadable gives
  /// the default list.
  factory RelayList.decode(String? saved, List<String> published) {
    if (saved == null) return RelayList(published: published);
    try {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      return RelayList(
          published: published,
          off: {...(json['off'] as List? ?? const []).whereType<String>()},
          custom: [
            for (final r in (json['custom'] as List? ?? const []).whereType<String>())
              if (normaliseRelay(r) case final ok?) ok
          ]);
    } on Object {
      return RelayList(published: published);
    }
  }
}

/// `input` as a relay address (`wss://host[:port][/path]`), or null when it isn't one. A bare host
/// gets `wss://`. `ws://` is kept for relays on a local network.
String? normaliseRelay(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'wss://$text';
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'wss' && uri.scheme != 'ws') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  if (!RegExp(r'^[A-Za-z0-9.\-\[\]:]+$').hasMatch(uri.host)) return null;
  final path = uri.path == '/' ? '' : uri.path;
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path)
      .toString();
}

/// The relays a link asks for: `relays=wss://a,wss://b` or one `relay=` per relay, in the query or
/// in a fragment like `#join=…&relays=…`. Hosts without a scheme get `wss://`. Empty when the link
/// names none, and anything that isn't a relay address is left out.
List<String> relaysFromLink(Uri link) {
  final params = <String, List<String>>{};
  void read(String query) {
    if (query.isEmpty) return;
    // Not Uri.splitQueryString: it keeps only the last of repeated keys.
    for (final part in query.split('&')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      try {
        final key = Uri.decodeQueryComponent(part.substring(0, eq));
        final value = Uri.decodeQueryComponent(part.substring(eq + 1));
        params.putIfAbsent(key, () => []).add(value);
      } on ArgumentError {
        // Bad percent-encoding: this part names no relays.
      }
    }
  }

  read(link.query);
  final fragment = link.fragment;
  // `#/path?relays=…` (a router path) or `#relays=…`.
  read(fragment.contains('?') ? fragment.substring(fragment.indexOf('?') + 1) : fragment);
  return {
    for (final value in [...?params['relays'], ...?params['relay']])
      for (final r in value.split(','))
        if (normaliseRelay(r) case final ok?) ok
  }.toList();
}

/// A relay address without `wss://`, for showing.
String relayLabel(String relay) => relay.startsWith('wss://') ? relay.substring(6) : relay;
