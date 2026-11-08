/// Settings for finding the group's other devices, kept out of the sync logic so they can change
/// without touching it.
class SyncConfig {
  /// Public relays that only carry sealed, ephemeral signalling (see `Signalling`). Any of them is
  /// enough; more of them only make it likelier that two devices share one that is up.
  static const defaultRelays = ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'];

  final List<Uri> relays;

  /// STUN or TURN servers for direct connections. None by default: devices then connect only on the
  /// same network, and no server outside the group learns their addresses.
  final List<Uri> iceServers;

  const SyncConfig({required this.relays, this.iceServers = const []});

  /// The defaults, or the comma-separated lists a build sets with
  /// `--dart-define=SYNC_RELAYS=wss://a,wss://b` and `--dart-define=SYNC_ICE_SERVERS=stun:host:3478`.
  factory SyncConfig.fromEnvironment() {
    const relays = String.fromEnvironment('SYNC_RELAYS');
    const iceServers = String.fromEnvironment('SYNC_ICE_SERVERS');
    return SyncConfig(
        relays: relays.isEmpty ? [for (final r in defaultRelays) Uri.parse(r)] : _uris(relays),
        iceServers: _uris(iceServers));
  }

  static List<Uri> _uris(String list) => [
        for (final u in list.split(',').map((u) => u.trim()))
          if (u.isNotEmpty) Uri.parse(u)
      ];
}
