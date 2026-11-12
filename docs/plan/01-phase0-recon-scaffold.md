# Phase 0: API recon and app scaffold

Goal: a verified picture of the ABS API, a local ABS server to develop against, and an empty app shell with theme, l10n and routing in place. No features yet.

Branch: `phase-0-scaffold`

---

## 0.1 Local ABS dev server

Files:
- `tool/abs-dev/docker-compose.yml`
- `tool/abs-dev/docker-compose.short-tokens.yml` (override)
- `tool/abs-dev/seed/README.md`
- `tool/abs-dev/.gitignore` (ignore `data/` and downloaded audio)

```yaml
# tool/abs-dev/docker-compose.yml
services:
  abs:
    image: ghcr.io/advplyr/audiobookshelf:<PIN_CURRENT_RELEASE>  # must be >= 2.36.0
    container_name: abs-dev
    ports:
      - "13378:80"
    volumes:
      - ./data/config:/config
      - ./data/metadata:/metadata
      - ./seed/audiobooks:/audiobooks
      - ./seed/podcasts:/podcasts
    restart: unless-stopped
```

```yaml
# tool/abs-dev/docker-compose.short-tokens.yml
# Forces fast expiry so token refresh paths get exercised constantly.
services:
  abs:
    environment:
      ACCESS_TOKEN_EXPIRY: "60"
      REFRESH_TOKEN_EXPIRY: "600"
```

