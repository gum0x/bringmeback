# Principles and goals

bringmeback exists to answer two questions at a glance: **what am I doing now, and what comes next?**
As a side effect it keeps an honest record of where the time went, without asking you to keep one.

## Goals

1. **Get back on track fast.** After an interruption, one look at the top of the list tells you what
   you were doing and how long you have been at it.
2. **Plan by ordering.** The list is the plan. Its order is the order you will work in.
3. **Record time for free.** Every minute is attributed to a task or a break by the normal act of using
   the list, so history and metrics need no extra input.
4. **Stay private.** Your data lives on your devices. Sharing and sync are opt-in and end-to-end
   encrypted.

## Principles

These are the rules a change has to respect. When two of them pull in different directions, the
earlier one wins.

1. **The top task is the current task.** Only the top task's timer runs. Done, delete and reorder hand
   the running timer to whatever becomes the top, and a paused state stays paused.
2. **No bookkeeping.** Never ask the user to log, tag or categorise time to get value. Pausing logs a
   break; done keeps when it finished; history is computed from those.
3. **Nothing is lost.** Every action that takes something away can be undone, and the document keeps
   history even after a task leaves the list.
4. **One step for the common things.** New task, pause/resume and done are each one tap or one key.
   Everything else may live one level down, in the task's menu.
5. **Calm, not nagging.** Alerts tell you something useful (time's up, a long stretch) and can be
   muted. No streaks, scores or guilt.
6. **Phone and desktop are equal.** Every screen works at 380 px wide and with a keyboard. Browser
   shortcut clashes get an Alt variant.
7. **Say it in plain words.** Clocks carry labels ("Left", "Total", "over"), buttons have tooltips,
   placeholders never look like real content.
8. **Few views, one home.** The task list is home. Any other view is one step away and one step back,
   and must earn its place by answering a question the list cannot.
9. **Local first.** The app works fully offline with no account. Anything that leaves the device is
   encrypted and optional.

## The usability path

The path a new user follows. Every change should keep each step obvious and short; if a change adds a
step or a decision here, it needs a strong reason.

1. Open the app. The empty state says what to do: add a task.
2. Press **New task** (or Alt+N). A task appears on top and its timer starts. Type its name.
3. Add the next few tasks below it, in the order you will do them.
4. Step away: press **Pause**. The break is logged. Press **Resume** when back.
5. Finish: press **Done**. The task leaves the list and the next one starts timing.
6. Made a mistake? **Undo** in the message at the bottom.
7. At the end of the day, look at what you did and where the time went (History, see
   [VIEWS.md](VIEWS.md)).

## Checklist for a change

- Does the top of the list still say what is happening now?
- Can the change be undone, or does it lose nothing?
- Does it add a tap, a field or a question to the usability path?
- Does it work at phone width and from the keyboard?
- Does it keep data on the device unless the user opted in?
