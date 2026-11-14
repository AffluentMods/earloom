# Earloom architecture

How the app is put together, written for whoever works on it next. `docs/plan/` says what to build and in what order; this file says how the pieces fit. `docs/abs-api.md` is the truth about the server. If this file and the code disagree, fix one of them in the same change.

## 1. What the app is

An audiobook (and podcast) player with two kinds of **source**:

- **Audiobookshelf accounts**: one user on one self-hosted ABS server. Many accounts can exist, one is current.
- **On this device**: books the user imported from files on the phone. Works with no server and no account at all.

Anything the user can do with a book (browse, play, resume, bookmark, chapters, sleep timer, speed) works the same for both. Server books can additionally be downloaded for offline use, sync progress, and show up in stats on the server.

## 2. Design direction

- **Tone:** calm, comfortable density, cover-driven. The app shell is neutral (dark by default, light and AMOLED available); color comes from the book.
- **The one memorable thing:** the cover of the book you are looking at or listening to colors the whole screen, animating as you move between books. Now Playing should feel like holding the book.
- **Closest references:** Apple Books and Apple Music Now Playing, ShelfPlayer, Pocket Casts, BookPlayer (for local files).
- **Type:** Newsreader (serif) for book titles and screen titles, Inter for everything else. Tokens in `lib/app/theme/tokens.dart`, theme in `app_theme.dart`. No raw colors in features: the shell scheme or the cover scheme (`CoverTheme`, `cover_surfaces.dart`).
- **Words, not abbreviations:** "3 hr 12 min left", "Downloaded", "Sign in again to sync". Every string through `lib/l10n/app_en.arb`.
- **States:** every screen designs loading (skeletons shaped like the content), empty (one sentence plus one action), offline with cache (content plus a quiet banner), offline without cache, and error (plain words plus "Copy details").
- **Motion:** 150 to 300 ms, purposeful: cover hero from lists to detail and from the mini player to Now Playing, theme cross-fades between covers, spring sheets. Reduce motion turns the ambient gradient and scale effects off.
- **Haptics:** light on play, pause, skip and bookmark; selection ticks on chapter boundaries while scrubbing.

## 3. Layers

```
UI (features/*/ui)        reads providers, never touches the network or the database directly
Providers (Riverpod)      compose repositories, expose AsyncValue / streams
Repositories              one per concern and source; stream from the database, refresh from the network
Sources                   AbsSource (per account) and LocalSource, behind the LibrarySource interface
Core                      net (dio, auth), db (drift), storage (secure store), sync (outbox), player engine
```

Rule: **the UI reads the database.** Repositories write what the server says into the database and the UI watches the result. A screen never waits on the network to render, which is what makes offline and fast start-up work.

## 4. Identity of things

- `SourceId`: `local` or `abs:<accountId>`.
- `ItemRef`: a book or podcast in a source, `(SourceId source, String itemId, String? episodeId)`. Encoded in routes as `/book/<source>/<itemId>`; the deep link `earloom://item/<id>` means "item `<id>` in the current account".
- Progress, bookmarks, downloads and cover colors are always keyed by `ItemRef`.

## 5. Databases

| Database | File | Holds |
|---|---|---|
| `GlobalDb` | `global.sqlite` | app settings, accounts list, device id, recently played across sources |
| `AccountDb` | `account_<id>.sqlite` | everything cached for one ABS account: libraries, items, details, progress, series, authors, collections, playlists, shelves, filter data, cover colors, podcast episodes and this phone's per-show settings (`podcast_prefs`) |
| `OfflineDb` | `offline.sqlite` | downloads and their files, item snapshots for offline playback, local listening sessions, the outbox; every row carries its `accountId` |
| `LocalDb` | `local.sqlite` | the On this device library: books, files, chapters, progress, bookmarks |

