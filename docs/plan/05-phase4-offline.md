# Phase 4: Downloads and offline

Goal: download a book, put the phone in airplane mode for a week, listen, bookmark, finish books, and everything lands on the server correctly the moment the phone is back online. No lost minutes, no duplicate stats.

Branch: `phase-4-offline`

---

## 4.1 Data model (AccountDb)

| Table | Columns |
|---|---|
| `downloads` | id, itemId, episodeId (nullable), status (`queued`, `downloading`, `paused`, `failed`, `complete`), bytesTotal, bytesDone, createdAt, completedAt, lastError, autoReason (nullable: `series`, `podcast`) |
| `download_files` | downloadId, trackIndex, ino, remoteUrl, localPath, sizeExpected, sizeActual, status |
| `local_snapshots` | itemId, episodeId, itemJson, chaptersJson, tracksJson, coverPath, savedAt |
| `local_sessions` | id (uuid), itemId, episodeId, startedAt, updatedAt, currentTime, timeListened, duration, payloadJson, syncedAt (nullable) |
| `outbox` | id, kind, itemId, episodeId, payloadJson, createdAt, attempts, nextAttemptAt, lastError |

`items.isDownloaded` is denormalized from `downloads.status == complete` for fast list filtering.

### Acceptance
- [ ] Migration from Phase 2 schema tested

---

## 4.2 Storage layout

```
<appSupportDir>/accounts/<accountId>/downloads/<itemId>/
  cover.webp
  track_000.<ext>
  track_001.<ext>
  ...
```

- iOS: Application Support directory, every file and folder marked `isExcludedFromBackup` (audio can be tens of GB; iCloud backup would be hostile).
- Android: app-specific external files dir (`getExternalFilesDirs`). If the device has removable storage, Settings offers "Store downloads on SD card". No storage permissions needed.
- Never write to shared Music or Downloads folders.

### Acceptance
- [ ] iOS: downloaded files do not appear in iCloud backup size (check Settings > iCloud > Manage Storage)
- [ ] Android: moving storage location moves existing downloads with progress UI, or offers to re-download

---

## 4.3 Download manager

Files: `lib/features/downloads/data/download_manager.dart`, `lib/features/downloads/data/download_paths.dart`

```dart
abstract interface class DownloadManager {
  Stream<Map<String, DownloadState>> get states; // keyed by itemId or itemId:episodeId
  Future<void> enqueueItem(String itemId, {String? episodeId, DownloadReason reason = DownloadReason.user});
  Future<void> enqueueSeries(String seriesId, {int? limit});
  Future<void> pause(String key);
  Future<void> resume(String key);
  Future<void> cancel(String key);   // removes partial files
  Future<void> delete(String key);   // removes complete files, keeps progress
  Future<void> retryFailed();
}
```

Implementation rules:
- Use `background_downloader` with one task group per item. Each audio file is its own task (resumable).
- Before enqueueing, fetch the expanded item, save a `local_snapshots` row and the cover file. The snapshot is what offline playback reads.
- Download URLs and auth come from `docs/abs-api.md`. Headers are captured at enqueue time, so: proactive token refresh right before enqueue, and on any 401 task failure refresh the token and re-enqueue the remaining files with new headers.
- Wi-Fi only (setting, default on): use the plugin's network requirement, show "Waiting for Wi-Fi" state.
- At most 2 items downloading at once, others queued.
- Progress notification on Android and iOS (plugin notification config, strings from l10n).
- Android 14+: follow the plugin's guidance for long-running downloads (run in foreground for large files) so the OS does not kill multi-GB downloads.
- On completion: verify each file size against the expected size from the snapshot. Mismatch marks the download failed with "File incomplete".

### Acceptance
- [ ] 2 GB multi-file book downloads fully with the app in the background on both platforms
- [ ] Kill the app mid-download: on relaunch the download resumes, it does not restart from zero
- [ ] Download started with a token that expires mid-way (short-token dev server) still completes
- [ ] Wi-Fi only blocks cellular and resumes on Wi-Fi

---

## 4.4 Download UI in the app

- Item detail download button states: Download, Waiting for Wi-Fi, Queued, progress ring with percent (tap to pause), Paused, Failed (tap to retry), Downloaded (tap for options: delete, re-download).
- Library cards and list rows show a small downloaded badge.
- Series screen: "Download all" and "Download next 3".
- You tab > Downloads screen:
  - Active section with progress, pause all, resume all.
  - Downloaded section grouped by library, sortable by size, title, date.
  - Storage bar: this app's downloads vs free space on device.
  - Multi-select delete. "Delete finished books" action.

### Acceptance
- [ ] Storage numbers match the OS storage settings within 5%
- [ ] Deleting a download never deletes progress or bookmarks

---

