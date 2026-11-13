# Using bringmeback

bringmeback is a task list with a timer, written like a sticky note: a short numbered list for today,
in the order you will do it. The first task not yet checked off is the one you are working on.

## Today's note

The app is laid out in portrait, like a phone, and keeps that shape in a wide desktop window.

- **Write a task** with **Add a task** on the next empty line of the note, or with the small **(+)**
  tabs on the top and bottom edges of a task. They show when you point at a task, or after you tap it
  to select it. A dialog asks for the name, optional **Details** (longer text over several lines) and
  the countdown length; Enter in the name saves.
- **New task** (at the end of the bottom bar, or Alt+N) writes a task on top, as an interruption: it
  takes the timer, and the task you were on waits one line below.
- **Every task shows its time**: the one waiting shows how long it is expected to take, or the time
  left if you already worked on it; the current one counts down, then shows how far over it is.
- **Check a task off** with its checkbox. It stays on the note, struck through, with the time it was
  done. Uncheck it if you checked it by mistake. When every task is checked off, the note gets an
  "All done" stamp.
- **Select a task** by tapping it. The bottom bar then acts on it: **Focus with Pomodoro**, **Restart
  countdown**, and the ⋮ menu with **Edit task**, **Reset total time** and **Delete task**. With no task
  selected it acts on the current one. Play/pause on the left of the bar always acts on the current
  task.
- **Edit a task** with a double tap or double click on it.
- **Reorder** by dragging the handle on the right of a task. Dragging an unchecked task above the
  current one makes it the current task.
- **The note is small on purpose**: it holds 10 tasks, done ones included. When it is full, finish
  or delete something, or start a fresh note. Change the size in **Settings** (the gear in the top
  bar), from 3 to 20 tasks. Making it smaller keeps what is already written.

## A new day

A note belongs to the day it was started (a day starts at 4:00). The next day the app asks you to
**tear off** yesterday's note: swipe it away or press **Tear it off**. Tasks you didn't finish wait
above today's note. Press **Write again** on the ones that still matter, in the order you will do them,
and **Let go** of the rest. Rewriting them by hand, one by one, is the point: it makes you choose again
instead of letting the list grow.

You can also tear off a note during the day from the note's ⋯ menu, with **Tear off and start a fresh
note**.

## History

The clock icon in the top bar opens History. **Notes** shows each note as it was written, newest
first: struck-through tasks with the time they were done, tasks written again on a later note, and
tasks let go. **Tasks** lists every task by day, with what became of it, when it was done and how
long you worked on it.

## The current task and its timer

Only the current task is timed. It is highlighted and is the only one with clocks. Pause and resume
it with the button on the left of the bottom bar.

- **Left 19:56** is the countdown. When it runs out it turns into **+02:10 over** in red, a sound plays
  and a "Time's up" message appears.
- **Total 00:42** is all the time worked on the task so far. "Paused" is shown next to it while work
  is paused.

Set the countdown length in the task dialog (default 20 minutes). The bottom bar has **Restart
countdown**, and its ⋮ menu **Reset total time**.

While a task runs, a short reminder sound plays every 30 minutes. The speaker icon in the top bar mutes
all sounds.

## Interruptions

An interruption is a new task. Press **New task** (Alt+N): it goes on top and is timed, and the task you
were on pauses one line below. When the interruption is done, check it off and the task it interrupted
takes over again.

## Focus with Pomodoro

Select a task and press **Focus with Pomodoro** in the bottom bar to work on it in Pomodoro sessions. The task moves to
the top, so it is the current one, and a focus view opens with a large clock, the task's name and,
below or beside it, the rest of the list in a quiet **Up next**.

- The first focus session starts as soon as the view opens, 25 minutes by default. **Pause** (or
  Space) stops the clock and **Resume** carries on. When a session ends a sound plays and a short
  break starts on its own; after every fourth session the break is a long one.
- The task's own timer runs during focus sessions and pauses during breaks or when you pause the clock,
  so the breaks are logged like any other pause.
- While the focus view is open, the task's own countdown stays quiet: no "Time's up" and no
  reminder sound. The Pomodoro clock is the one that counts. Back on the list it alerts as before.
- **Skip** (⏭) ends the session or break now; **Restart** (↺) puts it back to its full length.
- **Mark task done** finishes the task and goes back to the list, with Undo.
- The lengths under the clock (or the settings icon at the top right) set the focus, short break
  and long break lengths and how many sessions come before a long break. They apply right away; leave
  **Use these lengths from now on** ticked to keep them on this device for the next focus.
- The back arrow (or Esc) goes back to the list. The Pomodoro clock stops there; the task's timer
  carries on as it was.

## Pause and breaks

Press **Pause** on the current task when you step away. The time until you press **Resume** is logged
as a break, so the record shows the gaps between tasks too. Adding a new task on top also ends the
break.

## Delete

**Delete task** is in the bottom bar's ⋮ menu, for the selected task. Use it for tasks you wrote by mistake; to finish a task, check it
off instead. A message at the bottom offers **Undo**, which puts the task back where it was.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+N or Alt+N | New task on top, with its timer running |
| Ctrl+Shift+N or Alt+Shift+N | New task after the selected one |
| Ctrl+Enter or Alt+Enter | Check off the selected task, or uncheck it |
| Ctrl+D or Alt+D | Delete the selected task |
| Enter | Save the task in the task dialog |

Browsers keep Ctrl+N and Ctrl+D for themselves, so use the Alt variants in the web app. The keyboard
icon in the top bar shows this list.

## Where your data is

Everything is saved on the device you use, in the browser's storage for the web app. Nothing is sent
anywhere. Sync between your devices is planned and will be opt-in (see [ROADMAP.md](ROADMAP.md)).
