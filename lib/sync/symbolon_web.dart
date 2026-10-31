import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'symbolon.dart';

/// Where the build puts Symbolon's JavaScript binding (see tool/build_symbolon_web.sh), relative to
/// the app's own script.
const _modulePath = './symbolon/symbolon_wasm.js';

Future<Symbolon> load() async {
  final module = await importModule(_modulePath.toJS).toDart;
  // The default export loads the .wasm file next to the module.
  await module.callMethod<JSPromise<JSAny?>>('default'.toJS).toDart;
  return _Web(module);
}

JSUint8Array _js(List<int> bytes) =>
    (bytes is Uint8List ? bytes : Uint8List.fromList(bytes)).toJS;

Uint8List _dart(JSAny? value) => (value as JSUint8Array).toDart;

class _Web implements Symbolon {
  final JSObject module;

  _Web(this.module);

  JSFunction _class(String name) => module[name] as JSFunction;

  @override
  SymbolonGroupKeys groupKeys(List<int> context, List<int> secret) =>
      _GroupKeys(_class('GroupKeys').callAsConstructor<JSObject>(_js(context), _js(secret)));

  @override
  SymbolonDeviceKey generateDeviceKey() =>
      _DeviceKey(_class('DeviceKey').callMethod<JSObject>('generate'.toJS));

  @override
  SymbolonDeviceKey deviceKeyFromPrivate(List<int> privateKey) =>
      _DeviceKey(_class('DeviceKey').callMethod<JSObject>('fromPrivate'.toJS, _js(privateKey)));

  @override
  bool initiates(List<int> localPublic, List<int> remotePublic) => module
      .callMethod<JSBoolean>('initiates'.toJS, _js(localPublic), _js(remotePublic))
      .toDart;

  @override
  SymbolonHandshake initiator(SymbolonDeviceKey device, List<int> remotePublic,
          SymbolonGroupKeys group, List<int> prologue) =>
      _Handshake(_class('Handshake').callMethod<JSObject>('initiator'.toJS,
          (device as _DeviceKey).inner, _js(remotePublic), (group as _GroupKeys).inner, _js(prologue)));

  @override
  SymbolonHandshake responder(
          SymbolonDeviceKey device, SymbolonGroupKeys group, List<int> prologue) =>
      _Handshake(_class('Handshake').callMethod<JSObject>('responder'.toJS,
          (device as _DeviceKey).inner, (group as _GroupKeys).inner, _js(prologue)));

  @override
  int get maxPlaintext => _class('Channel').callMethod<JSNumber>('maxPlaintext'.toJS).toDartInt;
}

class _GroupKeys implements SymbolonGroupKeys {
  final JSObject inner;

  _GroupKeys(this.inner);

  @override
  Uint8List fingerprint() => _dart(inner.callMethod('fingerprint'.toJS));

  @override
  Uint8List topic(List<int> label) => _dart(inner.callMethod('topic'.toJS, _js(label)));

  @override
  Uint8List seal(List<int> plaintext, List<int> aad) =>
      _dart(inner.callMethod('seal'.toJS, _js(plaintext), _js(aad)));

  @override
  Uint8List open(List<int> sealed, List<int> aad) =>
      _dart(inner.callMethod('open'.toJS, _js(sealed), _js(aad)));
}

class _DeviceKey implements SymbolonDeviceKey {
  final JSObject inner;
  @override
  final Uint8List publicKey;

  _DeviceKey(this.inner) : publicKey = _dart(inner['publicKey']);

  @override
  Uint8List privateKey() => _dart(inner.callMethod('privateKey'.toJS));
}

class _Handshake implements SymbolonHandshake {
  final JSObject inner;

  _Handshake(this.inner);

  @override
  Uint8List writeMessage(List<int> payload) =>
      _dart(inner.callMethod('writeMessage'.toJS, _js(payload)));

  @override
  Uint8List readMessage(List<int> message) =>
      _dart(inner.callMethod('readMessage'.toJS, _js(message)));

  @override
  bool get isFinished => (inner['isFinished'] as JSBoolean).toDart;

  @override
  Uint8List? get remoteStatic {
    final key = inner['remoteStatic'];
    return key == null ? null : _dart(key);
  }

  @override
  SymbolonChannel intoChannel() => _Channel(inner.callMethod<JSObject>('intoChannel'.toJS));
}

class _Channel implements SymbolonChannel {
  final JSObject inner;

  _Channel(this.inner);

  @override
  Uint8List encrypt(List<int> plaintext) =>
      _dart(inner.callMethod('encrypt'.toJS, _js(plaintext)));

  @override
  Uint8List decrypt(List<int> ciphertext) =>
      _dart(inner.callMethod('decrypt'.toJS, _js(ciphertext)));

  @override
  bool get isOpen => (inner['isOpen'] as JSBoolean).toDart;
}
