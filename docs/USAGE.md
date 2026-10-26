# Using bringmeback

bringmeback is a task list with a timer. You keep tasks in the order you will do them, and the task at
the top is the one you are working on.

## The task list

- **New task** (button at the bottom right, or Alt+N) adds a task on top and starts its timer.
- **Add task after this** (the list icon on a task, or Alt+Shift+N) adds a task right below the
  selected one. On a phone it is in the task's ⋮ menu.
- **Type the name** in the task's field. "What are you working on?" in light italics is only the
  placeholder: the task has no name yet. Names save as you type; Enter finishes editing.
- **Reorder** by dragging the handle on the left of a task. Dragging a task to the top makes it the
  current task.

## The top task and its timer

Only the top task is timed. It is the only one with a play/pause button, and its card is highlighted:
filled while it runs, grey while paused.

Each task shows two clocks:

- **Left 19:56** is the countdown. When it runs out it turns into **+02:10 over** in red, a sound plays
  and a "Time's up" message appears.
- **Total 00:42** is all the time worked on the task so far. "Paused" is shown next to it while work
  is paused.

Set the countdown length in the **Minutes** field (default 20). It applies when you press Enter or
leave the field. From the task's ⋮ menu you can **Restart countdown** or **Reset total time**.

While a task runs, a short reminder sound plays every 30 minutes. The speaker icon in the top bar mutes
all sounds.

## Pause and breaks

Press **Pause** on the top task when you step away. The time until you press **Resume** is logged as a
break, so the record shows the gaps between tasks too. Adding a new task on top also ends the break.

## Done and delete

- **Mark as done** (the check icon) takes the task off the list and keeps when you finished it. If work
  was running, the next task's timer starts right away.
- **Delete task** is in the ⋮ menu. Use it for tasks you added by mistake or no longer plan to do.

Both show a message at the bottom with **Undo**, which puts the task back where it was.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+N or Alt+N | New task on top, with its timer running |
| Ctrl+Shift+N or Alt+Shift+N | New task after the selected one |
| Ctrl+D or Alt+D | Delete the selected task |
| Enter | Finish editing a task name or timer |

Browsers keep Ctrl+N and Ctrl+D for themselves, so use the Alt variants in the web app. The keyboard
icon in the top bar shows this list.

## Where your data is

Everything is saved on the device you use, in the browser's storage for the web app. Nothing is sent
anywhere. Sync between your devices is planned and will be opt-in (see [ROADMAP.md](ROADMAP.md)).
