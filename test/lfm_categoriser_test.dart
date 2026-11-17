import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:bringmeback/category/lfm_categoriser.dart';
import 'package:bringmeback/category/lfm_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the prompt lists each category, with its keywords, rules and examples', () {
    final text = LfmCategoriser.instructions(const [
      TaskCategory(id: 'w', name: 'Work planning', keywords: 'email plan'),
      TaskCategory(id: 'p', name: 'Personal projects', rules: 'bringmeback, BMB'),
    ], examples: [
      (text: 'backlog grooming', category: 'w'),
      (text: 'gone', category: 'deleted'),
    ]);
    expect(text, contains('- Work planning (for example: email, plan)'));
    expect(text, contains('- Personal projects. Always for tasks that mention: bringmeback, bmb'));
    expect(text, contains('backlog grooming => Work planning'));
    expect(text, isNot(contains('gone')));
  });

  test('softmax turns log-probabilities into probabilities', () {
    final p = LfmCategoriser.softmax([-1, -1, -3]);
    expect(p.reduce((a, b) => a + b), closeTo(1, 1e-9));
    expect(p[0], closeTo(p[1], 1e-9));
    expect(p[2], lessThan(p[0]));
  });

  group('the task list', () {
    Future<TasksBloc> newBloc(SmartCategoriser smart, {Categoriser? words}) async {
      final bloc = TasksBloc(
          categoriser: () async => words ?? (throw StateError('no vectors in this test')));
      bloc.smartCategoriser = smart;
      await settle();
      return bloc;
    }

    test('files a task where the language model says', () async {
      final asked = <String>[];
      final bloc = await newBloc((text, categories, examples) async {
        asked.add(text);
        return 'learning';
      });
      bloc.add(AddTaskOnTopEvent(name: 'Lección de piano', id: const ValueKey('a')));
      await settle();
      expect(asked, ['Lección de piano']);
      expect(bloc.state.tasks.single.category, 'learning');
      expect(bloc.state.tasks.single.categoryByHand, isFalse);
      await bloc.close();
    });

    test('a rule decides before the language model', () async {
      var asked = 0;
      final bloc = await newBloc((text, categories, examples) async {
        asked++;
        return 'leisure';
      });
      bloc.add(AddCategoryEvent(name: 'Acme', rules: 'acme'));
      await settle();
      bloc.add(AddTaskOnTopEvent(name: 'Acme invoice', id: const ValueKey('a')));
      await settle();
      expect(bloc.state.category(bloc.state.tasks.single.category)?.name, 'Acme');
      expect(asked, 0);
      await bloc.close();
    });

    test('when the model is unsure or unavailable, the word vectors decide', () async {
      for (final smart in <SmartCategoriser>[
        (text, categories, examples) async => null,
        (text, categories, examples) async => throw StateError('not downloaded'),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final bloc = await newBloc(smart, words: _FixedCategoriser('housekeeping'));
        bloc.add(AddTaskOnTopEvent(name: 'Clean the kitchen', id: const ValueKey('a')));
        await settle();
        expect(bloc.state.tasks.single.category, 'housekeeping');
        await bloc.close();
      }
    });

    test('a pick for a name the task no longer has is dropped', () async {
      final bloc = await newBloc((text, categories, examples) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return text == 'Go for a run' ? 'workout-self-care' : 'leisure';
      });
      bloc.add(AddTaskOnTopEvent(name: 'Go for a run', id: const ValueKey('a')));
      bloc.add(UpdateTaskNameEvent(id: const ValueKey('a'), newName: 'Watch a movie'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bloc.state.tasks.single.category, 'leisure');
      await bloc.close();
    });
  });

  group('turning LFM2.5 on and off', () {
    test('downloads, loads, and comes back on at the next start', () async {
      var loads = 0;
      final cubit = LfmCubit(load: ({onProgress}) async {
        loads++;
        throw StateError('no model in tests');
      });
      final seen = <LfmStatus>[];
      final sub = cubit.stream.listen((s) => seen.add(s.status));
      await cubit.restore();
      expect(loads, 0, reason: 'off until the user turns it on');
      await cubit.turnOn();
      await settle();
      expect(seen, [LfmStatus.downloading, LfmStatus.failed]);
      expect(cubit.state.error, contains('no model in tests'));
      expect(() => cubit.categorise('x', const [], const []), throwsStateError);

      final again = LfmCubit(load: ({onProgress}) async {
        loads++;
        throw StateError('still none');
      });
      await again.restore();
      expect(loads, 2, reason: 'turned on last time, so it loads at start');
      await again.turnOff();
      expect(again.state.status, LfmStatus.off);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('lfmCategories'), isFalse);
      await sub.cancel();
      await cubit.close();
      await again.close();
    });

    test('errors read as something to act on', () {
      expect(LfmCubit.describeError(Exception('needs COOP/COEP headers')), contains('isolation'));
      expect(LfmCubit.describeError(Exception('SocketException: no route')),
          contains('download failed'));
    });
  });
}

class _FixedCategoriser implements Categoriser {
  final String id;

  _FixedCategoriser(this.id);

  @override
  String? categorise(String text, List<TaskCategory> categories,
          {List<CategoryExample> examples = const []}) =>
      id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
