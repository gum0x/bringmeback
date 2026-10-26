# Views and navigation plan

A plan for the screens the app will need, so the size of the interface can be judged before any of it is
built. Nothing here exists in the app yet except **Now**, which is today's task list.

## Summary

Three main views, plus two things in the top bar and one switcher. That is the whole app.

| Where | What | Answers |
| --- | --- | --- |
| Main view | **Now** (task list, home) | What am I doing, what's next? |
| Main view | **History** (log and metrics) | What did I do, where did the time go? |
| Main view | **Notes** | What did I want to remember? |
| Top bar | **Alerts** (bell) | What has fired, what is coming up? |
| Top bar | **Settings** (gear) | How should the app behave? |
| Title | **Log switcher** (Work, Personal, …) | Which list am I looking at, and who shares it? |

Why logs are a switcher and not a view: a log scopes everything else. Now, History, Notes and Alerts
all show the selected log, the way a mail app's account switcher scopes the inbox. Making logs a fourth
destination would mean picking a log in one place and looking at it in another.

## Navigation

```
Phone (< 600 px)                          Desktop (>= 600 px)
┌────────────────────────────┐            ┌──────┬──────────────────────────────────┐
│ Work ▾          🔔  ⚙  ⋮   │            │      │ Work ▾                🔔  ⚙  ⌨  🔊 │
├────────────────────────────┤            │ Now  ├──────────────────────────────────┤
│                            │            │      │                                  │
│      (selected view)       │            │ Hist │        (selected view)           │
│                            │            │      │                                  │
│                  [+ New]   │            │ Notes│                        [+ New]   │
├────────────────────────────┤            │      │                                  │
│  Now    History    Notes   │            └──────┴──────────────────────────────────┘
└────────────────────────────┘
```

- Phone: a bottom `NavigationBar` with three destinations. Mute and keyboard shortcuts move into the
  ⋮ menu to leave room for the bell and gear.
- Desktop and wide web: a `NavigationRail` on the left with the same three destinations.
- Alerts and Settings open as full pages on a phone and as side sheets on desktop, with a back arrow.
  They are not destinations, because you visit them rarely and always return to where you were.
- Now stays the start screen. The bottom bar never hides the top task.
- Keyboard: Alt+1/2/3 switch views (to confirm when built, against browser clashes).

## Now (exists)

Today's task list, unchanged. Later additions that belong here, not in a new view:

- A small note icon on a task that has notes (opens the note in Notes).
- A "today" line under the top bar: worked 3:40 · breaks 0:35 · done 6. Tapping it opens History.

## History and metrics

```
┌────────────────────────────┐
│ Work ▾          🔔  ⚙  ⋮   │
├────────────────────────────┤
│ ◀  Today, Mon 26 Oct   ▶   │   day picker; Week toggle
│ Worked 3:40  Breaks 0:35   │   summary
│ ▇▇▇▇▁▇▇▇▇▇▁▁▇▇▇            │   timeline: work and breaks
├────────────────────────────┤
│ 09:02–09:48  Write docs ✓  │   one row per stretch of time,
│ 09:48–10:01  Break         │   newest first; done tasks ✓
│ 10:01–      Review PR      │
└────────────────────────────┘
```

- Built only from data the document already keeps: time entries, logged pauses, `doneAt`.
- Day view first, then week. Metrics kept small: time worked, breaks, tasks done, and per task the
  countdown set versus time actually spent.
- A done task can be brought back to the list from here (the long-term version of Undo).
- No goals, scores or streaks (principle 5).

## Notes

- A plain list of notes for the selected log, newest first, each with a title line and free text.
- A note can be linked to a task. The task's ⋮ menu gets "Add note", and the note shows the task name.
- Notes sync and share with their log.
- Kept deliberately simple: no folders, tags or rich text in the first version.

## Log switcher (work, personal, …)

```
┌──────────────────────┐
│ ✓ Work      shared 2 │
│   Personal           │
│ ──────────────────── │
│   New log…           │
│   Share Work…        │
└──────────────────────┘
```

- Each log is its own document with its own tasks, history, notes and alerts, so each can be shared on
  its own: share Work with a colleague's device without exposing Personal.
- Fits the sync plan: one CRDT document and one pairing secret per log (today the only document is
  `tasks`, which becomes the first log).
- One current task across all logs (monotasking, principle 1): two logs never run timers at once.
  Switching log while working asks nothing; the running task stays running and the top bar shows it.
- A task can be moved to another log from its ⋮ menu.

## Alerts

- The bell opens a list: alerts that fired (time's up, 30-minute reminders) and the next ones due.
- Background alerts on phones need scheduled local notifications computed from the countdown; the same
  mechanism the sync plan needs for alerts on another device.
- Per-alert settings live in Settings, not here. The bell is for "what happened", not configuration.

## Settings

One scrolling page, grouped:

- **Timer:** default countdown length (now fixed at 20 min), reminder interval (now fixed at 30 min).
- **Sounds and alerts:** mute, which sounds, notifications on/off.
- **Appearance:** theme (system, light, dark).
- **Logs and devices:** logs, paired devices, sharing (when sync lands).
- **Data:** export and import, about, help (links to the usage guide).

## Count

Three main views, two secondary pages, one switcher. If a future feature does not fit one of these, it
should first try to be a part of one of them before it becomes a new view.
