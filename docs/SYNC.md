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
- Every 30 seconds, a device that sees no other device announces itself again, and devices answer
  each other's announces again. Two devices that missed each other's announce (a relay dropped it, or
  one came online while the other's relay was reconnecting) still find each other.
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
