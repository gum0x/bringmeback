# Goals and usability rules

bringmeback exists to answer two questions at a glance: **what am I doing now, and what comes next?**
It is built for monotasking: one thing at a time, in priority order. As a side effect it keeps an honest
record of where the time went, without asking you to keep one.

## Goals

1. **Do one thing at a time.** Multitasking is not optimal and not really possible. The app keeps a
   single current task and steers away from anything that looks like juggling several.
2. **Get back on track fast.** After an interruption, one look at the top of the list tells you what
   you were doing and how long you have been at it.
3. **Stay out of the way.** Managing tasks, above all adding and finishing them, is so quick that the
   app never becomes a distraction itself.
4. **Carry your tasks everywhere.** Tasks and ideas are not tied to work, home or one device. They move
   with you between your phone, laptop and desktop.
5. **Stay private.** No service behind the app: your data lives only on your devices, synced directly
   between them.

## Usability rules

1. **Tasks are always in priority order.** The list says what is going to be done next. Its order is
   the plan.
2. **One thing at a time.** The first task is the one being worked on, and the only one being counted.
3. **An interruption is a new task on top.** It takes the focus and its timer, and the task you were on
   pauses one place below, ready to resume when the interruption is done.

## The usability path

The path a new user follows. Every change should keep each step obvious and short; if a change adds a
step or a decision here, it needs a strong reason.

1. Open the app. The empty state says what to do: add a task.
2. Press **New task** (or Alt+N). A task appears on top and its timer starts. Type its name.
3. Add the next few tasks below it, in priority order: what you will do next comes next.
4. Interrupted? Press **New task** again. The interruption goes on top and is timed; the task you were
   on pauses just below it.
5. Step away: press **Pause**. The break is logged. Press **Resume** when back.
6. Finish: press **Done**. The task leaves the list and the next one, often the task the interruption
   paused, starts timing.
7. Made a mistake? **Undo** in the message at the bottom.
8. Pick up another device later. The same list is there, in the same state.
9. At the end of the day, look at what you did and where the time went (History, see
   [VIEWS.md](VIEWS.md)).

## Checklist for a change

- Does the top of the list still say what is happening now, and is only one thing running?
- Are adding and finishing a task still one step each?
- Can the change be undone, or does it lose nothing?
- Does it add a tap, a field or a question to the usability path?
- Does it work at phone width and from the keyboard, and on every platform?
- Does it work offline, with no server, and keep data on your own devices?
