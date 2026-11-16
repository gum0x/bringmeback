import 'package:bringmeback/version/build_info.dart';
import 'package:bringmeback/version/dev_band.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(BuildInfo build, {double top = 0}) => MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), padding: EdgeInsets.only(top: top)),
        child: MaterialApp(
          builder: (context, child) => DevBand(info: build, child: child!),
          home: Scaffold(
            body: Builder(builder: (context) => Text('top ${MediaQuery.paddingOf(context).top}')),
          ),
        ),
      );

  testWidgets('a development build shows the strip with its commit', (tester) async {
    await tester
        .pumpWidget(app(BuildInfo(commit: 'abc1234', time: DateTime.utc(2026, 11, 16, 11))));
    expect(find.byKey(const Key('dev-band')), findsOneWidget);
    expect(find.text('DEV BUILD · 2026-11-16 11:00 UTC · abc1234'), findsOneWidget);
  });

  testWidgets('a build without defines still shows the strip', (tester) async {
    await tester.pumpWidget(app(const BuildInfo()));
    expect(find.text('DEV BUILD'), findsOneWidget);
  });

  testWidgets('a release shows no strip', (tester) async {
    await tester.pumpWidget(app(const BuildInfo(version: '1.0.0', commit: 'abc1234')));
    expect(find.byKey(const Key('dev-band')), findsNothing);
    expect(find.textContaining('DEV BUILD'), findsNothing);
  });

  testWidgets('the strip sits above the app, under the status bar, without covering it',
      (tester) async {
    await tester.pumpWidget(app(const BuildInfo(commit: 'abc'), top: 40));
    final band = tester.getRect(find.byKey(const Key('dev-band')));
    expect(band.top, 0);
    expect(band.height, 40 + DevBand.height);
    // The app starts below the strip and no longer pads for the status bar itself.
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, band.bottom);
    expect(find.text('top 0.0'), findsOneWidget);
  });
}
