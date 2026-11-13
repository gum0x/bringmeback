import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android's MainActivity answers on this channel with the link or shared text that opened the app,
/// sends later ones, and opens the share sheet. Other platforms don't answer, and then no link arrives.
const _channel = MethodChannel('bringmeback/links');

final StreamController<String> _later = StreamController<String>.broadcast(onListen: () {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'link' && call.arguments is String) _later.add(call.arguments as String);
  });
});

Future<String?> initialText() async {
  try {
    return await _channel.invokeMethod<String>('initial');
  } on MissingPluginException {
    return null;
  }
}

Stream<String> laterTexts() => _later.stream;

Uri? ownBase() => null;

bool canShare() => Platform.isAndroid;

Future<bool> share(String text) async {
  try {
    return await _channel.invokeMethod<bool>('share', text) ?? false;
  } on MissingPluginException {
    return false;
  }
}
