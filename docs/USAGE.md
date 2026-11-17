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
- **The note stays short on purpose**: once it holds 7 tasks not done yet, writing another one asks
  first. **Write on note anyway** adds it as usual; **Let it go** drops it on purpose, because not
  everything has to be done (History keeps it as let go). Done tasks don't count. The note's header
  says when you are at or over the limit. Change the limit in **Settings** (the gear in the top bar),
  from 3 to 20 open tasks.
- **Backlog (experimental)**, off unless turned on under **Settings › Experimental**. The prompt then
  also offers **Save to backlog**, which keeps the task for later in a backlog under the note. Open it
  to **Write on note** a task (past the limit this asks first too) or let it go. Unfinished tasks of a
  torn-off note can also be moved there instead of written again. It is a trial and may change or
  move.
- **Committed time**: under the date, the note adds up the expected times of all its tasks, and says
  roughly when everything will be done if you work on without breaks, e.g. "Committed 3 h 20 min ·
  done by ~14:45". The finish is rounded up to the quarter hour, so it doesn't tick like another
  clock. A note holds 8 hours by default; when you commit more, the time turns red. Change it in
  **Settings → Time per note**.

## Categories

Each task is filed under one category, shown next to its name, so History can later tell where the
time went. The app comes with a list built from the life areas most task and time-use frameworks
share, with work split by the kind of work:

| Category | For tasks like |
| --- | --- |
| Work planning | read work emails, prepare tomorrow's work, weekly KPIs |
| Focused work | fix a bug, write the design doc |
| Meetings and calls | standup, call with the client |
| Personal projects | side projects and hobby builds |
| Learning | a course, a book chapter, a language lesson |
| Housekeeping | cleaning, laundry, cooking, repairs |
| Errands and shopping | groceries, orders, the post office |
| Money and paperwork | bills, taxes, insurance, forms |
| Self-care and workout | gym, a run, yoga, the dentist |
| Family and friends | call mom, a birthday, dinner with friends |
| Leisure | a movie, a trip, a concert |

Manage them in **Settings → Categories**: rename or change any of them, delete the ones you don't
use (**Restore default categories** brings them back), and add your own. Each category has:

- **Keywords**: words its tasks often use, which help tell categories apart.
- **Always for tasks that mention**: names or phrases, separated by commas. A task that mentions one
  goes there whatever else it says. Use it for names the app can't know: put `bringmeback` on
  Personal projects and "Fix the sync bug in bringmeback" goes there. When rules of two categories
  match, the longer phrase wins.

Changes to the list sync with your other devices, like the tasks.

