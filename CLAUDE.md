# Working on bringmeback

## Building and testing

- `flutter pub get`, then `tool/build_symbolon.sh native` once (needs Rust): unit tests load that
  native Symbolon library.
- `flutter analyze` and `flutter test` must pass before a PR.
- Sync tests use `test/fake_relay.dart` (an in-memory Nostr relay that can be unreachable, deaf,
  refusing, filter by `since`, or have a connection die silently) and `test/fake_transport.dart`
  (a direct link that can hold or drop messages). Extend these fakes rather than skip a case.

## User stories are the spec: keep them current

[docs/USER-STORIES.md](docs/USER-STORIES.md) lists what a person does with sync and tear-off, the
expected behaviour, every edge case found so far, and the test that covers each one. Keep it true
in the same PR as the change:

1. **A bug fix**: add the case that broke, in words a user would recognise ("the phone said No other
   device online while the desktop was open"), with the date. Write a test that fails before the
   fix and passes after, and name it in the row. If the test reproduces a user's report, say so in
   the PR.
2. **A new feature**: add a story with its main case and the edge cases you can think of: devices
   apart, both devices doing it at once, a device on an older version, a device that comes back
   after hours, clocks that disagree, a relay that misbehaves, the app reloaded mid-way.
3. **A security or privacy finding**: add a row under **S** with what an attacker or a relay could
   do and what the app does about it, and the test that pins it down. An unfixed finding is a
   **gap** with what would fix it.
4. **Something you can't fix or test now**: list it under **Not covered yet** in its section, as a
   gap or a known limit, never leave it out.
5. **Behaviour changes**: update the row, and [docs/SYNC.md](docs/SYNC.md) when the mechanics
   change.

Each row's status is **covered**, **known limit** or **gap**. A row marked covered names a test
that exists; renaming or deleting a test means updating its row. New tests for stories that have
no better home go in `test/sync_stories_test.dart`, named with the story id (`T1.2 …`).

When you can't verify on a real device (an iPhone, a given browser, the live relays), say so in
the PR and in your reply.
