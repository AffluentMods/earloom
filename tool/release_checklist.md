# Release checklist

For every Earloom release (docs/plan/10-phase9-release.md 9.6).

1. Bump `version:` in `pubspec.yaml` (`x.y.z+build`, build always goes up).
2. `tool/check.sh` passes, and the live tests against `tool/abs-dev` pass.
3. Smoke test on real devices: an Android phone and tablet, an iPhone and
   iPad. Sign in, play a server book and a local book, download a book and
   play it in airplane mode, sleep timer, bookmarks, lock screen controls.
4. Android Auto in the Desktop Head Unit; CarPlay in the CarPlay Simulator
   (once the entitlement is granted).
5. Build:
   - Android: `tool/release_android.sh` (needs `android/key.properties`).
   - iOS, on the Mac: `tool/ios/release_ios.sh`.
6. Archive `build/debug-symbols/<version>` with the release, outside the repo.
7. Store notes, What's New and the Discord changelog: written in the chat,
   reviewed by the owner, never committed as files.
8. Betas first: TestFlight external group and Play closed testing, at least
   a week before 1.0.
9. Tag and publish only when the owner says so.
