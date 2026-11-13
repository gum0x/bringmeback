import 'package:bringmeback/version/build_info.dart';
import 'package:bringmeback/version/update_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BuildInfo', () {
    final t = DateTime.utc(2026, 11, 13, 12, 30);

    test('a release shows its number, other builds the commit time and commit', () {
      expect(const BuildInfo(version: '1.2.0').label, 'v1.2.0');
      expect(BuildInfo(commit: '70135a09b6', time: t).label, '2026-11-13 12:30 UTC · 70135a09b6');
      expect(const BuildInfo(version: '1.2.0', commit: 'abc').label, 'v1.2.0 · abc');
      expect(const BuildInfo().label, 'Development build, no commit');
      expect(const BuildInfo().isKnown, isFalse);
    });

    test('newer means a higher release, or else a later commit', () {
      expect(const BuildInfo(version: '1.9.2').isOlderThan(const BuildInfo(version: '1.10.0')),
          isTrue);
      expect(const BuildInfo(version: '1.10.0').isOlderThan(const BuildInfo(version: '1.9.2')),
          isFalse);
      final old = BuildInfo(commit: 'a', time: t);
      final later = BuildInfo(commit: 'b', time: t.add(const Duration(hours: 1)));
      expect(old.isOlderThan(later), isTrue);
      expect(later.isOlderThan(old), isFalse);
      expect(old.isOlderThan(old), isFalse);
      expect(const BuildInfo().isOlderThan(later), isFalse);
    });

    test('round-trips through JSON, and reads anything else as unknown', () {
      final b = BuildInfo(version: '1.0.0', commit: 'abc', time: t);
      final back = BuildInfo.fromJson(b.toJson());
      expect(back.sameAs(b), isTrue);
      expect(back.time, t);
      expect(BuildInfo.fromJson('nope').isKnown, isFalse);
      expect(BuildInfo.fromJson({'commit': 42}).isKnown, isFalse);
      expect(BuildInfo.fromJson({'commit': 'x' * 500}).commit.length, 40);
    });
  });

  group('UpdateCubit', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a newer build found by the check is reported', () async {
      // Tests run as an unknown build, which is never older; compare against what was found.
      final found = BuildInfo(commit: 'new', time: DateTime.utc(2030));
      final cubit = UpdateCubit(latest: (_) async => found);
      await cubit.load();
      expect(cubit.state.latest!.sameAs(found), isTrue);
      expect(cubit.state.checkedAt, isNotNull);
      expect(cubit.state.error, isNull);
      expect(cubit.timerActive, isTrue);
      await cubit.close();
      expect(cubit.timerActive, isFalse);
    });

    test('a failed check keeps what was known and says why', () async {
      var calls = 0;
      final cubit = UpdateCubit(latest: (_) async {
        if (calls++ > 0) throw StateError('offline');
        return const BuildInfo(version: '2.0.0');
      });
      await cubit.load();
      await cubit.check();
      expect(cubit.state.latest!.version, '2.0.0');
      expect(cubit.state.error, contains('offline'));
      await cubit.close();
    });

    test('checking releases is off by default and remembered when turned on', () async {
      final seen = <bool>[];
      final cubit = UpdateCubit(latest: (s) async {
        seen.add(s.checkReleases);
        return null;
      });
      await cubit.load();
      await cubit.setCheckReleases(true);
      expect(seen, [false, true]);
      expect((await SharedPreferences.getInstance()).getBool('checkReleases'), isTrue);
      await cubit.close();
    });
  });
}
