# Design note: protected relax time

Status: proposal, no code yet. Asked for by J: "make sure that relax / hobby / disconnect time is
assured per day and have some time scheduled on the routine", tied to the routine reminders (#47) and
acting as a schedule that task time bounces around.

## The idea in one paragraph

Each day has a **relax target** (60 min by default). Part of it is a **relax block** fixed on the
day's timeline, like a routine (30 min at 15:30 by default). The block is not task time: it is not
counted in what is committed, tasks are never planned into it, and the note's "done by" jumps over
it. The rest of the target floats and is taken as any break of a kind that counts as relax. What was
not taken by the afternoon wrap-up is said plainly, once. Nothing is scored and there are no streaks
(ROADMAP: not planned).

## What it builds on

| Piece | Where | Used for |
| --- | --- | --- |
| Routine reminders, per device, 09:00 / 17:00 | PR #47 | The notification that opens the block, and the wrap-up line that reports relax still owed. |
| Windows (start + length, weekdays) | `docs/ORGANISE.md` (#56) | The block is one more window, of a kind that is protected. |
| Break kinds, planned length, "is over" call, overrun | PR #52 | A relax block runs as a break of kind Relax, with its planned length and its line on top of the note. |
| Interruption flag | PR #54 | Decides what happens when something lands inside the block. |
| Committed time and "done by ~14:45" | #35 (main) | The block is left out of committed time and is skipped by "done by". |

## How it behaves

### 1. Setting it up

**Settings → Relax**, next to Reminders:

- **Relax a day**: 0 (off) to 3 h in 15-minute steps. Default **60 min**.
- **Relax block**: a start time and a length, on chosen weekdays. Default **15:30 for 30 min, Mon to
  Fri**. More than one block is allowed (for example a walk at 12:30 and the 15:30 one); their
  lengths count toward the daily target.
- In **Settings → Breaks** (#52) each break kind gets a switch **Counts as relax**. On by default for
  new kinds Relax, Hobby and Disconnect, and for Walk; off for Coffee, Stretch, Errand and Lunch.
  Lunch is food, not rest you chose, so it does not use up the target.

### 2. On the note: the block is a line in the plan

The note already knows roughly when each task will finish (the "done by" sum). The block is drawn as
a quiet line **where the plan reaches its start time**, for example between the third and fourth
task: "☕ Relax · 15:30–16:00". It cannot be ticked, dragged or deleted from the note (only moved in
Settings, or skipped for today from its menu, which says what that costs: "Skip today's relax? 30 min
stays owed.").

**Task time bounces around it.** A task whose time would run into the block is not split: the line
sits after the task that would be running at 15:30, and everything below it moves 30 min later.
"Done by" adds every block still ahead today. When the block is over, its line goes.

### 3. Committed time and the over-commit warning

- **Committed** stays the sum of task time only. Relax is not task time, so it never shows there.
- **Time per note** (8 h default) stays a cap on task time. The block does not shrink it.
- A second, new reason for red: **the day no longer fits**. When "done by" (with the blocks added)
  lands after the afternoon wrap-up time from #47 (17:00 default), the line reads "done by ~17:45,
  past your wrap-up at 17:00". This is the honest form of "tasks should not be scheduled into relax
  time": the plan has to give, not the block.
- The task limit prompt (#45) does not change.

### 4. When the block starts

- **App in front:** a banner on top of the note, in the break line's place: "Relax time · 30 min ·
  back at 16:00" with **Start now** and **In 10 min**. **Start now** pauses the current task exactly
  as a chosen break does (#52): kind Relax, 30 min planned.
- **App in the background or closed:** a system notification at 15:30 (the #47 machinery, one more
  reminder id range), "Relax time: 30 min. Step away." Tapping it opens the app with the banner.
- **In 10 min** can be pressed twice. After that the banner stays until it is started or skipped, but
  does not ring again.
- The clock never pauses on its own: a task is only stopped by the person (PRINCIPLES: the record
  stays honest, and someone mid-sentence needs a few seconds).
- **When the block ends:** the #52 "is over" call: sound, "Relax is over. Back to *task*", and the
  task clock starts only when they come back.

### 5. When an interruption lands inside it

PRINCIPLES rule 4 says an interruption goes on top and takes the clock. Relax is the one place where
it should cost a moment's thought first, otherwise the block is never protected.

- Pressing **Interruption** during a relax break asks once: "You're on relax (18 min left). **Handle it
  now** or **After relax**?"
- **Handle it now**: the relax break is put on hold, the interruption goes on top and is timed as
  usual (task time, flagged). When it is checked off the app comes back to the relax line with the
  minutes that were left ("Back to relax · 18 min"), not to the task from before.
- **After relax**: the interruption is written on top, flagged, but its clock waits until relax ends
  or is ended early.
- Minutes lost to a hold that runs past the end of the block plus 30 min are not lost: they go back
  into the day's floating relax.
- An interruption written in the 10 minutes before the block (or running when it opens) makes the
  banner wait: "Relax after this interruption". This mirrors the organise spike.

### 6. The day's relax, and what is still owed

- Relax taken = the minutes of every break today whose kind counts as relax, including the block.
- The afternoon reminder (#47) and the note header say what is left, once, as a fact: "Relax today:
  35 of 60 min". If the reminder fires with relax still owed, its text adds "25 min of relax still
  open today".
- Owed minutes do **not** carry to tomorrow. A day's rest isn't saved up, and a growing debt would
  become a score.
- History shows relax per day beside work and breaks: "Work 6 h 10 · breaks 55 min, relax 40 of 60".

### 7. Stored where

- **Settings** (target, blocks, which kinds count): recommended **synced** with the task document,
  unlike #47's per-device reminder times. The block changes the plan and "done by", which every
  device shows, so two devices must agree on it. Whether a device *rings* for it stays per device,
  as in #47.
- **Records**: a relax block runs as a break, so it already syncs (`<pauseId>/reason`,
  `<pauseId>/plannedSeconds` from #52). One new field, `<pauseId>/routine = relax`, says it was the
  scheduled block and not a break chosen on the spot. A hold adds `<pauseId>/heldAt` and
  `<pauseId>/heldSeconds`. Older versions ignore them and see a plain break.

## Recommendation

Ship it in three small slices after #47 and #52 land:

1. **Relax target and Counts as relax.** Settings, the header line "Relax today: 35 of 60 min",
   History. No scheduling yet. Already answers "is it assured".
2. **The relax block.** Window settings, the line on the note, "done by" skipping it, the banner and
   notification, the "past your wrap-up" red.
3. **Interruptions inside relax.** The Handle now / After relax question and the hold.

Defaults: **60 min a day, 30 min scheduled at 15:30, Mon to Fri, Walk / Relax / Hobby / Disconnect
count, Lunch doesn't.** 15:30 is the afternoon dip, inside the hours the app is open so the block can
actually be protected; a block after work would be outside the app's reach.

## Questions for J

1. **Defaults.** 60 min a day with 30 min fixed at 15:30, weekdays only? Or the block as the reward
   at the end of the day, just before the 17:00 wrap-up?
2. **Weekends.** Off, or the same target with no fixed block?
3. **Synced or per device.** Relax settings synced (recommended), or per device like the reminders?
4. **Start.** Banner with Start now / In 10 min (recommended), or pause the task automatically at
   15:30?
5. **Interruptions.** Ask "Handle it now / After relax" (recommended), or keep rule 4 as is and let an
   interruption always take over?
6. **Does Lunch count?** Recommended no.
7. **"Following rewards time".** Read here as relax being the reward that follows work. If you meant
   a specific earlier idea (for example relax earned per task finished), say so and the note changes.