## 4.5 Automatic rules (Settings > Downloads)

| Rule | Default |
|---|---|
| Wi-Fi only | On |
| Auto-download next book in series when the current one passes 75% | Off |
| Auto-delete downloads 7 days after finishing a book | Off |
| Keep at most N GB of downloads (oldest finished removed first) | Off |
| Download location (Android, when SD card exists) | Internal |

Rules run on app foreground and after each finished book. They never delete an unfinished book.

---

## 4.6 Offline playback and local sessions

File: `lib/features/player/offline_session_recorder.dart`

- Playing a downloaded item never calls the server. Sources are `file://` URIs from `download_files`, track map from the snapshot.
- Create a `local_sessions` row (uuid id) at play start. Update `currentTime`, `timeListened`, `updatedAt` at the same 15s cadence as online sync.
- If online, also sync progress directly so other devices see it right away. Still keep the local session for stats.
- Payload shape must match what `POST /api/session/local` expects (verified in Phase 0). Include deviceInfo and a minimal media metadata snapshot.
- Streaming playback that loses the network converts to a local session from that moment (Phase 3 handoff).

### Acceptance
- [ ] Airplane mode: listen 30 min across two books, add a bookmark, finish one book. Back online: ABS shows correct progress, the finished flag, the bookmark, and about 30 min in listening stats (no double counting)

---

## 4.7 Outbox

Files: `lib/core/sync/outbox.dart`, `lib/core/sync/outbox_flusher.dart`

Every server mutation goes through the outbox when it cannot be sent immediately: progress, finished flags, bookmarks, playlist edits, local sessions.

```dart
enum OutboxKind { progress, markFinished, bookmarkAdd, bookmarkUpdate, bookmarkDelete, playlistEdit, localSession }

class OutboxFlusher {
  OutboxFlusher(this._db, this._api, this._connectivity);
  bool _running = false;

  /// Triggers: connectivity regained, app foreground, successful re-auth, every 5 min in foreground.
  Future<void> flush() async {
    if (_running) return;
    _running = true;
    try {
      await _db.outboxDao.coalesce(); // keep only the newest progress row per item
      for (final entry in await _db.outboxDao.dueInOrder()) {
        final ok = await _send(entry); // per item order preserved
        ok ? await _db.outboxDao.remove(entry.id) : await _db.outboxDao.backoff(entry.id); // 30s, 2m, 10m, 1h cap
      }
    } finally {
      _running = false;
    }
  }
}
```

Rules:
- Coalesce progress per item: only the newest matters.
- Local sessions use `/api/session/local-all` in batches of 25.
- 4xx other than 401 means the payload is bad: move to a `dead_letter` state, log it, never retry forever. Show nothing to the user unless it affected their data (then a quiet "1 change could not sync" row in Settings > Sync with details).
- Before sending progress, re-check server progress for that item: if the server is newer, do not overwrite it (same rules as Phase 3 conflicts).

### Acceptance
- [ ] Unit tests: coalescing, ordering, backoff, dead letter
- [ ] 1,000 queued entries flush in under 30s on a real device

---

## 4.8 Reachability

File: `lib/core/net/reachability.dart`

- Online means the current server answers `/ping` within 3s, not just "the phone has a network". Tailscale and LAN-only servers make this matter.
- Re-check on connectivity change, app foreground, and every 60s while a request has recently failed.
- The offline banner (`offlineBanner` key) shows only when the server is unreachable.

### Acceptance
- [ ] Phone on Wi-Fi but server down: app shows offline banner and plays downloads
- [ ] LAN-only server while on cellular: offline mode, no endless spinners

---

## l10n keys added in Phase 4

```
downloadAction, downloadWaitingWifi, downloadQueued, downloadProgress(percent), downloadPaused,
downloadFailed, downloadRetry, downloadDownloaded, downloadDelete, downloadRedownload,
downloadAllInSeries, downloadNextInSeries(count), downloadsTitle, downloadsActive, downloadsCompleted,
downloadsPauseAll, downloadsResumeAll, downloadsStorageUsed(used, free), downloadsDeleteSelected(count),
downloadsDeleteFinished, downloadsEmpty, downloadFileIncomplete,
settingsDownloadsWifiOnly, settingsDownloadsAutoNextInSeries, settingsDownloadsAutoDelete(days),
settingsDownloadsMaxSize(gb), settingsDownloadsLocation, settingsDownloadsInternal, settingsDownloadsSdCard,
notificationDownloadRunning(title), notificationDownloadComplete(title), notificationDownloadFailed(title),
syncPendingChanges(count), syncFailedChanges(count), syncDetails
```

## Phase 4 done when
- [ ] All section checklists ticked
- [ ] The airplane-mode week test (compressed to a day with clock manipulation in integration tests) passes
