import 'dart:async';
import 'dart:convert';

import 'package:bringmeback/sync/signalling.dart';

/// A relay in memory that forwards every EVENT to the other connections' subscriptions, like a Nostr
/// relay does with ephemeral events. It doesn't apply filters: Signalling must drop what isn't its own.
class FakeRelay {
  final connections = <FakeConnection>[];
  final published = <String>[];
  bool reachable = true;

  /// While true, events are published but reach no one, as when a relay drops them.
  bool deaf = false;

  RelayConnection connect(Uri _) {
    final c = FakeConnection(this);
    connections.add(c);
    return c;
  }

  void deliver(FakeConnection from, String message) {
    final parsed = jsonDecode(message) as List;
    if (parsed[0] == 'REQ') {
      from.subscription = parsed[1] as String;
    } else if (parsed[0] == 'EVENT') {
      published.add(message);
      if (deaf) return;
      for (final c in connections) {
        if (c != from && c.subscription != null && !c.incoming.isClosed) {
          c.incoming.add(jsonEncode(['EVENT', c.subscription, parsed[1]]));
        }
      }
    }
  }
}

class FakeConnection implements RelayConnection {
  final FakeRelay relay;
  final incoming = StreamController<Object?>();
  String? subscription;

  FakeConnection(this.relay);

  @override
  Future<void> get ready =>
      relay.reachable ? Future.value() : Future.error(StateError('unreachable'));

  @override
  Stream<Object?> get messages => incoming.stream;

  @override
  void add(String message) => relay.deliver(this, message);

  @override
  Future<void> close() => incoming.close();
}
