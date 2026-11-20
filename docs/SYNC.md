# How sync behaves

This page describes what happens when devices of a sync group get out of sync and then sync again.
Every case here is covered by `test/sync_conflicts_test.dart`.

## The basics

The task list is a CRDT document (crdt_lf). Each edit is a *change* with a unique id and a hybrid
logical clock time. Each device keeps a *version vector*: for every device that ever wrote, the
latest change it has from it.

When two devices connect, each sends its vector, and the other answers with exactly the changes the
vector doesn't cover. After that, every edit goes to every connected device as it happens. A device
that gets a vector with changes it lacks answers with its own vector, so a comparison started on
either side fills in both.

Two properties make syncing again always safe:

- **A change is applied once.** A change that arrives twice (or ten times) is recognised by its id and
  ignored the second time. Sending more than needed never duplicates a task.
- **Every device ends with the same result.** When two devices wrote the same field while apart, the
  write with the later clock wins on both (ties are broken by device id). It doesn't matter which
  device syncs first or how often.

## Automatic sync

With **Find my devices online** on, devices that are both open sync without anyone pressing anything:

- They find each other through the Nostr relays and connect directly. Every edit is sent at once.
- Every 30 seconds, connected devices compare their vectors again, so anything that didn't make it
  across is sent again.
- A device announces itself ("I'm here", the only thing it publishes) on events, not on a timer:
  when a relay connects or reconnects (the app opens, comes back after 20 s or more hidden, wakes
  from sleep, its network comes back, or a dead relay socket is found), when it comes to the front
  while a device is missing, and on Sync now. It announces once more on the next round in case a
  relay dropped that one, and after a link drops. Then, only while a device is missing, it sends a
  safety announce every 10 minutes when no other device is online, or every 5 minutes while one is
  online but not connected. Devices answer each other's announces, once per device per round.
  Public relays rate-limit busy senders: on 2026-11-18 damus answered "rate-limited: you are noting
  too much" to a desktop that announced every 30 s while alone, and stopped passing its messages on.
- Waking from sleep: a round that runs more than three rounds late means the computer slept (timers
  don't run, relay sockets die without a close). The app reconnects to the relays at once, which
  announces it, instead of waiting for the relay check. A hidden app is handled when it comes back.
- Network back: the web app listens for the browser's `online` event (after a switch of Wi-Fi or to
  mobile data) and reconnects at once. A change of address that drops the direct link is handled by
  the link retry below, which goes through the relays.
- Reconnecting closes the old relay connections without waiting for them to finish: the close of
  a WebSocket that never opened never completes, and waiting for it once kept a desktop off the
  relays until it was reloaded (2026-11-20).
- The Devices page shows the step sync is at and a sync log (also printed to the console as
  `[bmb sync] …`) with relay connects, failures, drops, every event published and heard, links and
  uncaught errors. It holds no tasks, keys or group code.
- Every 30 seconds, each relay is asked to answer (the subscription is sent again, and a relay replies
  at once). A relay that answered nothing since the last round is connected again, which also
  announces the device on it. A relay socket can die without closing, after the computer sleeps or
  changes network; before this check, such a device still showed its relays as connected but heard
  and reached no one, so other devices saw "No other device online".
- A device that was seen online but isn't connected stops counting as online when nothing is heard
  from it for twelve rounds (6 minutes). One that is still there announces every 5 minutes while it
  isn't connected, so it stays listed. A phone sent to the background never says bye, and its old
  session used to keep the other device from announcing again.
- When the app comes back to the front, connected devices compare again; after 20 seconds or more
  hidden, it reconnects to the relays first.
- A link that drops is tried again after 5 s, then waiting twice as long each time, up to 5 minutes.
- A device passes on changes it got from another device. If A is connected to B and to C, but B and C
  can't connect to each other, B and C still get each other's changes through A.

## Sync now

The **Sync now** button (the circular arrows in the bottom bar, shown once the device is in a sync
group) does the automatic round at once:

| Situation | What Sync now does | Message |
| --- | --- | --- |
| Not in a group, or Find my devices online is off | Nothing is sent | "Sync is off on this device." with a link to Devices |
| Every online device is connected | They compare vectors and send what is missing | "Syncing with N devices" |
| An online device isn't connected | Connects to it at once, skipping the retry wait, and compares with the rest | "Connecting to N devices" |
| No other device online | Reconnects to the relays and announces this device again | "Looking for your other devices" |

## Two resyncs while out of sync, then in sync again

**Link up, messages delayed** (a congested network, a tab that is slow to read). Both devices edit,
then Sync now is pressed twice on each device while nothing gets through. When the messages arrive,
each device gets the other's edits, plus four vector comparisons. Each comparison is answered only
with the changes still missing, and changes that arrive more than once are applied once. The result
is the same as after a single sync: the same tasks on both, no task twice, the same number of
changes, and both report "in sync". Pressing Sync now again afterwards sends no new changes.

**Link down, both devices online.** Both devices edit while the direct link is down. Without Sync now,
the next try would come after the retry wait (5 s at first, up to 5 minutes). Two presses on each
device, at the same time, set up one new link (not one per press, and not one per device: only one of
the two devices ever makes the offer). Once connected, both exchange what the other lacks and are in
sync.

**Devices offline.** Sync now with no other device online only looks for them again; edits made
meanwhile stay on the device and are exchanged when the two next connect, as above.

## Closing the same task on two devices that are out of sync

Both devices have "First" (running) and "Second". While they are out of sync, each checks off "First",
a moment apart. On each device, checking off "First" stops its timer and starts "Second".

When they sync again:

- "First" is done once, on both devices, at the time of the **later** check-off. Its time entry is
  closed; its end is the later device's.
- Each device had opened its own time entry on "Second", so "Second" briefly has two running entries,
  which would count its time twice. The task list repairs this as soon as it merges the other device's
  changes: the **earliest** entry stays open, and the later one is closed where it starts, so it
  counts nothing. Both devices make the same repair, so their writes agree.
- No task is duplicated, and both devices show the same entries.

**One device checks off the task, the other writes a new task on top.** On A, checking off "First"
starts "Second". On B, a moment later, a new task "Urgent" goes on top and takes the timer. After the
merge "Urgent" is the current task and runs; "Second" ran on A from when "First" was checked off, and
its timer is closed at the moment "Urgent" started, since work moved on then. Only one task runs.

The rule behind both repairs: after a merge, only the current task (the first one not checked off)
may run, with one open time entry.

## Not handled yet

- When the current task isn't running after the merge (for example one device paused while the other
  started another task), a task below it that the other device started keeps its timer running.
  There is no moment to close it at that both devices would agree on.
- Messages are never lost inside a working link (the channel is reliable and ordered), so the
  30-second comparison mainly covers links that dropped, devices passing changes on for each other,
  and announces lost on the relays.

## Tearing off while out of sync

**One device tears off, the other keeps using yesterday's note.** Nothing is lost when they sync.
A task checked off on the old note counts as done on yesterday's torn-off note. A task written on
the old note after the tear-off lands on today's note. The unfinished tasks wait to be written again,
as usual.

**Both devices tear off the same note.** History keeps one note per note started: the two records
merge into one, with the tasks of both, closed at the earlier tear-off. When both devices wrote the
same unfinished task again, today's note would have it twice. After the merge, each device keeps
the copy the task's `carriedTo` names (the same one on both devices) and deletes the other, unless
that copy was checked off.
