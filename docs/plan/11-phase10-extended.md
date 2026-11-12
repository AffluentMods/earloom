# Phase 10: Watch apps and casting

Goal: extend listening to the wrist and the living room. These are native or plugin-heavy pieces, built after 1.0 ships so they never block the launch.

Branch: `phase-10-extended` (or one branch per platform)

---

## 10.1 Apple Watch (SwiftUI, native)

Files: `ios/WatchApp/` (watchOS target), `ios/Runner/Watch/WatchBridge.swift`, `lib/platform/watch_bridge.dart`

**Stage 1: companion remote**
- watchOS already shows the system Now Playing for phone audio. Our app adds what it lacks: chapter list with jump, bookmark button, speed picker, sleep timer, Continue listening list (tap to start on phone).
- Transport: WatchConnectivity. Phone sends a compact snapshot (same shape as the widget snapshot, minus file paths, plus small cover thumbnails). Watch sends commands that the phone routes to `PlayerController`.
- Complications: progress ring, minutes today.

**Stage 2: standalone offline playback**
- From the phone's Downloads screen: "Send to Watch" for a downloaded book. Transfer files with `WCSession.transferFile`, show transfer progress.
- Watch plays with AVFoundation to Bluetooth headphones, using a track map equivalent to Phase 3.
- Progress and local sessions recorded on the watch, sent back to the phone, which puts them in the outbox. The watch never holds ABS tokens (overview rule 10, extended: only the phone's main isolate authenticates).

### Acceptance
- [ ] Stage 1: every watch control acts on phone playback within 1s
- [ ] Stage 2: listen on the watch with the phone off, then reconnect: progress and stats land in ABS correctly

---

## 10.2 Wear OS (Kotlin, Compose for Wear OS, native)

Files: `android/wear/` module

- Flutter on Wear OS is limited; use Kotlin with Compose for Wear OS and the Horologist media UI components.
- Stage 1 remote: Wearable Data Layer API for snapshots and commands, same contract as the Apple Watch.
- Stage 2 offline: transfer downloaded files via the Data Layer `ChannelClient`, play with Media3 ExoPlayer on the watch, relay progress back through the phone outbox.
- Tiles: Now Playing tile and Today tile.

### Acceptance
- [ ] Same acceptance as 10.1 for both stages
- [ ] Passes Wear OS app quality guidelines

---

## 10.3 Chromecast

Files: `lib/features/player/cast/`

- `play` Android flavor and iOS only. The `foss` flavor (F-Droid) ships without Cast.
- Evaluate maintained Google Cast plugins for Flutter. If none is solid, wrap the native Cast SDKs behind a small MethodChannel.
- Use the Default Media Receiver. Stream URLs must be reachable by the Cast device without app headers: use the public session track URLs (Phase 0) so no token is ever sent to the receiver.
- Multi-file books: queue the tracks on the receiver and map positions with `TrackMap`.
- While casting, the phone keeps the ABS session alive and runs `SessionSync` using the receiver's reported position.
- Cast button in Now Playing next to the output button, only shown when a Cast device is on the network.

### Acceptance
- [ ] Cast a multi-file book, scrub across file boundaries, stop casting: playback resumes on the phone at the same position
- [ ] Progress syncs to ABS while casting

---

## 10.4 Parked (needs its own plan doc before work starts)

- **Ebook reader**: ABS serves epub and pdf. Reading position sync, whispersync-style audio and text pairing is a large project.
- **Desktop builds** (Windows, macOS): ZestSSH already ships on Windows, so the pipeline exists, but the media session and tray story need design.
- **Public share links**: ABS supports share links for items; playing a shared link without an account.

## l10n keys added in Phase 10

```
watchSendToWatch, watchTransferring(percent), watchOnWatch, watchRemoveFromWatch, watchNotConnected,
castButton, castConnectedTo(device), castStop, castNoDevices
```

Watch apps generate their native strings from `app_en.arb` with `tool/gen_native_strings.dart`, same as Phase 6.

## Phase 10 done when
- [ ] Each stage shipped as its own release with its own checklist
