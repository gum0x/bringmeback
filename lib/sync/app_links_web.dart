import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'share_link.dart';

Future<String?> initialText() async => _takeFromAddress();

/// A link pasted into the address bar of the open app changes only the fragment, which doesn't
/// reload the page.
Stream<String> laterTexts() => web.EventStreamProviders.hashChangeEvent
    .forTarget(web.window)
    .map((_) => _takeFromAddress())
    .where((text) => text != null)
    .cast<String>();

String? _takeFromAddress() {
  final opened = Uri.base;
  if (ShareLink.parse(opened.toString()) == null) return null;
  // The code is the group secret: keep it out of the address bar, the history and bookmarks.
  web.window.history.replaceState(null, '', ShareLink.baseOf(opened).toString());
  return opened.toString();
}

Uri? ownBase() => ShareLink.baseOf(Uri.base);

bool canShare() => web.window.navigator.has('share');

Future<bool> share(String text) async {
  try {
    await web.window.navigator.share(web.ShareData(text: text)).toDart;
    return true;
  } on Object {
    // Cancelled, or not allowed here.
    return false;
  }
}
