import 'dart:async';

import 'app_links_io.dart' if (dart.library.js_interop) 'app_links_web.dart' as platform;
import 'share_link.dart';

/// Share links in and out of the app. In: the address the web app was opened at, a link the phone
/// opened with the app, or text shared to the app from another app's share menu. Out: the system share
/// sheet, where there is one.
class AppLinks {
  AppLinks._();

  /// The link the app was started with, if it carries a pairing code. On the web, the code is then
  /// taken out of the address bar and the browser history.
  static Future<ShareLink?> initial() async {
    final text = await platform.initialText();
    return text == null ? null : ShareLink.parse(text);
  }

  /// Links that arrive while the app runs, such as a share to the app that is already open.
  static Stream<ShareLink> get later =>
      platform.laterTexts().map(ShareLink.parse).where((l) => l != null).cast<ShareLink>();

  /// The web address of this app, to build share links on, or null where the app has none.
  static Uri? get ownBase => platform.ownBase();

  /// Whether [share] can open the system share sheet here.
  static bool get canShare => platform.canShare();

  /// Opens the system share sheet with `text`. Returns false when it couldn't.
  static Future<bool> share(String text) => platform.share(text);
}
