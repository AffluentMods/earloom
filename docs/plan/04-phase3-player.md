# Phase 3: The player

Goal: the best-feeling audiobook player on either platform. Gapless across multi-file books, chapter-aware everywhere, never loses a position, syncs with ABS like a first-party client.

Branch: `phase-3-player`

---

## 3.1 Audio stack

Files: `lib/features/player/audio_handler.dart`, `lib/features/player/player_controller.dart`, `lib/main.dart`

- `audio_service` with a single `BaseAudioHandler` (`AppAudioHandler`) owning one `just_audio` `AudioPlayer`.
- `audio_session`: `AudioSessionConfiguration.speech()`. Handle interruptions: pause on call or other audio, resume afterwards only if we were playing and the interruption lasted under 2 minutes. Pause on "becoming noisy" (headphones unplugged, Bluetooth dropped).
- Android: notification channel `playback`, keep the notification after pause (audiobook users pause a lot), foreground service type `mediaPlayback` with the matching permission in the manifest.
- iOS: background mode `audio` in `Info.plist`.
- `PlayerController` is the app-facing API (Riverpod provider). UI, CarPlay, Android Auto, widgets and shortcuts all call the controller. Nothing else touches `AudioPlayer`.

```dart
// lib/features/player/player_controller.dart
abstract interface class PlayerController {
  Stream<PlayerSnapshot> get snapshots; // item, chapter, global position, duration, speed, isPlaying, sleep timer, buffering
  Future<void> playItem(String itemId, {String? episodeId, Duration? startAt, bool userInitiated = true});
  Future<void> togglePlayPause();
  Future<void> seekGlobal(Duration position);
  Future<void> skipBy(Duration delta); // negative for back
  Future<void> nextChapter();
  Future<void> previousChapter(); // within first 3s of a chapter goes to previous, otherwise restarts current
  Future<void> setSpeed(double speed);
  Future<void> addBookmark({String? title});
  Future<void> stop(); // syncs and closes session
}
```

### Acceptance
- [ ] Phone call interrupts and resumes correctly on both platforms
- [ ] Unplugging headphones pauses
- [ ] Notification and lock screen show cover, title, chapter name, progress and controls

---

## 3.2 Starting a playback session

File: `lib/features/player/session_starter.dart`

1. Proactive token refresh if under 2 minutes left (Phase 1).
2. If the item is downloaded (Phase 4), build a local session and play local files. Skip the network entirely.
3. Otherwise `POST /api/items/:id/play` (or `/play/:episodeId`) with:

```dart
final body = {
  'deviceInfo': {
    'deviceId': await DeviceId.stable(),     // random uuid generated once, stored in GlobalDb
    'clientName': 'Earloom',
    'clientVersion': packageInfo.version,
    'manufacturer': device.manufacturer,
    'model': device.model,
    'sdkVersion': device.osVersion,
  },
  'forceDirectPlay': false,
  'forceTranscode': false,
  'supportedMimeTypes': PlatformAudio.supportedMimeTypes, // per platform list, verified by test files
  'mediaPlayer': 'earloom',
};
```

4. Build sources from `session.audioTracks`:
   - Direct play: stream URL per track. Prefer the public session track route (`/public/session/:sessionId/track/:index`) if Phase 0 confirmed it supports range requests, so no token sits in the player and long sessions never hit token expiry. Otherwise use `contentUrl` with an `Authorization` header via `AudioSource.uri(uri, headers: ...)`.
   - Transcode (server returns HLS for unsupported formats): use the HLS URL from the session as documented in `docs/abs-api.md`.
5. `player.setAudioSources(sources, initialIndex: i, initialPosition: local)` (just_audio 0.10+ API, confirm against the pinned version) with `(i, local)` from `TrackMap.locate(startAt ?? session.currentTime)`.
6. Restore per-book speed (or default), then play.

### Acceptance
- [ ] Multi-file MP3 book plays gaplessly across file boundaries
- [ ] Single M4B with embedded chapters seeks instantly to any chapter
- [ ] A format the device cannot decode (test with an OGG file on iOS) plays via server transcode
- [ ] Two-hour playback against the short-token dev server never stalls on auth

