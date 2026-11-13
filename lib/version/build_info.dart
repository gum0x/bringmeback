/// Which build of the app this is, so two devices can tell whether they run the same one.
///
/// Set at build time with `--dart-define`:
/// - `APP_VERSION`: the release number (`1.2.0`), for released builds only;
/// - `BUILD_COMMIT`: the commit it was built from, short form, with `-dirty` for local changes;
/// - `BUILD_TIME`: when that commit was made, ISO 8601.
/// `tool/build_info.sh` prints these for the current checkout.
class BuildInfo {
  final String version;
  final String commit;
  final DateTime? time;

  const BuildInfo({this.version = '', this.commit = '', this.time});

  /// This build.
  static final current = BuildInfo(
      version: const String.fromEnvironment('APP_VERSION'),
      commit: const String.fromEnvironment('BUILD_COMMIT'),
      time: DateTime.tryParse(const String.fromEnvironment('BUILD_TIME'))?.toUtc());

  bool get isRelease => version.isNotEmpty;

  /// False for a build without any of the defines, such as `flutter run`.
  bool get isKnown => isRelease || commit.isNotEmpty;

  /// How the build is shown: the release number, or the commit time and commit.
  String get label {
    if (isRelease) return 'v$version';
    if (commit.isEmpty) return 'Development build';
    final t = time;
    return t == null ? commit : '${_format(t)} · $commit';
  }

  bool sameAs(BuildInfo other) => version == other.version && commit == other.commit;

  /// Whether `other` is a newer build than this one: a higher release number, or else a later
  /// commit time. Unknown builds are never older or newer.
  bool isOlderThan(BuildInfo other) {
    if (!isKnown || !other.isKnown || sameAs(other)) return false;
    if (isRelease && other.isRelease) return _compareVersions(version, other.version) < 0;
    final mine = time, theirs = other.time;
    return mine != null && theirs != null && theirs.isAfter(mine);
  }

  Map<String, Object> toJson() => {
        if (version.isNotEmpty) 'version': version,
        if (commit.isNotEmpty) 'commit': commit,
        if (time != null) 'time': time!.toIso8601String(),
      };

  /// Reads what [toJson] wrote, from another device or the server. Anything that doesn't fit reads
  /// as an unknown build; text is cut short so it can't fill the screen.
  static BuildInfo fromJson(Object? json) {
    if (json is! Map) return const BuildInfo();
    String text(Object? v) => v is String ? (v.length > 40 ? v.substring(0, 40) : v) : '';
    return BuildInfo(
        version: text(json['version']),
        commit: text(json['commit']),
        time: DateTime.tryParse(text(json['time']))?.toUtc());
  }

  static String _format(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final u = t.toUtc();
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)} UTC';
  }

  /// Compares dotted numbers (`1.10.0` > `1.9.2`); a leading `v` and anything after `-` or `+` in a
  /// part are ignored.
  static int _compareVersions(String a, String b) {
    List<int> parts(String v) => [
          for (final p in v.replaceFirst(RegExp('^v'), '').split('.'))
            int.tryParse(p.split(RegExp('[-+]')).first) ?? 0
        ];
    final x = parts(a), y = parts(b);
    for (var i = 0; i < x.length || i < y.length; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }
}
