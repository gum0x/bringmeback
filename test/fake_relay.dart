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

  /// When set, every event is refused with this reason, as a relay that rejects them does.
  String? refuse;

  /// The relay's clock, for its `since` filter. Null: it doesn't filter on time.
  int Function()? now;

  RelayConnection connect(Uri _) {
    final c = FakeConnection(this);
    connections.add(c);
    return c;
  }

  void deliver(FakeConnection from, String message) {
    final parsed = jsonDecode(message) as List;
    if (from.dead) return;
    if (parsed[0] == 'REQ') {
      from.subscription = parsed[1] as String;
      from.since = (parsed[2] as Map)['since'] as int?;
      // A relay ends the stored events of a subscription with EOSE, at once for ephemeral ones.
      if (!from.incoming.isClosed) from.incoming.add(jsonEncode(['EOSE', from.subscription]));
    } else if (parsed[0] == 'EVENT') {
      final event = parsed[1] as Map;
      if (refuse case final reason?) {
        from.incoming.add(jsonEncode(['OK', event['id'], false, reason]));
        return;
      }
      published.add(message);
      if (deaf) return;
      for (final c in connections) {
        // A relay passes an event on to every matching subscription, the sender's too.
        if (!c.dead &&
            c.subscription != null &&
            (c.since == null || (event['created_at'] as int) >= c.since!) &&
            !c.incoming.isClosed) {
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
  int? since;

  /// A connection that died without closing, as after the computer slept: nothing goes through in
  /// either direction, and no close ever arrives.
  bool dead = false;

  FakeConnection(this.relay);

  bool _opened = false;

  @override
  Future<void> get ready {
    if (!relay.reachable) return Future.error(StateError('unreachable'));
    _opened = true;
    return Future.value();
  }

  @override
  Stream<Object?> get messages => incoming.stream;

  @override
  void add(String message) => relay.deliver(this, message);

  /// Like web_socket_channel's, the close of a connection that never opened (its relay was
  /// unreachable) never completes: nothing ever listened to its socket.
  @override
  Future<void> close() => _opened ? incoming.close() : Completer<void>().future;
}
