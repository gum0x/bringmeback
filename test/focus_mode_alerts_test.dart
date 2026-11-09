import 'package:bringmeback/bloc/tasks_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The task's own countdown goes quiet while the task is open in the Pomodoro focus view, and
/// alerts as before everywhere else.
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

  /// A running task with a one-second countdown, then the names reported as time's up over the
  /// next two seconds.
  Future<List<String>> timeUpWith({required bool inFocus}) async {
    final tasks = TasksBloc();
    await tasks.document;
    // Muted, so no sound is played: tests have no audio files to play it from.
    tasks.add(ToggleMuteEvent());
    final timeUp = <String>[];
    final sub = tasks.timeUp.listen(timeUp.add);
    const id = ValueKey('task');
    tasks.add(AddTaskOnTopEvent(name: '', id: id));
    tasks.add(UpdateTaskTimerEvent(index: 0, seconds: 1));
    if (inFocus) tasks.add(SetFocusModeEvent(taskId: id.value));
    tasks.add(UpdateTimerEvent());
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    tasks.add(UpdateTimerEvent());
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await tasks.close();
    return timeUp;
  }

  test('time is up outside focus mode', () async {
    expect(await timeUpWith(inFocus: false), hasLength(1));
  });

  test('time is not up for the task open in focus mode', () async {
    expect(await timeUpWith(inFocus: true), isEmpty);
  });
}
