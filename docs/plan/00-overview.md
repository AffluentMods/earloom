# Earloom: Audiobookshelf client, build plan

Read this file first. Every phase doc in this folder assumes the rules and structure defined here.

## Identity

| Item | Value |
|---|---|
| App name | Earloom |
| Store subtitle | "for Audiobookshelf" (the name itself never contains "ABS" or "Audiobookshelf") |
| App id / Dart package | `earloom` |
| Bundle id (iOS) and application id (Android) | `com.affluentlabs.earloom` (the same prefix as ZestSSH, `com.affluentlabs.zestssh`, and Recipe Spellbook, `com.affluentlabs.recipespellbook`). It cannot change after the first store upload. Kotlin package `com.affluentlabs.earloom`. |
| URL scheme | `earloom` (OIDC redirect `earloom://oauth`, deep links `earloom://item/<id>`) |
| Repo | `earloom` (public) |
| Companion server | Earloom Server, repo `earloom-server` |
| Publisher | Affluent Labs LLC. No dedicated domain: support, privacy and docs pages live under affluentlabs.dev. |

## Product in one paragraph

A polished, cover-art driven audiobook and podcast player for people who self-host Audiobookshelf (ABS). Flutter, one codebase for Android and iOS. ABS stays the backend: it owns the library, metadata, progress and stats. This app is a client that makes listening feel premium, works fully offline, and integrates with the car, lock screen, widgets and watch. Published by Affluent Labs: free, open source (GPL-3.0), no purchases, no ads, no tracking.

## Positioning (why this exists)

- iOS already has decent ABS clients (ShelfPlayer, Plappa, Still, SoundLeaf). Android has very few polished ones (Lissen, Buchable, Vaani). Nothing polished covers both platforms with one design.
- Our angle: one premium design on both platforms, cover-driven color, best-in-class offline, CarPlay and Android Auto, stats people want to share, free and open source.
- Plappa gets dinged in reviews for locking downloads behind a paywall. Everything in this app is free.

## License (decided)

- GPL-3.0-or-later, public repo from the first commit, copyright Affluent Labs LLC.
- Plus an **app store exception** (an additional permission under GPLv3 section 7, text in `LICENSE-EXCEPTION.md`) that allows distribution through the Apple App Store and Google Play despite their terms. Every contribution is accepted under GPL-3.0 with that exception (stated in `CONTRIBUTING.md`, DCO sign-off on commits).
- Companion server: Earloom Server (separate repo, AGPL-3.0).
- Code is written on Windows. iOS and macOS builds run on the Mac mini.

## Global rules (apply to every phase)

1. **No hardcoded user-facing strings.** Every string goes through l10n keys in `lib/l10n/app_en.arb`. Each phase doc lists the keys it adds. Plurals and durations use ICU syntax.
2. **No em dashes anywhere**: UI strings, .arb files, code comments, docs, store copy. Use commas, colons, periods or parentheses.
3. **No hardcoded colors.** All color comes from theme tokens (`lib/app/theme/tokens.dart`) or the active cover `ColorScheme`. No `Color(0xFF...)` in feature code.
4. **Identifiers never use the developer's real name.** Test accounts, sample configs and usernames use `affluent`.
5. **Tokens never appear in URLs or logs.** Auth goes in headers. The HTTP logger redacts `Authorization`, `x-refresh-token`, cookies and passwords.
6. **Read, do not copy, other projects' code.** ABS, the official ABS app and other clients are GPL-family licensed, but their authors never granted our app store exception, so copying their code would break store distribution. Read them to learn API behavior only.
7. **Verify, do not trust the API docs.** api.audiobookshelf.org states it is out of date and no longer maintained. The source of truth is the ABS server source plus a live server. See Phase 0.
8. **Offline is a first-class state,** not an error. Every screen must render from local cache when the server is unreachable.
9. **Every release build is obfuscated:** `--obfuscate --split-debug-info=build/debug-symbols/<version>`.
10. **Main isolate owns auth and network.** Widget extensions, background callbacks and other isolates read cached data only. They never refresh tokens (refresh tokens rotate, two refreshers will log the user out).
11. **Package hygiene.** Before adding any package listed in these docs, check it is maintained and supports current Flutter stable. If it is abandoned, stop and propose an alternative instead of forcing it in.
12. **Each phase ends green:** `flutter analyze` clean, tests pass, the phase acceptance checklist is ticked in the PR description.

## Stack

