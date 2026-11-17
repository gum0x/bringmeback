# Organising the note: design note (spike)

Status: proposal, nothing built. This note answers what an organisation ritual should look like in
bringmeback, the two open questions about it, and the smallest slice to build first. Decisions that
are J's to make are listed at the end.

## The user story

Working hours end at 18:00, Monday to Friday. From 17:30 to 17:45 (a slot the user schedules for
this note) the user reviews the tasks, checks off what is done, lets go of what no longer matters and
puts tomorrow's tasks in order. On the next working day at 09:30 the user reviews the list again,
updates it with what came in overnight and starts on the top task.

The goal is a habit: at least twice a day, stop and organise. The app's job is to make that moment
easy to start, cheap to postpone when something urgent comes up, and visible afterwards.

## What exists today, and what is in review

| Piece | Where | How the ritual uses it |
| --- | --- | --- |
| Tear-off of yesterday's note, **Write again** / **Let go** | main | The morning session already is this flow; it becomes step 1 of the morning ritual. |
| Pauses logged as hidden tasks (`<id>/kind = pause`) | main | The pattern for logging an organising session as its own kind of record. |
| Reorder: a task dragged above the current one becomes current and ends a break | main | The behaviour organisation mode switches off. |
| Morning and afternoon reminders, per device (09:00 / 17:00) | PR #47 | The notification that starts the ritual. It needs a payload that opens the app in organisation mode. |
| Background notifications for countdowns | PR #26 | Same plugin as #47; the two should share one notifier. |
| Interruption button and `<id>/interruption` flag | PR #54 | The signal that postpones a session. |
| Rewrite counter and "Your plan kept changing" at tear-off | PR #53 | Edits made while organising should not count as rewrites (see decisions). |
| Break kinds | PR #52 | Organising is **not** a break kind: it is work, logged as its own record. |

## Organisation mode

A mode of the note, entered on purpose and left on purpose.

**Entering.** From the reminder notification, from an in-app banner, from the standing "Organise"
task (see question 2), or from **Organise now** in the note's ⋯ menu.

**While it is on:**

- The running task's clock stops. The time is logged as an organising session, not as a break and not
  on any task. Nothing else is timed.
- The note shows an **Organising** line on top (the same place as the "On a break" line), with how long
  the session has lasted and the window it belongs to, e.g. "Organising · 6 min · evening, ends 17:45".
- **Reordering never starts a clock.** Dragging a task above the current one does not make it current
  and does not end anything. The order is only a plan until the session ends.
- Checking off, unchecking, editing, letting go, moving to the backlog and writing new tasks (at the end
  or in place) all work as usual. None of them starts a clock.
- The task limit prompt still applies: organising is the moment the 7-task limit is meant for.
- The ⋯ menu offers **Tear off and prepare tomorrow** in the evening session (see decision 3).

**Leaving.** **Done organising** on the Organising line. In the morning the top task starts, exactly as
when a break ends. In the evening nothing starts, and the session ends the working day (a pause is
logged until the next task starts, as tear-off does today). **Cancel** leaves without a snapshot; every
change made stays, because each one was already saved and can be undone one by one.

**One record per session.** A clean session writes a snapshot of the whole note, so History can show
the list as it was planned, not only as it ended:

```
organise/<sessionId>/startedAt     seconds
organise/<sessionId>/endedAt       seconds
organise/<sessionId>/window        'morning' | 'evening' | 'manual'
organise/<sessionId>/ids           task ids in order at the end, joined by commas (like note/<id>/ids)
organise/<sessionId>/postponed     how many times it was put off before it started
organise/current/startedAt         set while a session is open, so every device shows "Organising on …"
```

The reorders themselves still go into the CRDT one by one, as every drag does today. Batching them
would not make sync cleaner (another device would see the same end state either way) and would lose
Undo. The "full picture in the log" comes from the snapshot, not from holding back changes. History
can then diff two snapshots: "evening: 7 tasks planned, 2 let go; morning: 3 added, order changed".

This is the same shape as a torn-off note (`note/<id>/ids`), so History reads it with the code it has.

## Reminders

Build on PR #47 rather than a new system.

- **Windows instead of times.** Each reminder becomes a window with a start and a length (morning
  09:30 for 15 min, evening 17:30 for 15 min), on chosen weekdays (Mon to Fri by default).
- **App in the background or closed:** a system notification at the start of the window, "Time to
  organise: 15 min to close today and plan tomorrow". Tapping it opens the app in organisation mode
  (a notification payload, read at launch and on resume).
- **App open and in front:** no system notification. A banner slides onto the note instead, in the
  place of the Organising line: **Start organising** · **In 10 min**. On Android and iOS the scheduled
  notification for that window is cancelled when the banner shows, so the two never double up. On the
  web and desktop #47 already fires in-app, so only the banner is new.
- **Missed window:** if the app is opened during the window without tapping the notification, the
  banner is there. Once the window is over, it goes. A missed evening is picked up by the morning
  session; nothing nags.

## Postponing for an interruption

An interruption is the one thing that outranks the ritual (PRINCIPLES rule 4).

