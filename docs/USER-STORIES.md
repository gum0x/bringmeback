# User stories: sync between devices

Each story says what a person does, what they should see, and the edge cases around it. Every
expected behaviour names the test that covers it (`file › test name`, in `test/`). A behaviour with
no test is listed under **Not covered yet** at the end of its section, never left out.

How to keep this file up to date is in [CLAUDE.md](../CLAUDE.md). [SYNC.md](SYNC.md) explains the
mechanics behind these stories.

Status: **covered** (a test checks it), **known limit** (by design, a test pins it down),
**gap** (wrong or untested today; say what would fix it).

---

## P · Pairing

**P1. I put my phone in the same group as my desktop.** I show the code (or QR) on one device and
enter it on the other. Both show the same group fingerprint.

| Case | Expected | Status |
| --- | --- | --- |
| P1.1 Code read on the other device | Same keys, same fingerprint | covered: `pairing_test › a code read on another device gives the same keys` |
| P1.2 Mistyped or garbled code | Refused with a message, nothing changes | covered: `pairing_test › bad codes are rejected` |
| P1.3 Join with **Start empty** | This device's tasks are deleted first, then it gets the group's | covered: `sync_problems_test › joining with a clean slate` |
| P1.4 Device from another group | Never heard, never connects | covered: `signalling_test › ignores other groups, junk, duplicates and old messages`, `peer_test › another group, another prologue or another device never connects`, `noise_test › a device from another group is rejected` |
| P1.5 I leave the group | The others see it go offline at once | covered: `sync_cubit_test › paired devices with live sync on see each other online, and not once one leaves` |

## D · Finding my other devices

**D1. I open the app on two devices and they find each other**, with **Find my devices online** on,
through the Nostr relays.

| Case | Expected | Status |
| --- | --- | --- |
| D1.1 Both open, sync on | Each lists the other as online, then connected | covered: `sync_cubit_test › paired devices with live sync on see each other online…` |
| D1.2 Sync off on a device | Nothing is sent to any relay | covered: same test |
| D1.3 Both missed each other's announce | Found on the next 30 s round | covered: `sync_conflicts_test › devices that missed each other's announce still find each other and sync` |
| D1.4 A device opens later than the other | The one already open answers its announce | covered: `signalling_test › devices of one group find each other and exchange offers` |

**D2. My desktop stays open for hours while my phone comes and goes.** (The bug of 2026-11-17: the
phone said "No other device online" while the desktop was open.)

| Case | Expected | Status |
| --- | --- | --- |
| D2.1 A relay socket dies without closing (sleep, network change) | Found within about a minute; the relay is reconnected and the device announces again | covered: `signalling_test › a relay that went silent without closing is connected again, and announces again`, `sync_cubit_test › a device whose relay socket died silently is found again…` |
| D2.2 The phone goes to the background without a bye | It stops counting as online after twelve rounds (about 6 minutes), and its "isn't syncing" warning goes with it; until then the desktop keeps announcing, backing off | covered: `sync_cubit_test › a device that left without a bye stops counting as online after a few rounds` |
| D2.3 The phone comes back after 20 s or more hidden | It reconnects to the relays at once | covered: `sync_problems_test › coming back after a long break reconnects at once` |
| D2.4 Back after less than 20 s | Only compares changes again, keeps its links | covered: same test |

**D3. A relay misbehaves.**

| Case | Expected | Status |
| --- | --- | --- |
| D3.1 One relay drops the connection | Reconnected with backoff (1 s, doubling, up to 1 min) and announces again | covered: `signalling_test › reconnects after the relay drops and announces again` |
| D3.2 No relay reachable | "Can't reach the relays" after 10 s | covered: `sync_problems_test › no relay reachable is reported after the grace period` |
| D3.3 A relay accepts the connection but refuses or drops our messages | The Devices page lists each relay: not connected, passes messages on, or not passing them on, plus the reason the relay gave, when this device's own messages last came back and when a message from another device last arrived through it | covered: `signalling_test › shows which relays pass messages on, and why one refuses them`, `signalling_test › notes when each relay last carried a message from another device` |
| D3.5 A relay's spam filter stops passing on a key's events to others after many of them (suspected on 2026-11-18: each device saw its own messages come back but not the other's) | Events are signed with a new throwaway key every 30 s round, so no key lasts long | covered: `signalling_test › signs with a new throwaway key on every relay check` (the relay behaviour itself is unconfirmed) |
| D3.6 A relay rate-limits us (2026-11-18: damus answered "rate-limited: you are noting too much" and stopped passing the desktop's messages on) | While no other device answers, announces back off: 30 s, 1, 2, 4, then every 5 min. Quick again on Sync now, coming to the front, a dropped link or reconnected relays | covered: `sync_cubit_test › announces back off while no device answers, and come quickly again after Sync now` (the relay's actual limits are unknown) |
| D3.4 A relay sends junk, duplicates or replays | Dropped without a reply | covered: `signalling_test › ignores other groups, junk, duplicates and old messages` |

**D5. My devices' clocks don't agree.**

| Case | Expected | Status |
| --- | --- | --- |
| D5.1 Up to 2 minutes apart, either way | Found as usual | covered: `sync_stories_test › D5.1 …`, `signalling_test › hears a device whose clock is a minute behind` |
| D5.2 More than 2 minutes apart | Not found: every signal is refused as too old or too far ahead | known limit: `sync_stories_test › D5.2 …` |

Not covered yet:
- D5.2 has no message on the Devices page. A gap: the app could compare its clock with the server's
  `Date` header and warn.
- Devices never open at the same time never find each other: relays don't store signals. A gap,
  tracked as a separate feature (sync through stored Nostr events).

## L · The direct link

| Case | Expected | Status |
| --- | --- | --- |
| L1 The link drops | The initiator tries again after 5 s, doubling up to 5 min | covered: `sync_cubit_test › online devices connect directly, and reconnect after the link drops` |
| L2 Only one device makes the offer | One link, never two crossed ones | covered: same test |
| L3 Other device on another sync version | Refused, and the message says which device to update | covered: `sync_problems_test › versions` |
| L4 A tampered or garbled message | The link closes, nothing changes | covered: `peer_test › a tampered message closes the link`, `doc_sync_test › a device that sends garbage loses its link and changes nothing` |
| L5 Safari delivers channel messages out of order | Put back in order | covered: `sync_problems_test › Reorder` |
| L6 No direct connection possible (different networks, WebRTC blocked) | "No direct connection within N seconds" | covered: `peer_test › a link that never opens gives up`, `sync_problems_test › a dropped link shows as a problem until it connects again` |
| L7 Two devices can't connect but both reach a third | Changes pass through the third | covered: `sync_conflicts_test › a change reaches a device through another one when the two can't connect` |