Seed content (public domain only, from LibriVox). `seed/README.md` documents a script or manual steps that fetch:
- A multi-file MP3 book (many tracks, chapters = files).
- A single-file M4B with embedded chapters.
- Two books in the same series with sequence numbers (to test series ordering).
- A book with a long description containing HTML.
- One podcast feed with a permissive license (or skip podcasts in seed and test against the owner's server).

Users on the dev server: `root` (admin) and `affluent` (normal user, no delete or upload permission). Passwords live in `tool/abs-dev/.env.local` (gitignored).

### Acceptance
- [ ] `docker compose up -d` in `tool/abs-dev` gives a working ABS on `http://localhost:13378`
- [ ] Seed books scan and show chapters in the ABS web UI
- [ ] Short-token override verified: access token expires after 60s
- [ ] No copyrighted audio committed anywhere in the repo

---

## 0.2 Verify the API, write `docs/abs-api.md`

The public API docs are out of date. For every row in the API map in `00-overview.md`:

1. Find the route in the ABS server source at the same tag as the dev server (`server/routers/ApiRouter.js`, `server/routers/PublicRouter.js`, `server/Auth.js` and `server/auth/`, controllers).
2. Call it against the dev server with curl or a small Dart script in `tool/api_probe.dart`.
3. Record in `docs/abs-api.md`: method, path, required headers, request body, response shape (trimmed), error codes, permission requirements, and anything surprising.
4. Save a trimmed response as a fixture: `test/fixtures/abs/<area>_<name>.json`. Strip tokens, emails and server URLs.

Specific questions to answer in `docs/abs-api.md` (these drive later phases):
- Does `/status` return `serverVersion` and `authMethods`? Exact shape of OIDC button config (`authFormData`)?
- Login with `x-return-tokens: true`: exact field names for access and refresh tokens. Is legacy `user.token` still present?
- Refresh: does it need a body, or only the `x-refresh-token` header? Does it return a new refresh token every time (rotation)? What happens if the same refresh token is used twice?
- OIDC mobile flow: required query params on `/auth/openid` (`code_challenge`, `code_challenge_method`, `redirect_uri`, `client_id`, `response_type`, `state`), how the callback returns tokens, and whether `x-return-tokens` applies. Where admins whitelist mobile redirect URIs in ABS settings.
- `POST /api/items/:id/play` request body fields (`deviceInfo`, `forceDirectPlay`, `forceTranscode`, `supportedMimeTypes`, `mediaPlayer`) and the PlaybackSession response (`id`, `audioTracks[].contentUrl`, `startOffset`, `duration`, `mimeType`, `chapters`, `currentTime`).
- Does `GET /public/session/:id/track/:index` stream without auth? Does it support HTTP range requests (needed for seeking)? When does it stop working (after session close)?
- Session sync body (`currentTime`, `timeListened`, `duration`) and how often the official app syncs.
- Local session shape for `POST /api/session/local` and `/local-all`, and how the server merges them into progress.
- Does the cover endpoint require auth? Supported query params (`width`, `height`, `format`, `raw`)?
- Socket: auth event name and payload under the new JWT system, what happens when the access token expires mid-connection, event names and payloads for progress and item changes.
- Download endpoint for individual audio files (for offline), and whether it needs auth.
- Listening stats shape (`totalTime`, `items`, `days`, `dayOfWeek`, `today`, `recentSessions`).

### Acceptance
- [ ] `docs/abs-api.md` covers every API map row with verified details and a "Verified against ABS vX.Y.Z" header
- [ ] Every question above has an answer or an explicit "not supported" note
- [ ] Fixtures exist for: status, login, authorize, libraries, library items page, personalized, item expanded (book), item expanded (podcast), play session, listening stats, filterdata, search
- [ ] No secrets in fixtures (grep for `eyJ` returns nothing)

---

## 0.3 Flutter project

```
flutter create --org com.affluentlabs --project-name earloom --platforms android,ios .
```

- Set `com.affluentlabs.earloom` on both platforms. Min SDK 26, iOS deployment target 17.0.
- Open source setup: `LICENSE` (GPL-3.0), `LICENSE-EXCEPTION.md` (app store exception), `README.md`, `CONTRIBUTING.md` (DCO, coding rules, Windows dev setup, Mac mini for iOS builds), `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue and PR templates. SPDX header `// SPDX-License-Identifier: GPL-3.0-or-later` on every Dart, Swift and Kotlin file; `tool/check.sh` fails on files missing it.
- Secrets that must never be committed (signing keys, store credentials, `key.properties`, `.env`) are gitignored from the first commit, with a pre-commit secret scan (gitleaks).
- Add packages from the overview stack table. Pin versions. Check each is maintained (rule 11).
- `analysis_options.yaml`: `flutter_lints` plus `prefer_const_constructors`, `avoid_print`, `unawaited_futures`, `always_declare_return_types`.
- Create the full folder tree from the overview with placeholder files so later phases only fill in.

### `tool/check.sh`

Runs locally and in CI. Fails on any violation.

```bash
#!/usr/bin/env bash
set -euo pipefail
flutter analyze
flutter test
# Rule 2: no em dashes in source, l10n or docs
if grep -rn $'\xe2\x80\x94' lib/ docs/ ios/Runner ios/NowPlayingWidget android/app/src 2>/dev/null; then
  echo "Em dash found"; exit 1
fi
# Rule 3: no raw colors in feature code
if grep -rnE 'Color\(0x[0-9A-Fa-f]{8}\)' lib/features lib/platform; then
  echo "Hardcoded color in feature code"; exit 1
fi
# Rule 1: crude check for string literals in Text widgets
if grep -rnE "Text\(\s*'[^']" lib/features; then
  echo "Possible hardcoded UI string"; exit 1
fi
echo "OK"
```

### Acceptance
- [ ] App builds and launches on an Android emulator and an iOS simulator
- [ ] `tool/check.sh` passes
- [ ] Folder tree matches the overview

---

## 0.4 Localization

Files: `l10n.yaml`, `lib/l10n/app_en.arb`

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n/gen
nullable-getter: false
```

Seed keys (Phase 0 only):

```json
{
  "@@locale": "en",
  "appName": "Earloom",
  "tabHome": "Home",
  "tabLibrary": "Library",
  "tabSearch": "Search",
  "tabYou": "You",
  "durationHoursMinutes": "{hours, plural, =0{} =1{1 hr } other{{hours} hrs }}{minutes, plural, =1{1 min} other{{minutes} min}}",
  "@durationHoursMinutes": { "placeholders": { "hours": {"type": "int"}, "minutes": {"type": "int"} } },
  "timeLeft": "{duration} left",
  "@timeLeft": { "placeholders": { "duration": {"type": "String"} } },
  "genericRetry": "Try again",
  "genericCancel": "Cancel",
  "genericSave": "Save",
  "offlineBanner": "Offline. Showing what is on this device."
}
```

`lib/core/util/duration_format.dart` turns a `Duration` into localized strings using these keys. No string concatenation of units.

### Acceptance
- [ ] `flutter gen-l10n` runs clean
- [ ] Tabs render localized labels
- [ ] Duration formatter has unit tests (0 min, 59 min, 1 hr, 1 hr 1 min, 25 hrs 3 min)

---

## 0.5 Theme tokens and cover-driven color

Files: `lib/app/theme/tokens.dart`, `lib/app/theme/app_theme.dart`, `lib/app/theme/cover_scheme.dart`, `lib/app/theme/typography.dart`, `assets/fonts/`

```dart
// lib/app/theme/tokens.dart
abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0;
}
abstract final class Radii {
  static const cover = 14.0, card = 20.0, sheet = 28.0, pill = 999.0;
}
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 500);
}
/// Neutral seed for the app shell. The only raw color literal allowed in lib/.
abstract final class NeutralSeed {
  static const color = Color(0xFF6B6F80);
}
```

```dart
// lib/app/theme/cover_scheme.dart
/// Returns a ColorScheme derived from a book cover.
/// Cached by (itemId, coverUpdatedAt, brightness) in AccountDb.cover_colors
/// so the second open is instant and works offline.
class CoverSchemeService {
  CoverSchemeService(this._db);
  final AccountDb _db;

