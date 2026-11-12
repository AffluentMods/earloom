# Phase 6: System integration

Goal: the app shows up everywhere a listener reaches for it: lock screen, car, home screen, Dynamic Island, voice, shortcuts. Each surface talks to `PlayerController` and reads cached data. None of them talk to ABS directly.

Branch: `phase-6-system`

**Do this first, on day one of the phase:** request the CarPlay audio entitlement (`com.apple.developer.carplay-audio`) from Apple through the developer portal. Approval can take days to weeks. Build CarPlay against the simulator while waiting.

---

## 6.1 Lock screen and notification polish

Files: `lib/features/player/audio_handler.dart`, `android/app/src/main/res/drawable/`

Android:
- Compact actions: skip back, play/pause, skip forward. Skip icons show the configured interval (provide drawables for 5, 10, 15, 30, 45, 60, 90).
- Extra custom actions: bookmark, speed cycle (1.0 > 1.25 > 1.5 > 2.0 > 1.0).
- Notification title: book title. Subtitle: chapter name, plus sleep timer remaining when active.

iOS:
- Remote commands: skip backward/forward with `preferredIntervals` matching settings, change playback position (scrubbing), change playback rate with the supported rate list.
- Now Playing info: elapsed time, duration and `playbackRate` equal to current speed so the system clock runs correctly.
- Setting: lock screen shows book progress (default) or chapter progress.

### Acceptance
- [ ] Lock screen scrubbing works on both platforms
- [ ] Changing skip intervals in settings updates lock screen icons without restarting playback

---

## 6.2 Android Auto

Files: `lib/features/player/media_browser.dart`, `android/app/src/main/res/xml/automotive_app_desc.xml`, `AndroidManifest.xml`

- Implement `getChildren`, `getMediaItem`, `search` and `playFromSearch` in the audio handler.
- Browse tree (built from AccountDb, works offline):

```
root
  Continue listening        (playable items, max 20)
  Recently added            (playable)
  Downloaded                (playable)
  Series                    (browsable) > books in sequence order
  Authors                   (browsable) > books
  Podcasts                  (browsable, if a podcast library exists) > shows > episodes
```

- Content style hints: grid for books and shows, list for episodes and chapters.
- Artwork: pass cover URIs the platform can load (cached file URIs where possible), downscaled.
- Voice: "Play <title> on Earloom" resolves through `playFromSearch` against local FTS (Phase 2).
- Signed out or `needsReauth`: playback state error with a message telling the user to open the app on their phone. Downloaded items stay playable.
- Manifest: `com.google.android.gms.car.application` meta-data pointing to `automotive_app_desc.xml`.

### Acceptance
- [ ] Full browse and playback in the Desktop Head Unit (DHU)
- [ ] Voice search plays the right book
- [ ] Works in airplane mode with downloads only
- [ ] Meets Google's Android Auto media app quality checklist (review it before submitting)

---

## 6.3 CarPlay (native Swift)

Files:
- `ios/Runner/CarPlay/CarPlaySceneDelegate.swift`
- `ios/Runner/CarPlay/CarPlayTemplates.swift`
- `ios/Runner/CarPlay/CarPlayChannel.swift`
- `lib/platform/carplay_bridge.dart`
- `ios/Runner/Info.plist` (scene manifest), `Runner.entitlements`

Approach:
- CarPlay requires a scene-based app. Adopt Flutter's UIScene lifecycle (follow Flutter's official UIScene migration guide for the pinned Flutter version), and add a `CPTemplateApplicationSceneSessionRoleApplication` scene configuration pointing to `CarPlaySceneDelegate`.
- One shared `FlutterEngine` created in `AppDelegate` and started at launch, so CarPlay works when the phone app was never opened (cold launch from the car). The audio handler and `PlayerController` must initialize headless.
- Evaluate `flutter_carplay` first. Use it only if it is maintained and supports everything below; otherwise implement natively as specified here.

Templates:
- `CPTabBarTemplate` with tabs: Listen Now (continue listening + recently added sections), Library (series and authors lists), Downloads, Podcasts (only if a podcast library exists).
- `CPListTemplate` items: cover image, title, author, progress indicator (`playbackProgress`), now-playing indicator on the current item. Respect `maximumItemCount` and `maximumSectionCount`.
- `CPNowPlayingTemplate.shared`: playback rate button enabled, "Up Next" button relabeled to Chapters (opens a chapter list), custom image button for bookmark.

Channel contract (`earloom/carplay`):

```dart
// lib/platform/carplay_bridge.dart
// Swift -> Dart (method calls)
//   getSection(String id) -> List<CarItem>   ids: continue, recent, downloads, series, series:<id>, authors, author:<id>, podcasts, show:<id>
//   play(String itemId, String? episodeId)
//   playChapter(int index)
//   getChapters() -> List<CarChapter>
//   addBookmark()
// Dart -> Swift
//   sectionsChanged(List<String> ids)   // after sync or download changes
//   nowPlayingChanged(CarNowPlaying)

class CarItem {
  CarItem({required this.id, this.episodeId, required this.title, required this.subtitle,
           this.coverPath, required this.progress, required this.isPlaying, required this.isBrowsable});
  final String id; final String? episodeId; final String title; final String subtitle;
  final String? coverPath; // local file path only, Swift never fetches from network
  final double progress; final bool isPlaying; final bool isBrowsable;
  Map<String, Object?> toMap() => { /* ... */ };
}
```

