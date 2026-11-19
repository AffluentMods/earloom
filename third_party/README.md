# Vendored packages

Packages here are copies of other people's open source code that Earloom
needs to change. Each keeps its own license file and headers. `tool/check.sh`
skips them: they are not ours, so our header, dash and format rules do not
apply. Keep every change small and listed below, so the copy can be dropped
the moment upstream has the fix.

## audio_service

- Upstream: <https://github.com/ryanheise/audio_service>, package
  `audio_service` 0.18.19 from pub.dev.
- License: MIT, see `audio_service/LICENSE`. MIT code can ship in Earloom
  under GPL-3.0-or-later with the app store exception.
- Copied: `lib/`, `android/`, `darwin/`, `LICENSE`, `README.md`,
  `CHANGELOG.md`, `pubspec.yaml`. Left out: `example/`, `test/` and
  `analysis_options.yaml`, which only upstream's own development uses.

### Patch: explicit play and pause keys

File: `android/src/main/java/com/ryanheise/audioservice/AudioService.java`,
`MediaSessionCallback.onMediaButtonEvent` (marked "Earloom patch").

Upstream sends a genuine `KEYCODE_MEDIA_PLAY` or `KEYCODE_MEDIA_PAUSE` to
`onClick(MediaButton.media)`, the same path as the toggle keys, and
`BaseAudioHandler.click` toggles. So a pause key from a headset, car or
`adb shell input keyevent KEYCODE_MEDIA_PAUSE` started playback when the book
was already paused, and a play key paused it. The patch routes those two keys
to `onPlay` and `onPause`. `KEYCODE_MEDIA_PLAY_PAUSE` and
`KEYCODE_HEADSETHOOK` still go to `onClick` and toggle. The notification's
own play and pause buttons already used the plugin's bypass keycodes and are
unchanged.

### Updating

1. Copy the new release from the pub cache over `audio_service/` (same files
   as above).
2. Check whether upstream fixed `onMediaButtonEvent`. If it did, delete
   `third_party/audio_service`, go back to the hosted dependency in
   `pubspec.yaml` and remove this section.
3. If not, apply the patch again and update the version above.
