# bringmeback
A Pomodoro timer, stopwatch, and task manager to help you stay focused.

Only one task's timer runs at a time: starting one pauses the others. Deleted tasks can be brought
back with Undo.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+N or Alt+N | New task on top, with its timer running |
| Ctrl+Shift+N or Alt+Shift+N | New task after the selected one |
| Ctrl+D or Alt+D | Delete the selected task |
| Enter | Finish editing a task name or timer |

Browsers keep Ctrl+N and Ctrl+D for themselves, so use the Alt variants in the web app.


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