### Acceptance
- [ ] Full browse, play, chapters, speed and bookmark in the Xcode CarPlay Simulator
- [ ] Cold launch from CarPlay with the phone app killed starts playback
- [ ] Real head unit test before release (wired and wireless if available)
- [ ] All CarPlay strings localized via `Localizable.strings` generated from the .arb source (script in `tool/gen_native_strings.dart`)

---

## 6.4 Home screen and lock screen widgets

Files:
- `lib/platform/widget_bridge.dart`
- `ios/NowPlayingWidget/` (WidgetKit extension, SwiftUI), App Group `group.com.affluentlabs.earloom`
- `android/app/src/main/kotlin/<package>/widget/` (Jetpack Glance)

Data contract, written by the main isolate only, on: item change, play/pause, chapter change, sleep timer change, download complete, every 60s while playing on Android.

```json
{
  "v": 1,
  "nowPlaying": {
    "itemId": "...", "episodeId": null, "title": "...", "author": "...", "chapter": "...",
    "coverPath": "<shared container path>", "position": 1234.5, "duration": 36000.0,
    "speed": 1.25, "isPlaying": true, "updatedAt": 1700000000000,
    "tint": { "bg": 4278190080, "fg": 4294967295 }
  },
  "continue": [ { "itemId": "...", "title": "...", "coverPath": "...", "progress": 0.42 } ],
  "stats": { "todayMinutes": 47, "streakDays": 12 }
}
```

Widget kinds:
| Widget | Sizes | Content |
|---|---|---|
| Now Playing | small, medium | Cover, title, chapter, progress, play/pause (medium adds skip back) |
| Continue Listening | medium, large | 2 or 4 recent covers with progress rings, tap resumes |
| Listening Today | small | Minutes today, streak |
| Lock screen (iOS) | circular, rectangular, inline | Progress ring / title and time left / "2 hr 14 min left" |

Live progress without constant updates: on iOS use `ProgressView(timerInterval:)` and `Text(timerInterval:)` computed from position, speed and `updatedAt` while playing.

Tint: widget colors come from the cover scheme written in the snapshot, never hardcoded.

Interactive buttons:
- Android: play/pause and skip send media button intents to the audio service.
- iOS 17+: App Intents conforming to `AudioPlaybackIntent`. **Prototype first.** If triggering Flutter playback from the intent is unreliable when the app is not running, ship widget buttons as deep links (`earloom://player?action=resume`) and note it in the PR.

### Acceptance
- [ ] Widgets render correctly in light, dark and tinted/clear home screen modes
- [ ] Tap targets deep link to the right item
- [ ] Widgets never show data from a different account than the current one
- [ ] No network calls from widget extensions (code review check)

---

## 6.5 Live Activities (iOS)

Files: `ios/NowPlayingWidget/SleepTimerLiveActivity.swift`, `lib/platform/live_activity_bridge.dart`

The system Now Playing already covers playback, so Live Activities cover what it does not:
- **Sleep timer**: starts with the timer, shows cover and countdown (`Text(timerInterval:)`) on the lock screen and in the Dynamic Island, ends when the timer ends or is cancelled. Button: +15 min (App Intent, same prototype rule as widgets).
- **Downloads**: one activity while downloads are active, shows overall progress and the current title. Updated at most every 5 seconds.

Local updates only. No push tokens.

### Acceptance
- [ ] Sleep timer activity matches the in-app countdown within 1s
- [ ] Activities end cleanly when the app is killed (stale activities dismissed on next launch)

---

## 6.6 Shortcuts and voice

iOS (`ios/Runner/Intents/`):
- App Intents with an `AppShortcutsProvider`: Resume listening, Start sleep timer (parameter: minutes), Add bookmark, Play <book> (entity query over a small exported list of recent and downloaded books).
- Control Center control (iOS 18+ `ControlWidget`): resume/pause.

Android:
- Static app shortcuts (`res/xml/shortcuts.xml`): Resume, Downloads, Search.
- Assistant voice through `playFromSearch` (shared with Android Auto).

### Acceptance
- [ ] "Resume listening in Earloom" works from Siri with the app killed
- [ ] Long-pressing the app icon shows the shortcuts on both platforms

---

## l10n keys added in Phase 6

```
autoContinueListening, autoRecentlyAdded, autoDownloaded, autoSeries, autoAuthors, autoPodcasts,
autoSignInOnPhone, carplayListenNow, carplayLibrary, carplayDownloads, carplayPodcasts, carplayChapters,
carplayBookmarkAdded, widgetNowPlayingName, widgetNowPlayingDescription, widgetContinueName,
widgetContinueDescription, widgetTodayName, widgetTodayDescription, widgetNothingPlaying,
widgetMinutesToday(minutes), widgetStreak(days), liveSleepTimer, liveSleepAdd15, liveDownloading(count),
shortcutResume, shortcutSleepTimer, shortcutAddBookmark, shortcutPlayBook, shortcutDownloads, shortcutSearch,
settingsLockScreenProgress, settingsLockScreenBook, settingsLockScreenChapter
```

Native string files (iOS `Localizable.strings`, Android `strings.xml` for widgets and shortcuts) are generated from `app_en.arb` by `tool/gen_native_strings.dart`. Never hand-edit them.

## Phase 6 done when
- [ ] All section checklists ticked
- [ ] Test drive (or DHU + CarPlay Simulator if no car is available) with a real 30-minute session, notes in the PR