---

## 3.3 Track map

File: `lib/features/player/track_map.dart`

All user-facing positions are global (whole-book) positions. The player works in (track index, offset). This class is the only translation layer.

```dart
class TrackMap {
  TrackMap(List<TrackInfo> tracks) : _tracks = [...tracks]..sort((a, b) => a.startOffset.compareTo(b.startOffset));
  final List<TrackInfo> _tracks;

  Duration get total => _tracks.isEmpty ? Duration.zero : _tracks.last.startOffset + _tracks.last.duration;

  ({int index, Duration offset}) locate(Duration global) {
    final g = global < Duration.zero ? Duration.zero : (global > total ? total : global);
    // binary search for last track with startOffset <= g
    var lo = 0, hi = _tracks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tracks[mid].startOffset <= g) { lo = mid; } else { hi = mid - 1; }
    }
    return (index: lo, offset: g - _tracks[lo].startOffset);
  }

  Duration toGlobal(int index, Duration offset) => _tracks[index].startOffset + offset;
}

class TrackInfo {
  const TrackInfo({required this.index, required this.startOffset, required this.duration, required this.uri, required this.mimeType});
  final int index;
  final Duration startOffset;
  final Duration duration;
  final Uri uri;
  final String mimeType;
}
```

### Tests
- [ ] Locate at 0, at an exact track boundary, mid-track, past the end, negative
- [ ] Round trip `toGlobal(locate(x))` equals `x` for 10,000 random positions

---

## 3.4 Chapters

File: `lib/features/player/chapters.dart`

- Source: `session.chapters` (fall back to item chapters, then one chapter per track, then a single chapter for the whole book).
- `currentChapter` derived from global position, exposed on `PlayerSnapshot`.
- Progress bar mode (user setting, default chapter): chapter-relative scrubber with "Chapter 7 of 32" and chapter time left, or whole-book scrubber.
- Next and previous chapter commands. Previous within the first 3 seconds of a chapter goes to the previous chapter, otherwise restarts the current one.
- Chapters sheet: list with titles, start times and durations, current highlighted and auto-scrolled into view, finished chapters dimmed.

### Acceptance
- [ ] Chapter name updates on the lock screen and notification when crossing a boundary
- [ ] Books with zero chapters still get sensible fallback chapters

---

## 3.5 Transport and listening comfort

| Feature | Spec |
|---|---|
| Skip intervals | Back and forward set separately: 5, 10, 15, 30, 45, 60, 90s. Defaults: back 15, forward 30. Buttons show the number. |
| Speed | 0.5x to 3.5x in 0.05 steps. Sheet with slider, plus/minus buttons and presets (0.8, 1.0, 1.2, 1.5, 1.75, 2.0). Remember per book (setting, default on). Pitch preserved. |
| Smart rewind | After a pause, rewind on resume: paused 1 to 5 min = 5s, 5 to 60 min = 15s, over 1 hr = 30s. Toggle in settings. |
| Volume boost | Android only: `AndroidLoudnessEnhancer`, 0 to +10 dB. Hidden on iOS. |
| Skip silence | Android only: ExoPlayer skip silence via just_audio. Hidden on iOS. |
| Remote buttons | Setting: headset/car next and previous do skip intervals (default) or chapters. iOS uses skip forward/backward remote commands so the lock screen shows the interval icons. |
| Auto-play next | Setting: when a book finishes, play the next book in the series, or the next queue item, or stop. Default: next in queue, else stop. |

### Acceptance
- [ ] Speed and skip settings apply to lock screen, notification, headset and car controls
- [ ] Smart rewind never rewinds before 0 or across into the previous book

---

## 3.6 Session sync

File: `lib/features/player/session_sync.dart`

