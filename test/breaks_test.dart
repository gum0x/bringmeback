import 'package:bringmeback/bloc/breaks.dart';
import 'package:bringmeback/bloc/task_document.dart';
import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TaskDocument newDoc() =>
    TaskDocument(CRDTDocument(peerId: PeerId.generate(), documentId: 'tasks'));

/// Sends each side the changes it is missing.
void exchange(TaskDocument a, TaskDocument b) {
  b.doc.importChanges(a.doc.exportChanges(fromVersionVector: b.doc.getVersionVector()));
  a.doc.importChanges(b.doc.exportChanges(fromVersionVector: a.doc.getVersionVector()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // TasksBloc makes an audio player; tests have no audio plugin.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) async {
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      }
      return handler?.call(message);
    };
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('break types', () {
    test('the defaults are all long enough to rest', () {
      expect(defaultBreakCategories, isNotEmpty);
      for (final c in defaultBreakCategories) {
        expect(c.minutes, greaterThanOrEqualTo(recommendedBreakMinutes));
        expect(breakIcons.containsKey(c.icon), isTrue);
      }
    });

    test('are saved and read back; anything unreadable falls back to the defaults', () {
      const list = [
        BreakCategory(name: 'Nap', minutes: 20, icon: 'rest'),
        BreakCategory(name: 'Call mum', minutes: 15, icon: 'call'),
      ];
      expect(decodeBreakCategories(encodeBreakCategories(list)), list);
      expect(decodeBreakCategories(null), defaultBreakCategories);
      expect(decodeBreakCategories('not json'), defaultBreakCategories);
      expect(decodeBreakCategories('{}'), defaultBreakCategories);
      // Removing every type is kept.
      expect(decodeBreakCategories('[]'), isEmpty);
      // Bad entries are dropped, lengths kept in range, unknown icons replaced.
      expect(
          decodeBreakCategories(
              '[{"name":"","minutes":5},{"name":"Gym","minutes":999,"icon":"rocket"},7]'),
          [const BreakCategory(name: 'Gym', minutes: maxBreakMinutes, icon: 'pause')]);
    });
  });

  group('the document', () {
    test('keeps what a break is for and how long it should last', () {
      final d = newDoc();
      expect(d.currentPause, isNull);
      d.startPause('p', reason: 'Lunch', plannedSeconds: 45 * 60, at: 1000);
      final pause = d.currentPause!;
      expect((pause.id, pause.startedAt, pause.reason, pause.plannedSeconds),
          ('p', 1000, 'Lunch', 45 * 60));
      expect(d.pauseStartedAt, 1000);

      d.setPause('p', reason: 'Walk', plannedSeconds: null);
      expect((d.currentPause!.reason, d.currentPause!.plannedSeconds), ('Walk', null));

      d.endPauses();
      expect(d.currentPause, isNull);
      // A pause stays out of the tasks.
      expect(d.allTaskIds, isEmpty);
    });

    test('a plain pause has no reason or timer', () {
      final d = newDoc()..startPause('p');
      expect((d.currentPause!.reason, d.currentPause!.plannedSeconds), (null, null));
    });

    test('a break and its changes sync to the other device', () {
      final a = newDoc()..insert(0, 't', name: 'Write report');
      final b = newDoc();
      exchange(a, b);

      a.setRunning('t', false);
      a.startPause('p', reason: 'Coffee', plannedSeconds: 5 * 60, at: 2000);
      exchange(a, b);
      expect(b.currentPause?.reason, 'Coffee');
      expect(b.currentPause?.plannedSeconds, 5 * 60);
      expect(b.currentPause?.startedAt, 2000);

      // Changed on the other device, it comes back.
      b.setPause('p', reason: 'Lunch', plannedSeconds: 45 * 60);
      exchange(a, b);
      expect((a.currentPause?.reason, a.currentPause?.plannedSeconds), ('Lunch', 45 * 60));

      a.endPauses();
      exchange(a, b);
      expect(b.currentPause, isNull);
    });

    test('should both devices start a break apart, the one started first counts', () {
      final a = newDoc();
      final b = newDoc();
      a.startPause('pa', reason: 'Walk', plannedSeconds: 900, at: 3000);
      b.startPause('pb', reason: 'Coffee', plannedSeconds: 300, at: 2990);
      exchange(a, b);
      expect(a.currentPause?.id, 'pb');
      expect(b.currentPause?.id, 'pb');
    });
  });

  group('the bloc', () {
    Future<TasksBloc> working() async {
      final tasks = TasksBloc();
      await tasks.document;
      tasks.add(ToggleMuteEvent());
      tasks.add(AddTaskOnTopEvent(name: 'Write report', id: const ValueKey('t')));
      await Future<void>.delayed(Duration.zero);
      expect(tasks.state.tasks.single.running, isTrue);
      return tasks;
    }

    test('taking a break of a kind pauses the work and logs it', () async {
      final tasks = await working();
      tasks.add(TakeBreakEvent(reason: 'Lunch', plannedSeconds: 45 * 60));
      await Future<void>.delayed(Duration.zero);
      final s = tasks.state;
      expect(s.onBreak, isTrue);
      expect(s.tasks.single.running, isFalse);
      expect(s.breakReason, 'Lunch');
      expect(s.breakPlannedSeconds, 45 * 60);
      expect(s.breakRemainingAt(s.breakStartedAt!), 45 * 60);
      expect(s.breakRemainingAt(s.breakStartedAt! + 46 * 60), -60);

      // Taking another kind while on the break changes it, and doesn't start another.
      final started = s.breakStartedAt;
      tasks.add(TakeBreakEvent(reason: 'Walk', plannedSeconds: 15 * 60));
      await Future<void>.delayed(Duration.zero);
      expect(tasks.state.breakReason, 'Walk');
      expect(tasks.state.breakStartedAt, started);
      expect(tasks.taskDocument!.pauseIds, hasLength(1));

      // Back to work ends it.
      tasks.add(ResumeTimerEvent(index: 0));
      await Future<void>.delayed(Duration.zero);
      expect(tasks.state.onBreak, isFalse);
      expect(tasks.state.breakReason, isNull);
      await tasks.close();
    });

    test('a break is edited: its reason, and a timer added, changed or taken away', () async {
      final tasks = await working();
      tasks.add(StopTimerEvent(index: 0));
      await Future<void>.delayed(Duration.zero);
      expect((tasks.state.breakReason, tasks.state.breakPlannedSeconds), (null, null));

      tasks.add(EditBreakEvent(reason: '  Doctor ', plannedSeconds: 30 * 60));
      await Future<void>.delayed(Duration.zero);
      expect((tasks.state.breakReason, tasks.state.breakPlannedSeconds), ('Doctor', 30 * 60));

      // Lengths are kept in range.
      tasks.add(EditBreakEvent(reason: 'Doctor', plannedSeconds: 10));
      await Future<void>.delayed(Duration.zero);
      expect(tasks.state.breakPlannedSeconds, minBreakMinutes * 60);

      tasks.add(EditBreakEvent(reason: '', plannedSeconds: null));
      await Future<void>.delayed(Duration.zero);
      expect((tasks.state.breakReason, tasks.state.breakPlannedSeconds), (null, null));

      // Editing with no break under way does nothing.
      tasks.add(ResumeTimerEvent(index: 0));
      tasks.add(EditBreakEvent(reason: 'Nap', plannedSeconds: 600));
      await Future<void>.delayed(Duration.zero);
      expect(tasks.state.onBreak, isFalse);
      expect(tasks.taskDocument!.currentPause, isNull);
      await tasks.close();
    });

    test('a planned break that runs out calls back to the task waiting', () async {
      final tasks = await working();
      final overs = <BreakOver>[];
      final sub = tasks.breakOver.listen(overs.add);
      tasks.add(StopTimerEvent(index: 0));
      await Future<void>.delayed(Duration.zero);
      // Started 59 seconds ago, planned for a minute: it runs out in a second.
      final doc = tasks.taskDocument!;
      doc.endPauses();
      doc.startPause('p', reason: 'Coffee', plannedSeconds: 60, at: nowSeconds() - 59);
      tasks.add(UpdateTimerEvent());
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      tasks.add(UpdateTimerEvent());
      await Future<void>.delayed(Duration.zero);
      expect(overs, hasLength(1));
      expect((overs.single.reason, overs.single.nextTask), ('Coffee', 'Write report'));
      // The break is not ended for the person: they say when they are back.
      expect(tasks.state.onBreak, isTrue);
      expect(tasks.state.breakRemainingAt(nowSeconds())!, lessThanOrEqualTo(0));

      // Only once.
      tasks.add(UpdateTimerEvent());
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(overs, hasLength(1));
      await sub.cancel();
      await tasks.close();
    });

    test('break types are kept in settings', () async {
      final tasks = TasksBloc();
      await tasks.document;
      expect(tasks.state.breakCategories, defaultBreakCategories);
      const mine = [BreakCategory(name: 'Nap', minutes: 20, icon: 'rest')];
      tasks.add(SetBreakCategoriesEvent(mine));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tasks.state.breakCategories, mine);
      await tasks.close();

      final again = TasksBloc();
      await again.document;
      await Future<void>.delayed(Duration.zero);
      expect(again.state.breakCategories, mine);
      await again.close();
    });
  });
}
