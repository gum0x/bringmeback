import 'dart:async';

import 'package:bringmeback/sync/sync_log.dart';

/// Keeps the sync log out of the test output.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SyncLog.instance.printing = false;
  await testMain();
}