`OfflineDb` is one database for all accounts (Phase 4 decision, unlike the plan's "in AccountDb"): a book downloaded in account A keeps playing, recording its listening and flushing its outbox while account B is current, and only the current account's `AccountDb` is open. Removing an account deletes its rows (`OfflineDb.deleteAccount`) and its `accounts/<id>/` folder.

Tokens and custom headers live only in the platform secure store (`SecureStore`), never in SQLite.

All four live in Application Support. Schema changes need a migration and a migration test (drift schema dumps in `drift_schemas/`).

## 6. Networking and auth (ABS)

From `docs/abs-api.md` section 18, which overrides the original plan:

- One `Dio` per account with `AuthInterceptor` (adds `Authorization: Bearer`, custom headers) and a bare `Dio` for refresh.
- `TokenRefresher`: single flight per account. Persist the new refresh token before using the new access token. **401 from `/auth/refresh` = sign in again; 429 = wait (`RateLimit-Reset`), never sign out; network error = stay signed in, offline.**
- Proactive refresh from the JWT `exp`: under 2 minutes left, on resume, before playback and downloads.
- `/api/authorize` is `POST`. Never use `?token=` or the legacy `user.token`.
- Rate limit is 40 auth requests per IP per 10 minutes, shared: keep refreshes rare.
- Socket: emit `auth` with the access token, expect `init`; progress arrives as `user_item_progress_updated` (playback) and `user_updated` (manual edits). Re-auth after reconnect.
- Only the main isolate talks to servers.

## 7. Playback

- One `AudioHandler` (audio_service) owns one `just_audio` player. The app talks only to `PlayerController`.
- A `PlayableBook` is source-agnostic: tracks (`Uri` plus optional headers, start offset, duration, mime), chapters, start position, title, author, cover. Built by:
  - **local:** file URIs from `LocalDb`;
  - **downloaded server book:** file URIs from `download_files` and the track map from the saved snapshot, never the server (`DownloadedPlayback`);
  - **streamed server book:** `POST /api/items/:id/play`, then the public session track URLs (no token, Range works), HLS for transcodes.
- `ProgressSink` per source receives position updates: local writes to `LocalDb`; a streamed server book syncs its session every 15 s and, when a sync cannot reach the server (or the server forgot the session), moves its listening into a local session from that moment until a sync gets through again; a downloaded book always records a local session and sends its position straight to the server when it answers, else queues it.

## 7a. Downloads, offline and the outbox (Phase 4)

- **Downloads** (`features/downloads/data`): `DownloadManager` is the interface the UI uses; `AbsDownloadManager` implements it on top of a `DownloadTransport` (background_downloader in the app, a fake in tests). Before any audio file is queued the expanded item is saved as a snapshot and the cover as `cover.img`. Each audio file is one background task with headers captured when it is queued; a 401 makes the main isolate refresh and queue the remaining files again. The downloader's native holding queue runs at most two files at once (so at most two books). Finished files are checked against the size in the snapshot.
- **On disk:** `<support>/accounts/<accountId>/downloads/<itemId>/[<episodeId>/]track_000.<ext>`. The database stores paths relative to Application Support, because the absolute path changes between launches on iOS. iOS excludes the folder and every file from iCloud backup; Android's backup rules exclude `accounts/`.
- **Local sessions** (`OfflineSessionRecorder`): opened on the first report, updated every report, closed on stop or finish, then queued once for `/api/session/local-all` with their final values (the server moves a re-sent session to a new day). Sessions left open by a kill are closed at the next start.
- **Outbox** (`core/sync`): progress (coalesced to the newest per item), finished flags, bookmark changes, playlist edits and local sessions, sent in order per item. Before sending progress the flusher reads the server's progress and skips ours when the server's is newer. Failures back off 30 s, 2 min, 10 min, then hourly; a 4xx other than 401 becomes a dead letter shown in a quiet "could not sync" row with details. Local sessions go 25 per request.
- **Reachability** (`core/net/reachability.dart`): online means the current server answers `/ping` within 3 s. Checked on account change, connectivity change, app foreground, after failures, and every 60 s while offline. The offline banner sits on top of the tabs and shows only while the server does not answer.
- `TrackMap` is the only place that converts whole-book positions to (track, offset).

## 7b. Podcasts (Phase 5)

- **Data:** `AbsPodcastRepository` (`features/podcasts/data`) next to the library repository, over the same AccountDb. Episodes live in their own table (`episodes`), written from the expanded show, the socket, episode shelves and `recent-episodes`; the show's cached detail JSON keeps no episodes. `items.num_episodes` gives the unplayed count before a show's episodes are cached; after, it is counted per episode (not finished), which is what the server's web app shows.
- **Screens:** with a podcast library selected, Home is `PodcastHome` (hero = latest episode in progress, the server's episode shelves, Latest episodes) and Library is `PodcastLibraryScreen` (shows with unplayed badges). The show screen and the episode sheet are reached from anywhere through `BrowseNav.show`, `BrowseNav.open` and `showEpisodeSheet`.
- **Playback:** an episode is an `ItemRef` with an `episodeId`; `/play/:episodeId` is used for it. The player asks `EpisodeHooks` (set by `podcastPlaybackBridgeProvider`) for the show speed and, when an episode ends with an empty Up next, the next unplayed episode of the show. Episode speed: the show's (`podcast_prefs.speed`), else the podcast default (`PlayerPrefs.podcastSpeed`). The lock screen shows the episode title and the show as the artist.
- **New episodes:** found when the socket sends the updated show (`item_updated` carries every episode), when a show is refreshed, and from shelves. The first look at a show announces nothing. `PodcastAutomation` then downloads (reason `podcast`) and notifies (local notifications, `flutter_local_notifications`) per the show's settings, and keeps automatic downloads within "keep latest" and "remove played", never removing an episode in progress. There is no background refresh: it would need a token outside the main isolate (Phase 5 notes).
- **Admin actions** (check new, download to the server, add podcast) show for `admin` and `root` users; Edit feed also for users with the update permission. The user type and permissions are kept from `/api/me` (`SyncMeta` key `me.access`).

## 8. Local library

- **Import, not link:** the user picks audio files or a folder (system picker); files are copied into `<support>/local/<bookId>/`. This works the same on iOS and Android and survives the original files moving. (Linking a folder in place with Android's storage framework is a later option for very large libraries.)
- Grouping: one multi-file selection = one book; a picked folder = one book of the audio directly in it plus any "CD 1" / "Disc 2" / "Part 3" sub-folders, and every other sub-folder with audio is a book of its own. Files are ordered by disc (the tag, else the part folder's number), then track number, then natural filename order ("2" before "10"). A single M4B/M4A file is one book with embedded chapters.
- Metadata from tags (`audio_metadata_reader`, plus our own readers in `features/local_library/data/tags/` for what it misses: MP4 album artist, composer, description and QuickTime chapter tracks, ID3 `CHAP` chapters, MP3 and raw AAC durations): title (album, then folder, then file name), author (album artist, then artist), narrator (narrator tag, then composer), year, cover (embedded, else cover.jpg/folder.jpg/a single image), chapters (embedded, else one per file). The user can edit everything afterwards.
- On disk every name is our own (`track_000.mp3`, `cover_<time>.jpg`), never one from tags or the picked files. A book is copied into a staging folder and only moved into place, with its rows written in one transaction, once complete; a cancel or failure removes it.
- Folder picking: Android reads the Storage Access Framework tree through the app's own channel (`SafChannel.kt`), with no storage permission; iOS keeps the security-scoped folder open while importing (`FolderAccessPlugin.swift`).
- Durations from the tags, verified by the player on first play.

## 9. Screens

| Route | Screen | Notes |
|---|---|---|
| `/onboarding` | Welcome, then "Connect a server" or "Play files on this phone" | No permission prompts here |
| `/home` (tab) | Hero (last book, Resume), shelves | Library switcher when several libraries or sources |
| `/library` (tab) | Grid or list, sort, filters, Series, Authors, Collections, Playlists | Current library of the current source |
| `/search` (tab) | Online search, offline full-text search | Across the current source |
| `/you` (tab) | Downloads, Stats, Accounts, Settings, On this device | |
| `/you/downloads` | Downloads: active, on this phone, storage | Settings at `/you/downloads/settings` |
| `/book/:source/:id` | Book detail | Cover themed. `:source` is the encoded source key (`local`, `abs%3A<accountId>`) |
| `/show/:source/:id` | Podcast show | Cover themed; episodes open in the episode sheet. A podcast reached through `/book` or `/item` shows this screen too |
| `/series/:source/:id`, `/author/:source/:id` | Series, author | For On this device the id is the name |
| `/filtered/:source/:library/:kind/:value` | Books of one library with one filter | Narrator (no narrator entity on the server), genre, tag |
| `/collection/:source/:id`, `/playlist/:source/:id` | Collection (read only), playlist (edit) | Server only |
| `/item/:id` | Book detail in the current account | Target of `earloom://item/<id>` |
| `/player` | Now Playing | Full screen, swipe down to close |
| `/accounts/add` | Add a server, then sign in | |
| `/local/import` | Import from files | |

Mini player sits above the navigation bar on every tab when something is loaded.

The browse routes (book, series, author, filtered, collection, playlist) also exist under `/home`, `/library` and `/search`, so a book opened from a tab keeps the tab bar and the mini player; `BrowseNav` picks the right base. Sheets open on the root navigator, above both.

Browsing reads one source-agnostic layer, `lib/features/library/data/library_providers.dart`: the same providers answer for the current server account and for On this device. Server lists are cached in AccountDb (`CatalogDao`) and synced by `AbsLibraryRepository`: a full library sync at most every 6 hours (or on pull to refresh), shelves after 2 minutes, item detail after 10 minutes, lists after 30 minutes; socket events update the cache live. Filters and sort run over the cache, so they also work offline.

## 10. Testing

- Unit tests for logic (token refresh, track map, progress rules, outbox, grouping of imported files).
- Widget tests for every screen state with fake repositories.
- Integration tests against the dev server in `tool/abs-dev` (tagged `server`, skipped when it is not running).
- The device test (`integration_test/app_launch_test.dart`) walks the main flows on an emulator and a simulator in CI.
- `tool/check.sh` must pass.