- While playing, sync every 15 seconds: `POST /api/session/:id/sync` with `currentTime` (global), `timeListened` (wall-clock seconds actually playing since last sync, not scaled by speed), `duration`.
- Also sync immediately on: pause, seek (debounced 2s), chapter change, app going to background, stop.
- Close the session (`/close`) on stop, item switch, or 30 minutes paused.
- Always also write progress to the local `progress` table first (UI reads from there).
- If sync fails with a network error: keep accumulating locally, convert to an offline local session (Phase 4 outbox) and keep playing.
- If the server says the session no longer exists: start a new session silently at the current position.

```dart
class SessionSync {
  SessionSync(this._api, this._db, this._clock);
  static const interval = Duration(seconds: 15);
  Duration _listenedSinceSync = Duration.zero;
  DateTime? _playingSince;

  void onPlay() => _playingSince = _clock.now();
  void onPause() { _accumulate(); }
  void _accumulate() {
    if (_playingSince == null) return;
    _listenedSinceSync += _clock.now().difference(_playingSince!);
    _playingSince = _clock.now();
  }
  Future<void> sync(String sessionId, Duration current, Duration total) async {
    _accumulate();
    await _db.progressDao.writeLocal(/* ... */);
    try {
      await _api.syncSession(sessionId, currentTime: current, timeListened: _listenedSinceSync, duration: total);
      _listenedSinceSync = Duration.zero;
    } on DioException {
      // keep _listenedSinceSync, hand off to offline session recorder
    }
  }
}
```

### Acceptance
- [ ] Listen 10 minutes at 2x: ABS listening stats show about 10 minutes, not 20
- [ ] Kill the app mid-playback: reopening restores position within 15 seconds of where it was
- [ ] Toggle airplane mode during streaming: playback continues from buffer, progress recorded, synced later

---

## 3.7 Progress conflicts

File: `lib/features/player/progress_resolver.dart`

Cases:
1. **Starting playback**: compare local progress and server progress for the item. If the server one is newer (`lastUpdate`) and differs by more than 30 seconds, start at the server position and show a snackbar: "Picked up where you left off on another device" with Undo (jumps back to the local position).
2. **Remote update while playing here**: local wins, do not jump. If a remote update is newer than our last sync and more than 2 minutes away, show a one-time snackbar with "Jump" so the user decides.
3. **Remote update while paused or not playing**: apply silently, update the hero card and mini player.
4. **Finished elsewhere**: if marked finished on the server while paused here, update state, do not auto-play.

### Acceptance
- [ ] Unit tests for each case with a fake clock
- [ ] Manual: listen on the ABS web UI, open the app, it resumes at the web position with the snackbar

---

## 3.8 Sleep timer

File: `lib/features/player/sleep_timer.dart`

- Modes: duration (5, 10, 15, 30, 45, 60, 90 min, custom), end of current chapter, end of book.
- Fade out over the last 30 seconds (configurable 0 to 60s), then pause and rewind by the fade length so nothing is missed.
- Shake to extend: when the timer is in its last 60 seconds or fading, a shake adds the original duration again (`sensors_plus`, low-power sampling only while the timer is active). Haptic confirmation.
- Auto sleep timer: optional time window (default 22:00 to 06:00). Starting playback inside the window starts the default timer automatically.
- Timer lives in the audio handler, not the UI, so it works with the screen off, from CarPlay, and from widgets.
- Remaining time shows on Now Playing and in the Android notification subtitle.

```dart
sealed class SleepTimerState {}
class SleepOff extends SleepTimerState {}
class SleepCountdown extends SleepTimerState { SleepCountdown(this.endsAt, this.original); final DateTime endsAt; final Duration original; }
class SleepEndOfChapter extends SleepTimerState { SleepEndOfChapter(this.chapterId); final String chapterId; }
class SleepFading extends SleepTimerState { SleepFading(this.until); final DateTime until; }
```

### Acceptance
- [ ] Timer fires correctly with the screen locked for 45 minutes
- [ ] End of chapter respects speed changes made after setting it
- [ ] Shake extends only while the timer is active

---

## 3.9 Bookmarks

File: `lib/features/player/bookmarks.dart`, `lib/features/player/ui/bookmarks_sheet.dart`

