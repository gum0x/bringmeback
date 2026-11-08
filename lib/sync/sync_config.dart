/// Settings for finding the group's other devices, kept out of the sync logic so they can change
/// without touching it.
class SyncConfig {
  /// Public relays that only carry sealed, ephemeral signalling (see `Signalling`). Any of them is
  /// enough; more of them only make it likelier that two devices share one that is up.
  static const defaultRelays = ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'];

  final List<Uri> relays;

  const SyncConfig({required this.relays});

  /// The default relays, or the comma-separated list in `--dart-define=SYNC_RELAYS=wss://a,wss://b`
  /// when a build sets one.
  factory SyncConfig.fromEnvironment() {
    const override = String.fromEnvironment('SYNC_RELAYS');
    final relays = override.isEmpty
        ? defaultRelays
        : override.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty);
    return SyncConfig(relays: [for (final r in relays) Uri.parse(r)]);
  }
}