  Future<ColorScheme> schemeFor({
    required String itemId,
    required int coverUpdatedAt,
    required ImageProvider cover,
    required Brightness brightness,
  }) async {
    final cached = await _db.coverColors.lookup(itemId, coverUpdatedAt);
    if (cached != null) {
      return ColorScheme.fromSeed(
        seedColor: Color(cached.seedArgb),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
    }
    final scheme = await ColorScheme.fromImageProvider(
      provider: cover,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    await _db.coverColors.put(itemId, coverUpdatedAt, scheme.primary.toARGB32());
    return scheme;
  }
}
```

Notes:
- Run extraction off the UI thread if it janks (profile first).
- Use a small cover (`?width=128`) for extraction, never the full-size image.
- `fidelity` keeps the cover's actual hue. If results look muddy on gray covers, fall back to `NeutralSeed`.
- Theme modes: system, light, dark, AMOLED (dark with `surface` forced to pure black). Stored in GlobalDb settings.

Fonts: bundle Newsreader (titles) and Inter (UI) as assets with their OFL license files in `assets/fonts/LICENSES/`. Define `TextTheme` in `typography.dart`: `displaySmall`, `headlineMedium`, `titleLarge` use Newsreader; everything else Inter.

### Acceptance
- [ ] Light, dark and AMOLED themes switch at runtime
- [ ] A debug screen (`/debug/colors`, debug builds only) shows 6 sample covers with their derived schemes side by side
- [ ] Text on derived surfaces passes AA contrast (unit test using the scheme's on-roles)

---

## 0.6 App shell and routing

File: `lib/app/router.dart`

```dart
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      // Phase 1: send to /onboarding when there is no active account.
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppScaffold(shell: shell), // hosts mini player above nav bar
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (_, __) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/search', builder: (_, __) => const SearchScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/you', builder: (_, __) => const YouScreen())]),
        ],
      ),
      GoRoute(path: '/item/:id', builder: (_, s) => ItemDetailScreen(itemId: s.pathParameters['id']!)),
      GoRoute(path: '/player', pageBuilder: (_, __) => const NowPlayingPage()), // full-screen modal
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    ],
  );
});
```

Tabs: Home, Library, Search, You (stats, downloads, settings, accounts live under You). The mini player sits above the navigation bar in `AppScaffold` and is hidden when nothing is loaded.

Deep links: `earloom://item/<id>` opens item detail, `earloom://player` opens Now Playing. Widgets and shortcuts in Phase 6 use these.

### Acceptance
- [ ] Four tabs with independent navigation stacks
- [ ] Deep link `earloom://item/test` routes to item detail (placeholder) on both platforms
- [ ] Mini player slot reserved and hidden by default

---

## Phase 0 done when
- [ ] All section checklists ticked
- [ ] `docs/abs-api.md` reviewed by the owner (stop and ask for review before Phase 1)
