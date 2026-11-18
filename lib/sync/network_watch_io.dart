/// Calls [onChange] when the device's network comes back. Only the web app watches;
/// elsewhere the relay check finds sockets that died with the old network.
void Function() watchNetwork(void Function() onChange) => () {};
