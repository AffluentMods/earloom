# Device tests

Tests that run the whole app on a real device, emulator or simulator. They need one connected (`flutter devices` lists it).

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_launch_test.dart
```

Screenshots taken during the run land in `build/device-screenshots/`.

`tool/ci/device_check_android.sh` and `tool/ci/device_check_ios.sh` run the same test plus deep link checks through the operating system itself. The `Devices` workflow runs both on every pull request (Android emulator and iPhone simulator) and keeps the screenshots as artifacts.

Tests that talk to the dev server in `tool/abs-dev` arrive in Phase 1.
