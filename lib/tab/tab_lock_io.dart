/// Outside a browser there are no tabs: the app is always the active one.
Future<bool> acquireTab({bool steal = false, void Function()? onLost}) async => true;