While you write a task, the dialog suggests up to three categories for its name: tap one to file it
there yourself. If you leave it on **Automatic**, the app picks the category (✨ on the tag, meaning
you didn't choose it): a rule it mentions, or else the category that fits its name best. That runs entirely on the device, with no service behind
it: it compares the task's words with each category's name and keywords using word vectors bundled
with the app (English). When nothing fits well enough, the task gets no category rather than a wrong
one.

To confirm an automatic pick, tap the tag and choose **Keep**; to correct it, pick another category,
or **No category**; or pick one in the task dialog. Your choice stays, even when you rename the task, until you pick **Choose automatically**.
Tasks you filed by hand also teach the app: a new task much like one of them goes the same way.

### Categories in any language

The word vectors only know English. For tasks in other languages, turn on **Categories in any
language** in Settings. The app downloads a small multilingual model,
paraphrase-multilingual-MiniLM-L12-v2 (about 130 MB, once, on this device only; Apache 2.0), and runs
it on the device. It knows over 50 languages, Spanish, Portuguese, Chinese, Hindi and Arabic among
them. It doesn't write anything: it turns a task into a point in space where tasks that mean alike
sit close, whatever their language, and files it under the category whose sample tasks, keywords
and hand-filed tasks are closest. That takes about 10 ms a task. Nothing leaves the device. Rules
still decide first, then the English word vectors, then the model. Turning it off deletes the
download.

It needs iOS 16.4 or macOS 14 or later. In a browser it needs WebGPU and a page served with
cross-origin isolation (the Docker image does this; the GitHub Pages site can't, so there Settings
says it can't run).

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
- **Total 00:42** is all the time worked on the task so far. "Paused, not counting" is shown next to
  it while work is paused.

## Breaks

Pausing starts a break. While it lasts, an **On a break** line sits on top of the note with how long
the break has lasted and "No task clock is running", so it is clear that nothing is being counted.
The break ends, and the line goes away, when you:

- press play on the bottom bar, or **Back to work** on the break line;
- put another task first: a **New task** on top, a task written above the current one, or a task
  dragged above it. That task's clock starts.

Writing or moving tasks lower down the note doesn't end the break.

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
- **The sessions fit the task.** They are cut to the time the task has left: a task with an hour
  left gets sessions of 25, 25 and 10 minutes, and one with 20 minutes a single 20-minute session. A
  rest of 5 minutes or less joins the session before it. Under the clock the view shows the plan,
  e.g. "Fits the task's 1 h: 25 + 25 + 10 min of focus, 1 h 10 min with breaks". Once the task's
  time is used up, sessions go back to full length. A task already over its time gets full
  sessions.
- The task's own timer runs during focus sessions and pauses during breaks or when you pause the clock,
  so the breaks are logged like any other pause.
- While the focus view is open, the task's own countdown stays quiet: no "Time's up" and no
  reminder sound. The Pomodoro clock is the one that counts. Back on the list it alerts as before.
- **Skip** (⏭) ends the session or break now; **Restart** (↺) puts it back to its full length.
- **Mark task done** finishes the task and goes back to the list, with Undo.
- The lengths under the clock (or the settings icon at the top right) set the focus, short break
  and long break lengths and how many sessions come before a long break. They apply right away; leave
  **Use these lengths from now on** ticked to keep them on this device for the next focus. Under them
  the view shows what a full cycle adds up to, up to the end of the long break, and how much of it
  is focus. The defaults, with the same total, are also in **Settings**, under **Pomodoro**.
- The back arrow (or Esc) goes back to the list and pauses the Pomodoro; the task's timer carries
  on as it was.
- Each task remembers where its Pomodoro is: the phase, the time left, the sessions done and how far
  along the plan for the task's time it is (the focus already counted and the length of the current
  session). It is kept with the task, so it syncs to your other devices like the rest of the list.
  Focus on the task again, here or on another device, and it picks up there, on the same plan,
  instead of starting over and cutting a new one. A fresh plan is cut only when the Pomodoro starts
  fresh.
- If the app closes while the focus view is open (a crash, a closed tab, the phone ending the app),
  the next start opens the focus view again: a running clock carries on as if nothing happened, a
  paused one waits for **Resume**. If a phase ran out while nobody was looking, it waits at the
  start of the next one instead of running on, and a focus session that ran out counts in full
  towards the task's time.
- With the focus view open on two devices, pausing, skipping or changing the lengths on one shows on
  the other. A Pomodoro left alone for 12 hours, or one whose task was marked done, starts fresh.

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

## Sync between your devices

The devices icon in the top bar opens **Devices**. Start a group on one device and enter its code
on the other. With **Find my devices online** on, the devices find each other through public Nostr
relays (which only see encrypted messages) and then sync directly, while both are open and on the
same network. Sync starts with the app and reconnects when you come back to it. While two devices
are both open they keep syncing on their own: every edit goes across at once, and every 30 seconds
they check that nothing is missing.

- **Sync now** (the circular arrows in the bottom bar, once the device is in a group) syncs at once:
  it compares with the connected devices, connects again to online devices whose link dropped, or
  looks for the others again when none is online. Pressing it more than once does no harm.
- When devices that worked apart sync again, the later edit of the same thing wins on both, and a
  task is never duplicated. [SYNC.md](SYNC.md) describes the cases.

- **Start empty**, under the code box, deletes this device's tasks and history before it joins, so
  it only gets the group's tasks and sends none of its own. It asks before deleting.
- Devices sync only when they run the same sync version, shown under **This device**. When they
  don't, the Devices page says which one is older; reload the page (or update the app) there.
- When sync can't work, the Devices page says why: no relay reachable, no direct connection (not
  on the same network, or a browser setting that blocks WebRTC), another version, or a failed
  handshake.

## Where your data is

Everything is saved on the device you use, in the browser's storage for the web app. Nothing is sent
anywhere unless you turn on sync, which is opt-in and sends tasks only to your own paired devices.
