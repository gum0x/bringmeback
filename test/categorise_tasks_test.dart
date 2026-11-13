import 'dart:io';

import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _categoriser = Categoriser(
    WordVectors.parse(ByteData.sublistView(File(wordVectorsAsset).readAsBytesSync())));

Future<TasksBloc> newBloc() async {
  final bloc = TasksBloc(categoriser: () async => _categoriser);
  await settle();
  return bloc;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

String? categoryName(TasksBloc bloc, int index) =>
    bloc.state.category(bloc.state.tasks[index].category)?.name;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a task written gets a category from the list, saved with the task', () async {
    final bloc = await newBloc();
    bloc.add(AddSuggestedCategoriesEvent());
    await settle();
    expect(bloc.state.categories.map((c) => c.name), contains('Health'));

    bloc.add(AddTaskOnTopEvent(name: 'Book dentist appointment', id: const ValueKey('a')));
    await settle();
    expect(categoryName(bloc, 0), 'Health');
    expect(bloc.state.tasks[0].categoryByHand, isFalse);
    expect(bloc.taskDocument!.task('a').category, bloc.state.tasks[0].category);

    // Renaming it files it again.
    bloc.add(EditTaskEvent(
        id: const ValueKey('a'), name: 'Pay electricity bill', timerLengthSeconds: 1200));
    await settle();
    expect(categoryName(bloc, 0), 'Money');
    await bloc.close();
  });

  test('a category chosen by hand stays, and the categoriser learns from it', () async {
    final bloc = await newBloc();
    bloc.add(AddCategoryEvent(name: 'Work', keywords: 'office meeting project'));
    bloc.add(AddCategoryEvent(name: 'Home', keywords: 'house cleaning kitchen'));
    await settle();
    final work = bloc.state.categories.firstWhere((c) => c.name == 'Work').id;

    bloc.add(AddTaskOnTopEvent(
        name: 'Standup', id: const ValueKey('a'), category: CategoryPick.hand(work)));
    await settle();
    expect((categoryName(bloc, 0), bloc.state.tasks[0].categoryByHand), ('Work', true));

    // A task much like it goes the same way.
    bloc.add(AddTaskOnTopEvent(name: 'Daily standup', id: const ValueKey('b')));
    await settle();
    expect(categoryName(bloc, 0), 'Work');

    // Renaming doesn't override the user's choice...
    bloc.add(UpdateTaskNameEvent(id: const ValueKey('a'), newName: 'Clean the kitchen'));
    await settle();
    expect(categoryName(bloc, 1), 'Work');
    // ...until it goes back to automatic.
    bloc.add(SetTaskCategoryEvent(id: 'a', category: const CategoryPick.auto()));
    await settle();
    expect((categoryName(bloc, 1), bloc.state.tasks[1].categoryByHand), ('Home', false));

    // None, by hand, also stays.
    bloc.add(SetTaskCategoryEvent(id: 'b', category: const CategoryPick.hand(null)));
    await settle();
    expect((bloc.state.tasks[0].category, bloc.state.tasks[0].categoryByHand), (null, true));
    await bloc.close();
  });

  test('changing the list files the tasks on the note again', () async {
    final bloc = await newBloc();
    bloc.add(AddTaskOnTopEvent(name: 'Go for a run', id: const ValueKey('a')));
    await settle();
    expect(bloc.state.tasks[0].category, isNull);

    bloc.add(AddCategoryEvent(name: 'Sport', keywords: 'run gym exercise'));
    await settle();
    expect(categoryName(bloc, 0), 'Sport');

    bloc.add(RemoveCategoryEvent(id: bloc.state.categories.single.id));
    await settle();
    expect(bloc.state.tasks[0].category, isNull);
    await bloc.close();
  });

  test('without the categoriser, tasks are still written, with no category', () async {
    final bloc = TasksBloc(categoriser: () async => throw StateError('no vectors'));
    await settle();
    bloc.add(AddCategoryEvent(name: 'Work'));
    bloc.add(AddTaskOnTopEvent(name: 'Write report', id: const ValueKey('a')));
    await settle();
    expect(bloc.state.tasks.single.name, 'Write report');
    expect(bloc.state.tasks.single.category, isNull);
    await bloc.close();
  });
}
