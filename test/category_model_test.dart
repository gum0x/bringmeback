import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:bringmeback/category/categoriser.dart';
import 'package:bringmeback/category/category_model_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the task list', () {
    Future<TasksBloc> newBloc(SmartCategoriser smart, {Categoriser? words}) async {
      final bloc = TasksBloc(
          categoriser: () async => words ?? (throw StateError('no vectors in this test')));
      bloc.smartCategoriser = smart;
      await settle();
      return bloc;
    }

    test('files a task where the multilingual model says', () async {
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

    test('a rule decides before the multilingual model', () async {
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

    test('the word vectors decide first; the model only places what they can\'t', () async {
      var asked = 0;
      final bloc = await newBloc((text, categories, examples) async {
        asked++;
        return 'leisure';
      }, words: _FixedCategoriser('housekeeping'));
      bloc.add(AddTaskOnTopEvent(name: 'Clean the kitchen', id: const ValueKey('a')));
      await settle();
      expect(bloc.state.tasks.single.category, 'housekeeping');
      expect(asked, 0);
      await bloc.close();
    });

    test('when the model fails, the task waits without a category', () async {
      final bloc = await newBloc((text, categories, examples) async => throw StateError('gone'));
      bloc.add(AddTaskOnTopEvent(name: 'Limpiar la cocina', id: const ValueKey('a')));
      await settle();
      expect(bloc.state.tasks.single.category, isNull);
      await bloc.close();
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

  group('turning the multilingual model on and off', () {
    test('downloads, loads, and comes back on at the next start', () async {
      var loads = 0;
      final cubit = CategoryModelCubit(load: ({onProgress}) async {
        loads++;
        throw StateError('no model in tests');
      });
      final seen = <CategoryModelStatus>[];
      final sub = cubit.stream.listen((s) => seen.add(s.status));
      await cubit.restore();
      expect(loads, 0, reason: 'off until the user turns it on');
      await cubit.turnOn();
      await settle();
      expect(seen, [CategoryModelStatus.downloading, CategoryModelStatus.failed]);
      expect(cubit.state.error, contains('no model in tests'));
      expect(() => cubit.categorise('x', const [], const []), throwsStateError);

      final again = CategoryModelCubit(load: ({onProgress}) async {
        loads++;
        throw StateError('still none');
      });
      await again.restore();
      expect(loads, 2, reason: 'turned on last time, so it loads at start');
      await again.turnOff();
      expect(again.state.status, CategoryModelStatus.off);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('multilingualCategories'), isFalse);
      await sub.cancel();
      await cubit.close();
      await again.close();
    });

    test('errors read as something to act on', () {
      expect(CategoryModelCubit.describeError(Exception('needs COOP/COEP headers')), contains('isolation'));
      expect(CategoryModelCubit.describeError(Exception('SocketException: no route')),
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