- **Before the session:** if an interruption (the #54 flag) is running when the window opens, or one is
  written in the 10 minutes before, the reminder waits. The banner reads "Organise after this
  interruption" and comes back when the interruption is checked off. Each wait adds 1 to `postponed`.
- **During the session:** pressing **Interruption** puts the session on hold. The interruption goes on
  top and takes the clock as usual. When it is checked off, the app comes back to the Organising line
  ("Back to organising"), not to the task that was current before.
- **Limit:** a session postponed past the end of its window plus 30 minutes is dropped for that window.
  An evening one hands over to the next morning, which then shows "Yesterday's evening was skipped".

## Question 1: should organisation go by note?

**Recommendation: a session organises one list, the windows belong to the list, and one sitting can
run more than one session back to back.**

- The priority order is per list. Work and Personal each say what comes next *in that list*, so
  ordering them together would mix two plans into one (VIEWS.md: a log scopes everything).
- Different lists want different times. Work wants 17:30 and 09:30 on weekdays; Personal may want one
  evening slot, every day, or none. So each list (log, or note block once several are on one screen)
  carries its own windows and its own snapshot.
- When two windows fall together, the session walks them in turn in one sitting: "Work (3 to review),
  then Personal (2)". One thing at a time, as everywhere else.
- Only one session is open at a time across all lists, matching "one current task across all logs".

Today there is one list, so the first slices don't need any of this. The only thing to get right now
is to put a list id in the session record (`organise/<sessionId>/list`, the default list for now) and
keep the window settings in a shape that can later hang off a list.

## Question 2: work that arrives after the window closed

In busy environments the evening plan is a draft: mail, chats and alerts arrive overnight and change
the day. Two options were on the table, pre-organisation (review inboxes first) and a standing
organisation task after the daily routines. **Recommendation: do both, as one thing. Make the morning
session a standing task on the note, and make its first step a short sweep of the inboxes.**

- **The morning organisation is a task.** When the new note starts (tear-off), the app writes
  "Organise the day" as a task, 15 minutes. It is on the plan, timed, and honest in History. The user
  can drag it below their routines ("Coffee", "Stand-up") so it runs when the inputs are in, which is
  what the 09:30 slot really means. Starting it (it reaches the top, or the user taps it) enters
  organisation mode, and **Done organising** checks it off.
- **The sweep is the first step of that session, not a separate mode.** Its Organising line starts with
  a checklist of the places the user says new work arrives: "Mail", "Team chat", "Alerts", set once in
  Settings. Each is ticked when looked at. The app never reads those sources: no service, nothing
  leaves the device (PRINCIPLES goal 5). The checklist only makes the sweep explicit and the same each
  day, which is what trains the habit.
- **What the sweep finds** goes on the note in its place in the order, or to the backlog. Anything that
  can't wait is an interruption, as at any other time of day.
- **During the day**, new work keeps arriving. **Organise now** in the ⋯ menu is always there for a
  quick re-plan; it writes a `manual` snapshot. A third scheduled window (say 13:30) is just another
  window in Settings, no new concept.

Why not a separate pre-organisation mode: it would be a second ritual to learn, its result would still
have to be ordered in the organisation session, and it would add a step to the usability path for
people whose work doesn't arrive by mail.

## Smallest slice to build first

**Slice 1: Organise now, by hand.** No notifications, one list.

1. **Organise now** in the note's ⋯ menu enters the mode.
2. The Organising line on top, with **Done organising** and **Cancel**.
3. While on: the clock is stopped and logged as an organising record; reorders and new tasks start no
   clock.
4. **Done** writes the snapshot; the top task starts (or nothing, if the user chooses "end of day").
5. History › Notes shows the session as a line on the day: "Organised 17:31 to 17:42, 7 tasks".
6. Tests: reorder above the current task in the mode doesn't switch it; snapshot syncs; Undo works.

It is useful on its own (J can practise the ritual by hand from day one), touches only the bloc, the
document and the note view, and every later slice builds on it.

**Then:**

2. **Windows and reminders**, on top of #47: weekday windows, notification payload opens the mode,
   in-app banner when the app is in front, "In 10 min".
3. **Interruptions postpone**, once #54 is in: wait before, hold during, the 30-minute limit.
4. **The standing morning task and the sweep checklist.**
5. **Per list**, when multiple logs or note blocks land.

## Needs J's decision

1. **Do edits while organising count as rewrites (#53)?** Recommended: no. Replanning is the point of
   the session; the counter is about plans that keep changing during the work.
2. **How is the habit trained without streaks or scores** (ROADMAP "Not planned")? Recommended: only
   facts, in History: "Organised 9:32 (12 min) · 17:34 (9 min)", and a quiet "evening skipped" when
   it was. No counters of days in a row.
3. **Where does tear-off happen?** Recommended: keep it in the morning, as today, so carried tasks are
   still written again by hand. The evening session orders the note, and tomorrow's tear-off view lists
   the unfinished tasks in that order. The alternative, tearing off at 17:45, means the next day's
   note starts the evening before.
4. **Window settings: synced or per device?** #47 keeps reminders per device. Recommended: the windows
   (times, weekdays) sync with the list, because they are the person's working hours; whether a device
   notifies stays per device, so only the laptop rings at work.
5. **Is organising time work?** Recommended: yes, its own kind of record, counted in "worked" in
   History and not as a break.
6. **How close before a window does an interruption postpone it?** Proposed 10 minutes, and the
   session is dropped 30 minutes after its window ends.
