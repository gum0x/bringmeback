import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_info.dart';
import 'platform.dart' as platform;

/// What the latest version check found.
class UpdateState {
  /// The newest build the check found, when it found one.
  final BuildInfo? latest;

  /// When the last check finished, and why it failed if it did.
  final DateTime? checkedAt;
  final String? error;

  /// Whether this device may ask GitHub for the latest release. Off by default; only release builds
  /// that aren't the web app use it.
  final bool checkReleases;

  const UpdateState({this.latest, this.checkedAt, this.error, this.checkReleases = false});

  /// Whether a newer build than this one is out.
  bool get newer => latest != null && BuildInfo.current.isOlderThan(latest!);
}

/// Where the latest build is told: the web app's own server, or GitHub releases.
typedef LatestBuild = Future<BuildInfo?> Function(UpdateState state);

/// Checks for a newer version of the app when it starts, every so often, and when it comes back to
/// the front.
///
/// The web app asks its own server for `build-info.json`, which says which build it serves now, so
/// a tab that still runs an older one finds out and can reload. Release builds of the other apps
/// can ask GitHub for the latest release, but only once that is turned on in Settings: no service
/// is contacted otherwise.
class UpdateCubit extends Cubit<UpdateState> {
  static const _checkReleasesKey = 'checkReleases';
  static const interval = Duration(minutes: 30);

  /// The repository whose releases are checked.
  static const releaseRepo =
      String.fromEnvironment('RELEASE_REPO', defaultValue: 'gum0x/bringmeback');

  final LatestBuild _latest;
  Timer? _timer;
  bool _checking = false;

  UpdateCubit({LatestBuild? latest})
      : _latest = latest ?? defaultLatest,
        super(const UpdateState());

  /// Whether a check can find anything on this build.
  static bool get supported => platform.servedBuildInfo() != null || BuildInfo.current.isRelease;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (isClosed) return;
    emit(UpdateState(checkReleases: prefs.getBool(_checkReleasesKey) ?? false));
    await check();
    _timer = Timer.periodic(interval, (_) => check());
  }

  Future<void> setCheckReleases(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_checkReleasesKey, on);
    if (isClosed) return;
    emit(UpdateState(
        latest: state.latest, checkedAt: state.checkedAt, error: state.error, checkReleases: on));
    if (on) await check();
  }

  Future<void> check() async {
    if (_checking || isClosed) return;
    _checking = true;
    try {
      final latest = await _latest(state);
      if (!isClosed) {
        emit(UpdateState(
            latest: latest ?? state.latest,
            checkedAt: DateTime.now(),
            checkReleases: state.checkReleases));
      }
    } on Object catch (e) {
      if (!isClosed) {
        emit(UpdateState(
            latest: state.latest,
            checkedAt: DateTime.now(),
            error: '$e',
            checkReleases: state.checkReleases));
      }
    } finally {
      _checking = false;
    }
  }

  static Future<BuildInfo?> defaultLatest(UpdateState state) async {
    final served = platform.servedBuildInfo();
    if (served != null) {
      final info = BuildInfo.fromJson(await platform.fetchJson(served));
      return info.isKnown ? info : null;
    }
    if (!BuildInfo.current.isRelease || !state.checkReleases) return null;
    final json = await platform
        .fetchJson(Uri.https('api.github.com', '/repos/$releaseRepo/releases/latest'));
    final tag = json is Map ? json['tag_name'] : null;
    if (tag is! String) return null;
    return BuildInfo(version: tag.replaceFirst(RegExp('^v'), ''));
  }

  @visibleForTesting
  bool get timerActive => _timer?.isActive ?? false;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