- Add bookmark: one tap on Now Playing (and from lock screen custom action on Android, CarPlay button in Phase 6). Haptic plus snackbar with "Add note".
- Default title: chapter name plus chapter-relative timestamp. Editable.
- List sheet: sorted by time, tap to jump, swipe to delete, edit title.
- Sync via ABS bookmark endpoints. ABS keys bookmarks by time: round to the whole second and nudge +1s if one already exists there.
- Offline: queue in the outbox (Phase 4).

### Acceptance
- [ ] Bookmarks round-trip with the ABS web UI
- [ ] Two quick bookmarks in the same second both survive

---

## 3.10 Queue and finishing

- Local "Up next" queue: Play next, Add to queue from any item menu. Reorder and remove in a sheet.
- Book finishes (position within 5s of end, or ended event): mark finished locally and on the server, close the session, then apply the auto-play setting.
- Listen again resets progress only when the user starts it.

---

## 3.11 Now Playing and mini player

Files: `lib/features/player/ui/now_playing_screen.dart`, `lib/features/player/ui/mini_player.dart`

Now Playing (full-screen, swipe down to dismiss):
- Background: slow-moving gradient built from 3 colors of the cover scheme (`primaryContainer`, `secondaryContainer`, `tertiaryContainer`). Subtle, no strobing. Respects reduce motion (static gradient).
- Top bar: down chevron, library or series name, more menu.
- Cover: large, rounded, soft shadow, scales down slightly when paused.
- Title (serif) and author. Chapter name above the scrubber.
- Scrubber: chapter or book mode (tap the time labels to toggle). Shows elapsed, remaining at current speed. Haptic tick at chapter boundaries when scrubbing in book mode.
- Controls: previous chapter, skip back (shows number), play/pause (large), skip forward, next chapter.
- Bottom row: speed (shows value), sleep timer (shows remaining), bookmark, chapters, output (AirPlay route picker on iOS, system output switcher on Android 11+).
- Swipe left/right on the cover: skip back/forward (setting, default off).

Mini player:
- Above the nav bar on every tab. Cover, title, chapter, thin progress line, play/pause, skip back.
- Tinted with the cover scheme. Tap opens Now Playing with a hero cover transition. Swipe down to stop and clear.

State restore: last item, position, speed, queue and sleep settings persist. Cold start shows the mini player paused at the saved position. Never autoplay on launch.

### Acceptance
- [ ] Hero transition is smooth (no frame drops over 16ms in a profile build on a mid-range Android)
- [ ] VoiceOver and TalkBack can operate every control; scrubber exposes adjustable actions in chapter-sized steps
- [ ] Golden tests: Now Playing in light, dark, AMOLED, with 3 different covers

---

## l10n keys added in Phase 3

```
playerChapterOf(current, total), playerTimeLeftAtSpeed(time), playerSkipBack(seconds), playerSkipForward(seconds),
playerPreviousChapter, playerNextChapter, playerPlay, playerPause, playerSpeed, playerSpeedValue(speed),
playerSleepTimer, playerSleepRemaining(time), playerBookmark, playerChapters, playerOutput, playerQueue,
speedSheetTitle, speedPresets, speedRememberPerBook,
sleepTitle, sleepMinutes(minutes), sleepCustom, sleepEndOfChapter, sleepEndOfBook, sleepOff,
sleepFadeOut, sleepShakeToExtend, sleepExtended(minutes), sleepAuto, sleepAutoWindow(start, end),
bookmarkAdded, bookmarkAddNote, bookmarkDefaultTitle(chapter, time), bookmarksTitle, bookmarksEmpty,
bookmarkEdit, bookmarkDelete,
queueTitle, queuePlayNext, queueAddToQueue, queueEmpty, queueClear,
progressSyncedFromOtherDevice, progressUndo, progressJumpPrompt(time), progressJump,
finishedBook(title), nowPlayingOpen, nowPlayingDismiss
```

## Phase 3 done when
- [ ] All section checklists ticked
- [ ] 8-hour soak test on a real Android and a real iPhone (screen off, Bluetooth, a few pauses): no crashes, progress matches ABS within 15s, battery use reasonable (record numbers in the PR)
