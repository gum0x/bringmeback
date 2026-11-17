import 'dart:async';

import 'package:bringmeback/sync/signalling.dart';

/// Runs before every test file: no test may send anything to a real Nostr relay.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  realRelaysBlocked = true;
  await testMain();
}
