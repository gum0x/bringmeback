# Roadmap

Features in the order they are planned. Each step should ship on its own as one or a few small PRs and
keep the app usable. The order follows [PRINCIPLES.md](PRINCIPLES.md): the list stays home, and views
come in the order they answer the most useful question with data we already have. The views are
described in [VIEWS.md](VIEWS.md).

## Done

- Task list with drag to reorder, keyboard shortcuts and Alt variants for the web.
- Only the top task runs; done and delete hand the timer on; Undo for both.
- Pause logs a break; done keeps when it finished.
- Countdown with time's up alert, 30-minute reminder, mute.
- Phone and desktop layouts, light and dark theme.
- Sync-ready data model and the task list in a crdt_lf document (sync steps 1 and 2).
- Web app on GitHub Pages; builds for Linux, macOS and Windows; unit and end-to-end tests.

## Next

1. **Navigation shell.** Bottom bar on phones, rail on desktop, with Now and placeholder History and
   Notes; bell and gear in the top bar. No new behaviour. Lets us judge the layout on real devices.
2. **Settings.** Default countdown length, reminder interval, sounds, theme. Small, and removes the
   hard-coded 20 and 30 minutes.
3. **History and metrics.** Day view of work and breaks from the data already recorded, then week view
   and the "today" line on Now. Bring back done tasks from history.
4. **Multiple logs.** Work, Personal and more, each its own document. Log switcher, move a task to
   another log. Comes before sync so that sharing is per log from the start.
5. **Notes.** Notes per log, optionally linked to a task.
6. **Alerts.** Scheduled local notifications so alerts fire with the app in the background; the bell
   with fired and upcoming alerts.
7. **Live sync between your devices** (sync steps 3 to 5): pairing by QR or text code, Nostr for
   signalling only, WebRTC data channel, encrypted and signed changes. Opt-in, per log. Pairing is
   already in review (#13); it should be adapted to pair per log once step 4 lands.
8. **Shared logs.** Share one log with another person's device, using the same pairing.
9. **Offline sync.** An app-dedicated Nostr relay as an encrypted mailbox, so devices that are never
   online together still converge.

## Later, not ordered

- Export and import (JSON, CSV for history).
- Phone home-screen widget or persistent notification showing the current task.
- Installable web app (PWA) with offline caching.
- Android store build. (iOS release and TestFlight are in review in #10.)

## Not planned

- Accounts or a hosted backend.
- Goals, streaks or scores.
- Veilid and IPFS for sync (ruled out in the sync research).