## C · My tasks after syncing

| Case | Expected | Status |
| --- | --- | --- |
| C1 Edits on both while apart | Both kept; the later write to the same field wins on both devices | covered: `doc_sync_test › connected devices exchange what the other is missing…`, `task_document_test › two devices converge after exchanging changes` |
| C2 Sync now pressed several times while nothing gets through | Applied once when it does, nothing duplicated | covered: `sync_conflicts_test › Two resyncs while the devices are out of sync` |
| C3 Sync now with sync off, or with nobody online | Nothing sent / looks again | covered: `sync_conflicts_test › Sync now with sync off does nothing, and with nobody online looks again` |
| C4 Same task checked off on both | Done once, at the later time; the next task has one timer running | covered: `sync_conflicts_test › Closing the same task on two linked devices that are out of sync` |
| C5 Checked off on one, new task on top on the other | Only the new task runs | covered: `sync_conflicts_test › one device checks it off, the other writes a new task on top…` |
| C6 Pomodoro on a task | Picks up where it was on the other device | covered: `focus_resume_test › syncs with the task to another device` |
| C7 A device writes fields of the wrong type | Read as defaults, nothing breaks | covered: `doc_sync_test › fields of the wrong type, which only a bad device could write, read as defaults` |

Not covered yet:
- The current task isn't running after a merge (one device paused, the other started a task below):
  the lower task keeps running. A gap, described in SYNC.md.

## T · Tearing off the note

**T1. I tear off yesterday's note on one device; my other devices should not ask me again.**

| Case | Expected | Status |
| --- | --- | --- |
| T1.1 Both devices connected | The other device's note clears at once; no "A new day" prompt | covered: `sync_stories_test › T1.1 …` |
| T1.2 Devices apart when I tear off | The other still shows the old note and asks to tear it off, until they sync; then it clears | covered: `sync_stories_test › T1.2 …` |
| T1.3 I keep using the old note on the other device meanwhile | Nothing is lost: check-offs count on yesterday's note, new tasks land on today's | covered: `task_document_test › a device that missed the tear-off keeps working on the old note…` |
| T1.4 I tear off on both devices while apart | One note in History, each task written again once | covered: `task_document_test › a note torn off on both devices while apart is kept once…` |
| T1.5 One device writes a task again, the other lets it go | Written again wins, on both | covered: `sync_stories_test › T1.5 …` |

Not covered yet:
- T1.4 when the copy to remove was already checked off: both copies stay. A gap; rare.
- No warning on the device that is out of sync before it shows "A new day". A gap: needs the
  stored version signal (see the Signal CRDT version over Nostr design).

## S · Security and privacy

| Case | Expected | Status |
| --- | --- | --- |
| S1 What relays see | Only sealed content under the topic, signed by a throwaway key | covered: `signalling_test › relays see only sealed content under the topic, signed by a throwaway key` |
| S2 Sealed payloads | Open only with the same key and context | covered: `pairing_test › sealed payloads open only with the same key and context` |
| S3 Replays older than 2 minutes | Dropped | covered: `signalling_test › ignores other groups, junk, duplicates and old messages` |
| S4 Oversized relay messages | Dropped before parsing | covered: same test (64 KiB limit in `Signalling`) |
