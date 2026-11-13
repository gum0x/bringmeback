import 'dart:io';

import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:bringmeback/category/default_categories.dart';
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

  test('a task written gets a category from the default list, saved with the task', () async {
    final bloc = await newBloc();
    expect(bloc.state.categories.map((c) => c.name), contains('Workout and self-care'));

    bloc.add(AddTaskOnTopEvent(name: 'Book dentist appointment', id: const ValueKey('a')));
    await settle();
    expect(categoryName(bloc, 0), 'Workout and self-care');
    expect(bloc.state.tasks[0].categoryByHand, isFalse);
    expect(bloc.taskDocument!.task('a').category, bloc.state.tasks[0].category);

    // Renaming it files it again.
    bloc.add(EditTaskEvent(
        id: const ValueKey('a'), name: 'Pay electricity bill', timerLengthSeconds: 1200));
    await settle();
    expect(categoryName(bloc, 0), 'Money and paperwork');
    await bloc.close();
  });

  test('a rule set in Settings files a project\'s tasks', () async {
    final bloc = await newBloc();
    bloc.add(EditCategoryEvent(
        id: 'personal-projects',
        name: 'Personal projects',
        keywords: defaultCategory('personal-projects')!.keywords,
        rules: 'bringmeback'));
    bloc.add(AddTaskOnTopEvent(name: 'Fix the sync bug in bringmeback', id: const ValueKey('a')));
    await settle();
    expect(categoryName(bloc, 0), 'Personal projects');
    // Only the rules were written; the name and keywords still follow the defaults.
    expect(bloc.taskDocument!.fieldInt('category/personal-projects/name'), isNull);
    await bloc.close();
  });

  test('default categories can be deleted, renamed and restored', () async {
    final bloc = await newBloc();
    bloc.add(RemoveCategoryEvent(id: 'leisure'));
    bloc.add(EditCategoryEvent(id: 'errands', name: 'Shopping', keywords: 'buy'));
    await settle();
    expect(bloc.state.categories.map((c) => c.id), isNot(contains('leisure')));
    expect(bloc.state.category('errands')!.name, 'Shopping');
    bloc.add(RestoreDefaultCategoriesEvent());
    await settle();
    expect(bloc.state.categories.map((c) => c.id), contains('leisure'));
    expect(bloc.state.category('errands')!.name, 'Shopping');
    await bloc.close();
  });

  test('a category chosen by hand stays, and the categoriser learns from it', () async {
    final bloc = await newBloc();
    bloc.add(AddCategoryEvent(name: 'Agile', keywords: 'scrum'));
    await settle();
    final agile = bloc.state.categories.firstWhere((c) => c.name == 'Agile').id;

    bloc.add(AddTaskOnTopEvent(
        name: 'Backlog grooming', id: const ValueKey('a'), category: CategoryPick.hand(agile)));
    await settle();
    expect((categoryName(bloc, 0), bloc.state.tasks[0].categoryByHand), ('Agile', true));

    // A task much like it goes the same way.
    bloc.add(AddTaskOnTopEvent(name: 'Groom the backlog', id: const ValueKey('b')));
    await settle();
    expect(categoryName(bloc, 0), 'Agile');

    // Renaming doesn't override the user's choice...
    bloc.add(UpdateTaskNameEvent(id: const ValueKey('a'), newName: 'Clean the kitchen'));
    await settle();
    expect(categoryName(bloc, 1), 'Agile');
    // ...until it goes back to automatic.
    bloc.add(SetTaskCategoryEvent(id: 'a', category: const CategoryPick.auto()));
    await settle();
    expect((categoryName(bloc, 1), bloc.state.tasks[1].categoryByHand), ('Housekeeping', false));

    // None, by hand, also stays.
    bloc.add(SetTaskCategoryEvent(id: 'b', category: const CategoryPick.hand(null)));
    await settle();
    expect((bloc.state.tasks[0].category, bloc.state.tasks[0].categoryByHand), (null, true));
    await bloc.close();
  });

  test('changing the list files the tasks on the note again', () async {
    final bloc = await newBloc();
    bloc.add(AddTaskOnTopEvent(name: 'Zumba with Ana', id: const ValueKey('a')));
    await settle();
    expect(categoryName(bloc, 0), isNot('Dance'));

    bloc.add(AddCategoryEvent(name: 'Dance', rules: 'zumba'));
    await settle();
    expect(categoryName(bloc, 0), 'Dance');

    bloc.add(RemoveCategoryEvent(id: bloc.state.categories.last.id));
    await settle();
    expect(categoryName(bloc, 0), isNot('Dance'));
    await bloc.close();
  });

  test('without the word vectors, tasks are still written, and only rules file them', () async {
    final bloc = TasksBloc(categoriser: () async => throw StateError('no vectors'));
    await settle();
    bloc.add(AddCategoryEvent(name: 'Acme', rules: 'acme'));
    bloc.add(AddTaskOnTopEvent(name: 'Write report', id: const ValueKey('a')));
    bloc.add(AddTaskOnTopEvent(name: 'Acme invoice', id: const ValueKey('b')));
    await settle();
    expect(bloc.state.tasks.map((t) => t.name), ['Acme invoice', 'Write report']);
    expect(bloc.state.tasks.map((t) => bloc.state.category(t.category)?.name), ['Acme', null]);
    await bloc.close();
  });
}