| Concern | Choice | Notes |
|---|---|---|
| Framework | Flutter stable, Dart 3 | Android 8+ (API 26), iOS 17+ |
| State | `flutter_riverpod` (+ `riverpod_generator`) | |
| Routing | `go_router` with `StatefulShellRoute` | Tabs keep their own stacks |
| Models | `freezed` + `json_serializable` | |
| HTTP | `dio` | Custom auth interceptor, see Phase 1 |
| Realtime | `socket_io_client` | ABS uses socket.io |
| Local DB | `drift` (SQLite) | One global DB + one DB per account |
| Secrets | `flutter_secure_storage` | Tokens, custom headers |
| Audio | `just_audio` + `audio_service` + `audio_session` | Media session, lock screen, Android Auto |
| Downloads | `background_downloader` | Background, resumable, headers |
| Images | `cached_network_image` (with auth headers) | Covers requested pre-sized |
| Cover color | `ColorScheme.fromImageProvider` / `material_color_utilities` | Cached per item |
| OIDC | `flutter_web_auth_2` + PKCE | Own redirect URI, never `audiobookshelf://oauth` |
| Widgets | `home_widget` + native WidgetKit / Glance | |
| Live Activities | `live_activities` or native ActivityKit | |
| CarPlay | Native Swift scene + MethodChannel | See Phase 6 |
| Fonts | Bundled assets, no runtime font fetching | Privacy |

## Architecture

```
            UI (features/*/ui)               CarPlay / Android Auto / Widgets
                    |                                     |
            Riverpod providers                    platform/ bridges
                    |                                     |
        Repositories (features/*/data)  <----->  PlayerController (audio_service handler)
            |                  |                          |
      AccountDb (drift)    AbsClient (dio)          TrackMap / SessionSync / SleepTimer
            |                  |                          |
       Outbox table  ---->  ABS server  <-----  socket.io (progress, item updates)
```

Data flow rule: UI reads from the DB (streams). Repositories fetch from ABS and write to the DB. UI never awaits the network to render. This is what makes offline and fast startup work.

## Folder structure

Starting skeleton. Each phase doc lists any extra files it adds.

```
lib/
  main.dart
  app/
    app.dart                      # MaterialApp.router, theme, l10n
    router.dart                   # go_router config, shell routes
    theme/
      tokens.dart                 # spacing, radii, durations, neutral palette
      app_theme.dart              # light, dark, AMOLED ThemeData builders
      cover_scheme.dart           # cover -> ColorScheme, cached
      typography.dart
  core/
    net/
      abs_client.dart             # typed API wrapper
      auth_interceptor.dart
      token_refresher.dart        # single-flight refresh
      server_probe.dart           # /ping, /status, version gating
      redacting_logger.dart
    socket/abs_socket.dart
    db/
      global_db.dart              # accounts, app settings
      account_db.dart             # per-account cache
      tables/                     # one file per table
    storage/secure_store.dart
    sync/                         # outbox + flusher (Phase 4)
    ui/                           # shared states: empty, error, offline (Phase 8)
    util/
      duration_format.dart
      html_sanitize.dart
  features/
    accounts/{data,ui}/
    home/{data,ui}/
    library/{data,ui}/
    item_detail/ui/
    search/{data,ui}/
    player/
      audio_handler.dart          # BaseAudioHandler implementation
      player_controller.dart
      track_map.dart
      session_sync.dart
      progress_resolver.dart
      sleep_timer.dart
      ui/{now_playing_screen,mini_player,chapters_sheet,speed_sheet,sleep_sheet,bookmarks_sheet}.dart
    downloads/{data,ui}/
    podcasts/{data,ui}/
    stats/{data,ui}/
    settings/ui/
    onboarding/ui/
  platform/
    carplay_bridge.dart
    widget_bridge.dart
    live_activity_bridge.dart
    shortcuts_bridge.dart
  l10n/
    app_en.arb
ios/
  Runner/CarPlay/                 # Swift CarPlay scene
  NowPlayingWidget/               # WidgetKit extension
  Runner/PrivacyInfo.xcprivacy
android/app/src/main/
  kotlin/<package>/widget/        # Glance widgets
  res/xml/automotive_app_desc.xml
tool/abs-dev/
  docker-compose.yml              # local ABS for dev and integration tests
  seed/                           # LibriVox public-domain fixtures
test/ integration_test/
docs/
  plan/                           # these files
  abs-api.md                      # produced in Phase 0
```

## ABS API map (verify every row in Phase 0)

> **Verified in Phase 0.** The table below is the plan's original guess. What the server really does is in [`docs/abs-api.md`](../abs-api.md), and every place the plan was wrong or incomplete is listed in its section 18, "Differences from the plan". Where the two disagree, `docs/abs-api.md` wins.

Minimum supported server: **2.26.0** (new JWT auth). Show a non-blocking warning to admin users on servers below **2.36.0** (fixes CVE-2026-73085, refresh tokens accepted as access tokens; Phase 0 confirms the CVE id and the fixed version against the ABS release notes and corrects both here if they differ).

