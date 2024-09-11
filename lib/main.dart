import 'package:flutter/material.dart';
import 'package:bringmeback/timer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/tasks_bloc.dart';
import 'dart:async';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
        create: (_) => TasksBloc()..add(LoadStateEvent()),
        child: MaterialApp(
          title: 'Flutter Stopwatch App',
          theme: ThemeData(primarySwatch: Colors.blue, fontFamily: "arial"),
          home: TasksStack(),
        ));
  }
}

class TasksStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tasksBloc = BlocProvider.of<TasksBloc>(context);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            AddNewTaskIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyD):
            RemoveCurrentTaskIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyN): AddNewTaskNextIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AddNewTaskIntent: CallbackAction<AddNewTaskIntent>(
            onInvoke: (AddNewTaskIntent intent) => _addNewTask(tasksBloc),
          ),
          RemoveCurrentTaskIntent: CallbackAction<RemoveCurrentTaskIntent>(
            onInvoke: (RemoveCurrentTaskIntent intent) =>
                _removeCurrentTask(tasksBloc),
          ),
          AddNewTaskNextIntent: CallbackAction<AddNewTaskNextIntent>(
            onInvoke: (AddNewTaskNextIntent intent) => _addNextTask(tasksBloc),
          )
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              Expanded(child:
                  BlocBuilder<TasksBloc, TasksState>(builder: (context, state) {
                return ReorderableListView.builder(
                  itemCount: state.tasks.length,
                  itemBuilder: (context, index) {
                    final task = state.tasks[index];
                    return Task(key: task.id, task: task, index: index);
                  },
                  onReorder: (int oldIndex, int newIndex) {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    tasksBloc.add(
                        MoveTaskEvent(fromIndex: oldIndex, toIndex: newIndex));
                  },
                );
              })),
              Container(
                padding: EdgeInsets.all(16),
                child: ElevatedButton(
                    onPressed: () {
                      final taskId =
                          DateTime.now().millisecondsSinceEpoch.toString();
                      tasksBloc.add(AddTaskOnTopEvent(
                        name: "",
                        id: ValueKey<String>(taskId),
                      ));
                    },
                    child: Icon(Icons.add)),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _addNewTask(TasksBloc taskBloc) {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    taskBloc.add(AddTaskOnTopEvent(
      name: "",
      id: ValueKey<String>(taskId),
    ));
  }

  void _removeCurrentTask(TasksBloc tasksBloc) {
    tasksBloc.add(RemoveTaskEvent(index: 0));
  }

  void _addNextTask(TasksBloc tasksBloc) {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    tasksBloc.add(
        AddNextTaskEvent(id: ValueKey<String>(taskId), name: "", index: 0));
  }
}

class Task extends StatefulWidget {
  final TaskState task;
  final int index;

  const Task({
    Key? key,
    required this.task,
    required this.index,
  }) : super(key: key);

  @override
  _TaskState createState() => _TaskState();
}

class _TaskState extends State<Task> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _debounce;
  late TextEditingController _stopWatchController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.name);
    _focusNode = FocusNode();
    _stopWatchController =
        TextEditingController(text: intToMinutes(widget.task.taskTimerSeconds));

    if (widget.task.inFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _stopWatchController.dispose();
    super.dispose();
  }

  Widget _buildTextField(
      String value, String label, Function(String) onChanged) {
    return Container(
      width: 80,
      child: TextField(
          controller: _stopWatchController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(),
          ),
          onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksBloc = context.read<TasksBloc>();

    return ReorderableDragStartListener(
      index: widget.index,
      child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: widget.task.inFocus
                  ? Border.all(color: Colors.red, width: 2)
                  : Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(8),
              color: widget.index == 0 ? Colors.green[300] : Colors.white,
            ),
            child: Row(
              children: [
                Expanded(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: TextStyle(fontSize: 18, color: Colors.black),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: "Task description here",
                          fillColor: Colors.white60,
                        ),
                        onChanged: (value) {
                          if (_debounce?.isActive ?? false) _debounce?.cancel();
                          _debounce =
                              Timer(const Duration(milliseconds: 500), () {
                            tasksBloc.add(UpdateTaskNameEvent(
                                index: widget.index, newName: value));
                          });
                        }),
                    const SizedBox(
                      height: 8,
                    ),
                    TaskWidget(
                      seconds: widget.task.taskTimerSeconds,
                      fontSize: 18,
                    ),
                    TaskWidget(
                      seconds: widget.task.totalTaskTimerSeconds,
                      fontSize: 12,
                    )
                  ],
                )),
                _buildTextField(
                  intToMinutes(widget.task.taskTimerSeconds),
                  'min',
                  (value) {
                    tasksBloc.add(UpdateTaskTimerEvent(
                        index: widget.index, seconds: int.parse(value) * 60));
                  },
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    FloatingActionButton(
                        onPressed: () =>
                            tasksBloc.add(RemoveTaskEvent(index: widget.index)),
                        child: Icon(Icons.delete)),
                    FloatingActionButton(
                        onPressed: () {
                          final taskId =
                              DateTime.now().millisecondsSinceEpoch.toString();
                          tasksBloc.add(AddNextTaskEvent(
                              index: widget.index,
                              name: "",
                              id: ValueKey<String>(taskId)));
                        },
                        child: Icon(Icons.add)),
                  ],
                )
              ],
            ),
          )),
    );
  }
}

class TaskWidget extends StatelessWidget {
  final int seconds;
  final double fontSize;
  final bool isEditable;

  TaskWidget({
    required this.seconds,
    required this.fontSize,
    this.isEditable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 25),
        Text(intToHours(seconds), style: TextStyle(fontSize: fontSize)),
        const SizedBox(width: 5),
        Text(":", style: TextStyle(fontSize: fontSize)),
        const SizedBox(width: 5),
        Text(intToMinutes(seconds), style: TextStyle(fontSize: fontSize)),
        const SizedBox(width: 5),
        Text(":", style: TextStyle(fontSize: fontSize)),
        const SizedBox(width: 5),
        Text(intToSeconds(seconds), style: TextStyle(fontSize: fontSize)),
      ],
    );
  }
}

class AddNewTaskIntent extends Intent {}

class RemoveCurrentTaskIntent extends Intent {}

class AddNewTaskNextIntent extends Intent {}
