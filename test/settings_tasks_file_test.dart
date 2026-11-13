import 'dart:io';

import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/settings/settings_page.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers the save dialog with [savePath] and the open dialog with [openPath].
class FakeFileSelector extends FileSelectorPlatform {
  String? savePath;
  String? openPath;
  List<XTypeGroup>? lastTypes;

  @override
  Future<FileSaveLocation?> getSaveLocation(
      {List<XTypeGroup>? acceptedTypeGroups, SaveDialogOptions options = const SaveDialogOptions()}) async {
    lastTypes = acceptedTypeGroups;
    return savePath == null ? null : FileSaveLocation(savePath!);
  }

  @override
  Future<XFile?> openFile(
      {List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async {
    lastTypes = acceptedTypeGroups;
    return openPath == null ? null : XFile(openPath!);
  }
}

/// Lets real file reads and writes, and the bloc's loading, finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

/// Runs [body] on the Settings page over a fresh [TasksBloc] with nothing saved.
Future<void> onSettings(WidgetTester tester,
    Future<void> Function(TasksBloc bloc) body) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bloc = TasksBloc();
  await tester.pumpWidget(BlocProvider.value(
      value: bloc, child: const MaterialApp(home: SettingsPage())));
  await settle(tester);
  await body(bloc);
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(bloc.close);
}

List<String> names(TasksBloc bloc) => [for (final t in bloc.state.tasks) t.name];

void main() {
  late FakeFileSelector files;
  late Directory dir;

  setUp(() {
    files = FakeFileSelector();
    FileSelectorPlatform.instance = files;
    dir = Directory.systemTemp.createTempSync('bmb-tasks');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('tasks exported from Settings import back on another device', (tester) async {
    final path = '${dir.path}/tasks.json';

    // One device writes two tasks, checks one off and exports them.
    await onSettings(tester, (bloc) async {
      bloc
        ..add(InsertTaskEvent(index: 0, name: 'write report', id: ValueKey('a' * 32)))
        ..add(InsertTaskEvent(
            index: 1,
            name: 'call bank',
            id: ValueKey('b' * 32),
            timerLengthSeconds: 600,
            notes: 'ask about the fee'));
      await settle(tester);
      bloc.add(SetDoneEvent(index: 0, done: true));
      await settle(tester);

      files.savePath = path;
      await tester.tap(find.byKey(const Key('exportTasks')));
      await settle(tester);
      expect(files.lastTypes!.single.extensions, ['json']);
      expect(find.textContaining('Tasks exported to bringmeback-tasks-'), findsOneWidget);
    });
    expect(File(path).existsSync(), isTrue);

    // A fresh device, with a task of its own, imports the file twice.
    await onSettings(tester, (bloc) async {
      bloc.add(InsertTaskEvent(index: 0, name: 'what I am doing', id: ValueKey('c' * 32)));
      await settle(tester);

      files.openPath = path;
      await tester.tap(find.byKey(const Key('importTasks')));
      await settle(tester);
      expect(find.text('Imported: 2 tasks added to the note.'), findsOneWidget);
      expect(names(bloc), ['what I am doing', 'write report', 'call bank']);
      final [_, report, bank] = bloc.state.tasks;
      expect(report.done, isTrue);
      expect((bank.done, bank.timerLengthSeconds, bank.notes), (false, 600, 'ask about the fee'));
      // The task being worked on stays the current one.
      expect(bloc.state.currentIndex, 0);

      await tester.tap(find.byKey(const Key('importTasks')));
      await settle(tester);
      expect(find.text('Imported: 2 tasks already here.'), findsOneWidget);
      expect(names(bloc), ['what I am doing', 'write report', 'call bank']);
    });
  });

  testWidgets('a file that is not a tasks file says so and changes nothing', (tester) async {
    final path = '${dir.path}/other.json';
    File(path).writeAsStringSync('{"hello": "world"}');

    await onSettings(tester, (bloc) async {
      files.openPath = path;
      await tester.tap(find.byKey(const Key('importTasks')));
      await settle(tester);
      expect(find.text('This file is not a bringmeback tasks file.'), findsOneWidget);
      expect(bloc.state.tasks, isEmpty);
    });
  });

  testWidgets('cancelling the dialogs does nothing', (tester) async {
    await onSettings(tester, (bloc) async {
      await tester.tap(find.byKey(const Key('exportTasks')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('importTasks')));
      await settle(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(dir.listSync(), isEmpty);
    });
  });
}