| Area | Expected endpoint | Source to verify |
|---|---|---|
| Reachability | `GET /ping`, `GET /status` (isInit, authMethods, serverVersion) | `server/Server.js` |
| Login | `POST /login` + header `x-return-tokens: true` returns `user.accessToken`, `user.refreshToken` | `server/Auth.js`, `server/auth/` |
| Refresh | `POST /auth/refresh` + header `x-refresh-token`; refresh tokens rotate | same |
| Logout | `POST /logout` + `x-refresh-token` | same |
| OIDC | `GET /auth/openid?...code_challenge...redirect_uri=...` then `/auth/openid/callback` | same + official app source |
| Me | `GET /api/authorize`, `GET /api/me`, `GET /api/me/items-in-progress` | `MeController.js` |
| Libraries | `GET /api/libraries`, `/api/libraries/:id/items`, `/personalized`, `/series`, `/authors`, `/collections`, `/search`, `/filterdata` | `LibraryController.js` |
| Items | `GET /api/items/:id?expanded=1&include=progress,...`, `GET /api/items/:id/cover?width=&format=` | `LibraryItemController.js` |
| Play | `POST /api/items/:id/play` and `/play/:episodeId` returns PlaybackSession | `LibraryItemController.js`, `SessionController.js` |
| Stream | `GET /public/session/:sessionId/track/:index` (no token in URL) | `server/routers/PublicRouter.js` |
| Session | `POST /api/session/:id/sync`, `POST /api/session/:id/close` | `SessionController.js` |
| Offline sessions | `POST /api/session/local`, `POST /api/session/local-all` | `SessionController.js` |
| Progress | `PATCH /api/me/progress/:itemId[/:episodeId]`, `PATCH /api/me/progress/batch/update` | `MeController.js` |
| Bookmarks | `POST`/`PATCH /api/me/item/:id/bookmark`, `DELETE /api/me/item/:id/bookmark/:time` | `MeController.js` |
| Stats | `GET /api/me/listening-stats`, `GET /api/me/listening-sessions` | `MeController.js` |
| Playlists | `/api/playlists*` | `PlaylistController.js` |
| Podcasts | `/api/libraries/:id/recent-episodes`, `/api/podcasts/*`, `/api/search/podcast` | `PodcastController.js` |
| Socket | socket.io, `auth` event with access token; `user_item_progress_updated`, `item_updated`, `item_added`, `item_removed` | `server/SocketAuthority.js` |

Server source: `github.com/advplyr/audiobookshelf` (read the tag matching the dev server). Official app for flow reference: `github.com/advplyr/audiobookshelf-app`. ABS third-party client rules: `audiobookshelf.org/faq/app`.

## Design direction: cover-art driven

- App shell is neutral (dark by default, light and AMOLED available). Color comes from the book.
- Item detail, Now Playing, mini player and the Home hero card take their `ColorScheme` from the current cover, animated on change (`AnimatedTheme`, 300ms).
- Book titles use a bundled serif display face; UI text uses a bundled sans. Suggested pair: Newsreader (titles) + Inter (UI). Both are OFL licensed.
- Covers are the hero: large, soft shadow, rounded 12 to 16. Never stretched; letterbox square-ish covers on a palette background.
- Motion: cover hero transition mini player to Now Playing, spring-based sheet drags, haptics on play, skip and bookmark.
- Contrast: text on palette colors must meet WCAG AA. Use the scheme's `on*` roles, never raw palette swatches for text.

## Phase index

| # | Doc | Depends on | Outcome |
|---|---|---|---|
| 0 | `01-phase0-recon-scaffold.md` | | Verified API notes, dev ABS server, app skeleton, theme, l10n |
| 1 | `02-phase1-accounts-auth.md` | 0 | Add server, login (local + OIDC), token refresh, multi-account, socket |
| 2 | `03-phase2-library.md` | 1 | Home, library, series, authors, collections, playlists, search, item detail |
| 3 | `04-phase3-player.md` | 2 | Full player, session sync, chapters, sleep timer, bookmarks, queue |
| 4 | `05-phase4-offline.md` | 3 | Downloads, offline sessions, outbox, storage management |
| 5 | `06-phase5-podcasts.md` | 3, 4 | Podcast libraries, episodes, auto-download, admin actions |
| 6 | `07-phase6-system-integration.md` | 3, 4 | Lock screen polish, Android Auto, CarPlay, widgets, Live Activities, shortcuts, AirPlay |
| 7 | `08-phase7-stats.md` | 3 | Stats screens, streaks, year in review |
| 8 | `09-phase8-settings-polish.md` | all above | Settings, onboarding, accessibility, empty/error states, performance |
| 9 | `10-phase9-release.md` | 8 | Open source release, store listings, F-Droid, privacy, demo server, release pipeline, security review |
| 10 | `11-phase10-extended.md` | 9 | Apple Watch, Wear OS, Chromecast |
| 11 | `12-phase11-server-integration.md` | 9, Earloom Server Phase 4 | Server status, requests, activity, phone import |

Parked for after 1.0 (do not build yet): ebook reader (ABS serves epub/pdf), sharing via ABS share links, desktop builds.

## How to work these docs

- Do one phase per branch: `phase-N-short-name`.
- Start each phase by re-reading this overview and `docs/abs-api.md`.
- If a doc conflicts with what the live server does, the server wins: update `docs/abs-api.md`, note the deviation in the PR, keep going.
- If a decision is marked **DECIDE**, stop and ask the owner before implementing that item. Everything else, make the reasonable call and note it in the PR.
