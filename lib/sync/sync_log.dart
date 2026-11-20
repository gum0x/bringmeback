import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A record of what sync does, step by step, to copy from the Devices page and share when devices
/// don't find each other. Each line is also printed to the console (`[bmb sync] …`), so the browser's
/// developer tools show it too.
///
/// It never holds tasks, the group code or keys: only relay hosts, short device and session ids,
/// event kinds and short event ids, counts and reasons.
class SyncLog {
  SyncLog._();

  static final instance = SyncLog._();

  /// The oldest lines are dropped beyond this many.
  static const limit = 2000;

  final _lines = ListQueue<String>();
  final _changes = StreamController<void>.broadcast();

  /// Whether lines are printed to the console too. Tests turn it off.
  bool printing = true;

  /// The lines, oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  /// Fires after each new line.
  Stream<void> get changes => _changes.stream;

  void add(String message) {
    final line = '${stamp(DateTime.now())} $message';
    _lines.addLast(line);
    while (_lines.length > limit) {
      _lines.removeFirst();
    }
    if (printing) debugPrint('[bmb sync] $line');
    _changes.add(null);
  }

  void clear() {
    _lines.clear();
    _changes.add(null);
  }

  /// The whole log as text, after a header that says which device and build wrote it.
  String export(String header) => '$header\n${_lines.join('\n')}\n';

  /// "2026-11-20 09:41:07.123", local time.
  static String stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Adds a line to [SyncLog].
void syncLog(String message) => SyncLog.instance.add(message);

/// The first bytes of an id, as hex, enough to tell sessions and events apart in the log.
String shortHex(List<int> bytes, [int length = 4]) => bytes
    .take(length)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// A device's short id, as the Devices page shows it ("Device CGJehB").
String deviceShort(List<int> device) {
  final id = base64Url.encode(device).replaceAll('=', '');
  return id.length > 6 ? id.substring(0, 6) : id;
}
