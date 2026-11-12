# Phase 5: Podcasts

Goal: ABS podcast libraries feel as good as the book experience. Same player, same offline guarantees, plus episode-specific flows.

Branch: `phase-5-podcasts`

---

## 5.1 Data model additions (AccountDb)

| Table | Columns |
|---|---|
| `episodes` | id, itemId (podcast), title, subtitle, descriptionHtml, publishedAt, durationSec, season, episodeNumber, episodeType, audioMime, sizeBytes, chaptersJson, updatedAt |
| `podcast_prefs` | itemId, autoDownload (bool), keepLatest (int), notifyNew (bool), speed (nullable) |

`progress` already supports `episodeId`. Downloads already support `episodeId`.

### Acceptance
- [ ] Migration tested
- [ ] A podcast with 2,000 episodes loads its list from cache in under 300ms

---

## 5.2 Podcast library screens

Files: `lib/features/podcasts/ui/podcast_home.dart`, `podcast_library_screen.dart`, `show_screen.dart`, `episode_sheet.dart`

**Home (podcast library selected)**
- Hero: most recent in-progress episode.
- Shelves from `/personalized` (episode shelf ids such as continue-listening, listen-again, episodes-recently-added) plus a "Latest episodes" list from the recent-episodes endpoint.

**Library tab**
- Shows grid with an unplayed count badge per show.
- Sort: title, recently updated, date added.

**Show screen**
- Cover-tinted header, title, author, description (sanitized, collapsible), episode count.
- Actions: Play latest, Play all unplayed (builds the queue), Settings (5.4).
- Episode list: sort newest/oldest, filter all/unplayed/in progress/downloaded, group by season when seasons exist.
- Episode row: title, date, duration or time left, progress ring, download state, played check. Swipe actions: mark played/unplayed, download/delete, add to queue.

**Episode sheet**
- Title, date, duration, show notes rendered from sanitized HTML.
- Timestamps in show notes (`12:34`, `1:02:03`) become tappable and seek within that episode.
- Play, download, queue, mark played.

### Acceptance
- [ ] Timestamp links seek correctly, including when the episode is not yet playing (starts it at that time)
- [ ] Unplayed counts match the ABS web UI

---

## 5.3 Playback specifics

- Same `PlayerController.playItem(itemId, episodeId: ...)`. Play endpoint is the episode variant.
- Separate default speed for podcasts (Settings > Playback), and per-show speed via `podcast_prefs.speed`.
- Finishing an episode: mark played, then auto-play the next queue item, otherwise the next unplayed episode of the same show (setting, default on), otherwise stop.
- Lock screen and notification show the episode title as title and the show name as artist.

### Acceptance
- [ ] Episode progress syncs per episode, not per show
- [ ] Per-show speed overrides the podcast default

---

## 5.4 Per-show settings and automation (client side)

Sheet on the show screen:
- Auto-download new episodes on this device (off by default)
- Keep latest N downloaded (1, 3, 5, 10, all)
- Delete played episodes automatically (on by default when auto-download is on)
- Notify me about new episodes (off by default)
- Playback speed for this show

New episode detection:
- Socket `ItemUpdated` for a podcast item triggers an episode refetch and diff.
- Best-effort background refresh: `workmanager` on Android, `BGAppRefreshTask` on iOS, at most every 6 hours. Main isolate rules apply: background work only runs when it can use a valid access token; if the token is expired it skips and waits for the app to open (never refreshes outside the main isolate, see overview rule 10).
- Local notification "New episode: <title>" only for shows with notify on.

### Acceptance
- [ ] New episode added on the server shows up in the app within seconds while open
- [ ] Keep latest N never deletes an in-progress episode

---

## 5.5 Admin actions (permission gated)

Only shown when the current ABS user has the needed permissions (read from `/api/me`, verify permission names in `docs/abs-api.md`).

- **Add podcast**: search via the ABS podcast search endpoint, preview feed, choose library folder, add.
- **Check for new episodes** on the server.
- **Download episodes to server**: pick episodes not yet on the server, request server download.
- **Edit**: feed URL, server-side auto-download schedule (if the API supports it).

Every admin action shows a confirmation and the server's result. Errors show the server message.

### Acceptance
- [ ] A non-admin user never sees admin actions (widget test with permission fixtures)
- [ ] Adding a podcast from the app appears in the ABS web UI

---

## 5.6 Search integration

Phase 2 search gains Podcasts and Episodes result groups when a podcast library is searched.

---

## l10n keys added in Phase 5

```
podcastLatestEpisodes, podcastPlayLatest, podcastPlayAllUnplayed, podcastEpisodes(count), podcastUnplayed(count),
podcastSortNewest, podcastSortOldest, podcastFilterAll, podcastFilterUnplayed, podcastFilterInProgress,
podcastFilterDownloaded, podcastSeason(number), podcastEpisodeNumber(number), podcastMarkPlayed,
podcastMarkUnplayed, podcastShowNotes, podcastSettingsTitle, podcastAutoDownload, podcastKeepLatest(count),
podcastKeepAll, podcastDeletePlayed, podcastNotifyNew, podcastShowSpeed,
notificationNewEpisode(show, title), podcastAdminAdd, podcastAdminSearchHint, podcastAdminPreview,
podcastAdminChooseFolder, podcastAdminAdded(title), podcastAdminCheckNew, podcastAdminFoundNew(count),
podcastAdminDownloadToServer, podcastAdminEditFeed, podcastAdminConfirm, searchGroupPodcasts, searchGroupEpisodes,
settingsPodcastDefaultSpeed, settingsPodcastAutoPlayNextUnplayed
```

## Phase 5 done when
- [ ] All section checklists ticked
- [ ] Offline test from Phase 4 repeated with podcast episodes passes
