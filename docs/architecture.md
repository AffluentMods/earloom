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
| `AccountDb` | `account_<id>.sqlite` | everything cached for one ABS account: libraries, items, details, progress, series, authors, collections, playlists, shelves, filter data, cover colors, downloads, local sessions, outbox |
| `LocalDb` | `local.sqlite` | the On this device library: books, files, chapters, progress, bookmarks |

Tokens and custom headers live only in the platform secure store (`SecureStore`), never in SQLite.

All three live in Application Support. Schema changes need a migration and a migration test (drift schema dumps in `drift_schemas/`).

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
  - **downloaded server book:** file URIs from the account's downloads;
  - **streamed server book:** `POST /api/items/:id/play`, then the public session track URLs (no token, Range works), HLS for transcodes.
- `ProgressSink` per source receives position updates: local writes to `LocalDb`; server writes locally first, syncs the session every 15 s, falls back to the outbox and local sessions when offline.
- `TrackMap` is the only place that converts whole-book positions to (track, offset).

## 8. Local library

- **Import, not link:** the user picks audio files or a folder (system picker); files are copied into `<support>/local/<bookId>/`. This works the same on iOS and Android and survives the original files moving. (Linking a folder in place with Android's storage framework is a later option for very large libraries.)
- Grouping: one folder or one multi-file selection = one book, files ordered by track number, then disc, then natural filename order. A single M4B/M4A file is one book with embedded chapters.
- Metadata from tags (`audio_metadata_reader`): title, author, narrator, album, year, embedded cover, chapters. The user can edit everything afterwards.
- Durations from the tags, verified by the player on first play.

## 9. Screens

| Route | Screen | Notes |
|---|---|---|
| `/onboarding` | Welcome, then "Connect a server" or "Play files on this phone" | No permission prompts here |
| `/home` (tab) | Hero (last book, Resume), shelves | Library switcher when several libraries or sources |
| `/library` (tab) | Grid or list, sort, filters, Series, Authors, Collections, Playlists | Current library of the current source |
| `/search` (tab) | Online search, offline full-text search | Across the current source |
| `/you` (tab) | Downloads, Stats, Accounts, Settings, On this device | |
| `/book/:source/:id` | Book detail | Cover themed |
| `/player` | Now Playing | Full screen, swipe down to close |
| `/accounts/add` | Add a server, then sign in | |
| `/local/import` | Import from files | |

Mini player sits above the navigation bar on every tab when something is loaded.

## 10. Testing

- Unit tests for logic (token refresh, track map, progress rules, outbox, grouping of imported files).
- Widget tests for every screen state with fake repositories.
- Integration tests against the dev server in `tool/abs-dev` (tagged `server`, skipped when it is not running).
- The device test (`integration_test/app_launch_test.dart`) walks the main flows on an emulator and a simulator in CI.
- `tool/check.sh` must pass.
