# bringmeback
A Pomodoro timer, stopwatch, and task manager to help you stay focused.

Write today's tasks on a small numbered note, in the order you will do them. The first task not
checked off is the one you are working on, and it is the only one whose timer runs. Check it off and
it stays on the note, struck through, while the next one takes over. Each day starts with tearing off
yesterday's note and writing again only what still matters. Pausing logs a
break, so the time between tasks is kept too. Deleted tasks can be brought back with Undo, and History keeps every note.

- [How to use the app](docs/USAGE.md)
- [Goals and usability rules](docs/PRINCIPLES.md)
- [Views and navigation plan](docs/VIEWS.md)
- [Roadmap](docs/ROADMAP.md)

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+N or Alt+N | New task on top, with its timer running |
| Ctrl+Shift+N or Alt+Shift+N | New task after the selected one |
| Ctrl+Enter or Alt+Enter | Check off the selected task, or uncheck it |
| Ctrl+D or Alt+D | Delete the selected task |
| Enter | Save the task in the task dialog |

Browsers keep Ctrl+N and Ctrl+D for themselves, so use the Alt variants in the web app.


## Run the web app in Docker

Docker builds the web app and serves it, so you don't need Flutter installed. This works the same on
Windows (Docker Desktop with Linux containers), macOS, and Linux:

```sh
docker build -t bringmeback-web .
docker run --rm -p 8080:8080 bringmeback-web
```

Then open http://localhost:8080. The first build downloads the Flutter SDK and takes several minutes;
later builds reuse it.

## Versions

Every build shows its version in **Settings** (under About) and on the **Devices** page, where each
paired device's version is listed too:

- a release (a commit tagged `vX.Y.Z`) shows its number, such as `v1.2.0`;
- any other build shows the time of its last commit and the commit, such as
  `2026-11-13 12:30 UTC · 70135a09b6`, with `-dirty` when it was built with uncommitted changes.

- a release shows its commit too, such as `v1.2.0 · 70135a09b6`;
- a build with uncommitted changes shows when it was built instead of the commit time, so a stale
  cached build is easy to spot.

`tool/build_info.sh defines` prints the `--dart-define` flags that set this. Run the app with
`tool/run.sh` (the same arguments as `flutter run`, such as `tool/run.sh -d chrome`) and build with
`flutter build web $(tool/build_info.sh defines)`. The Docker build and the CI builds do this on
their own. A plain `flutter run` shows "Development build, no commit".

The web app also checks `build-info.json` on its own server (written by `tool/build_info.sh json`) when
it starts, every half hour and when you come back to it, and offers **Reload** when a newer build is
served. Released desktop and phone apps can check GitHub for a newer release, which is off until you
turn it on in Settings.

## Tests

Unit tests: `flutter test`

End-to-end tests launch the app and drive it through the UI. On the desktop:

```sh
flutter test integration_test -d linux   # or macos, windows
```

In Chrome, with [ChromeDriver](https://googlechromelabs.github.io/chrome-for-testing/) running on port 4444:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
  -d web-server --browser-name=chrome --headless --no-web-resources-cdn
```
