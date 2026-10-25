# bringmeback
A Pomodoro timer, stopwatch, and task manager to help you stay focused.


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
