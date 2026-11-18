import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _lockName = 'bringmeback-active-tab';

/// Makes this tab the one where the app runs, with a Web Lock every tab of this site shares.
///
/// Tabs of one browser share localStorage, so they are one device to sync, with one identity, but
/// each would hold its own copy of the tasks. Their edits would overwrite each other's saved copy,
/// and an edit made in one tab could never reach the other devices: they would take it as already
/// received from this device. So the app runs in one tab only.
///
/// Returns false when another tab holds the app (it is left alone). With `steal`, takes the app
/// from that tab, which then gets `onLost`. Where the browser has no Web Locks (an old browser, or a
/// page that isn't https or localhost), returns true: there is nothing to coordinate with.
Future<bool> acquireTab({bool steal = false, void Function()? onLost}) async {
  final web.LockManager locks;
  try {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('locks')) return true;
    locks = web.window.navigator.locks;
  } on Object {
    return true;
  }
  final granted = Completer<bool>();
  // Held until the page closes: the callback's promise never resolves.
  final held = Completer<void>();
  JSPromise<JSAny?> onLock(web.Lock? lock) {
    if (!granted.isCompleted) granted.complete(lock != null);
    if (lock == null) return Future<JSAny?>.value().toJS;
    return held.future.then((_) => null).toJS;
  }

  final options = steal ? web.LockOptions(steal: true) : web.LockOptions(ifAvailable: true);
  locks.request(_lockName, options, onLock.toJS).toDart.then((_) {}, onError: (Object _) {
    // Another tab stole the lock: this one must stop.
    if (granted.isCompleted) onLost?.call();
    if (!granted.isCompleted) granted.complete(false);
  });
  return granted.future;
}
