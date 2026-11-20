# Release checklist

## First release, once

1. Apple developer site: App Group `group.com.affluentlabs.earloom`; App
   IDs `com.affluentlabs.earloom` (App Groups, CarPlay Audio) and
   `com.affluentlabs.earloom.NowPlayingWidget` (App Groups). Details:
   `ios/NowPlayingWidget/README.md`. Then, on the Mac, `tool/ios/profiles.rb`
   makes the two App Store profiles (`tool/ios/README.md`).
2. Demo server for review: `tool/demo-server/README.md`.
3. Publish `docs/privacy-policy.md` and `docs/support.md` on affluentlabs.dev.
4. App Store Connect: new app "Earloom: Audiobook Player", bundle id
   `com.affluentlabs.earloom`, screenshots from
   `STORE=1 flutter test tool/screenshots/app_screens.dart`
   (`build/screenshots/store/ios_*`), privacy answers "Data Not Collected",
   review notes from the demo server README.
5. Play Console: new app, upload key signing (Play App Signing on), store
   listing from `fastlane/metadata/android/en-US/`, Data safety "no data
   collected or shared", content rating, app access from the demo server
   README.

## Every release

For every Earloom release (docs/plan/10-phase9-release.md 9.6).

1. Bump `version:` in `pubspec.yaml` (`x.y.z+build`, build always goes up).
2. `tool/check.sh` passes, and the live tests against `tool/abs-dev` pass.
3. Smoke test on real devices: an Android phone and tablet, an iPhone and
   iPad. Sign in, play a server book and a local book, download a book and
   play it in airplane mode, sleep timer, bookmarks, lock screen controls.
4. Android Auto in the Desktop Head Unit; CarPlay in the CarPlay Simulator.
5. Build:
   - Android: `tool/release_android.sh` (needs `android/key.properties`).
   - iOS, on the Mac: `tool/ios/build_ipa.sh`, then the upload with
     `xcrun altool`. Both lines are in `tool/ios/README.md`.
6. Archive the symbols with the release, outside the repo:
   `build/debug-symbols/<version>` from the Android build. The iOS script
   puts its own in `~/earloom-releases/<version>+<build>/` on the Mac.
7. Store notes, What's New and the Discord changelog: written in the chat,
   reviewed by the owner, never committed as files.
8. Betas first: TestFlight external group and Play closed testing, at least
   a week before 1.0.
9. Tag and publish only when the owner says so.
