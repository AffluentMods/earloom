# Audiobookshelf API reference for Earloom

## Verified against Audiobookshelf v2.37.2

Date: 2026-11-12

This is the API as the server really behaves, checked two ways:

- **Source**: the ABS server source at tag `v2.37.2` (routes, controllers, auth, socket).
- **Live**: the dev server in `tool/abs-dev` (image `ghcr.io/advplyr/audiobookshelf:2.37.2`), called as `root` (admin) and `affluent` (normal user: `download` only, no `update`, `delete` or `upload`).

Every endpoint below is marked **live** (seen in a real response) or **source only** (read in the server code, not exercised). Nothing here is taken from api.audiobookshelf.org.

Re-check after an ABS upgrade with `dart run tool/api_probe.dart` (see section 15).

## Contents

1. Conventions
2. Endpoint map (every row of the plan's API map)
3. Reachability
4. Local login, tokens, refresh, logout
5. OIDC (source only)
6. Current user, permissions, progress, bookmarks
7. Libraries and browsing
8. Items, covers, author images, files
9. Playback sessions and streaming
10. Offline (local) sessions
11. Listening stats
12. Playlists and collections
13. Podcasts
14. Socket
15. Fixtures and the probe script
16. Security advisories and minimum version
17. Answers to the Phase 0 questions
18. Differences from the plan
19. Not verified

---

## 1. Conventions

- **Base URL.** All paths are relative to the server base URL. A server can run under a subpath (`ROUTER_BASE_PATH`). URLs returned inside responses (`contentUrl`, HLS URLs) are relative, start with `/api`, `/public` or `/hls`, and do **not** include that subpath (source only for the subpath case). Always build `base + contentUrl`.
- **Auth.** `Authorization: Bearer <accessToken>` on everything under `/api`, except `GET /api/items/:id/cover` and `GET /api/authors/:id/image`, which need no auth. Routes under `/public` and `/hls` take no auth at all.
- **Ids** are UUID strings. File ids (`ino`) are numeric strings.
- **Times.** Positions and durations are seconds (numbers, may be fractional). Timestamps are epoch milliseconds.
- **Errors.** Most errors are a bare status with a `text/plain` body such as `Unauthorized`, `Forbidden`, `Not Found`, or a short English sentence. Only the auth routes answer errors as JSON (`{"error": "..."}`). Do not parse error bodies as JSON without checking the content type.
- **401 on `/api`** is always `401` with the plain text body `Unauthorized` and no `WWW-Authenticate` header. It is the same answer for a missing, garbage, tampered, expired or wrong-type token and for a disabled user. The client cannot tell these apart from the response (live).
- **403** means the user lacks a permission or library access. **404** is also used for "not yours" in a few places (noted where it happens).

### Tokens in URLs: never

The server still accepts the access token as a `?token=` query parameter on every `/api` route (live: `GET /api/me?token=...` returned 200), and the web OIDC flow puts tokens in a redirect URL. **Earloom must never do either.** Tokens go in the `Authorization` header (or `x-refresh-token` for the refresh token). For audio and HLS, where a player cannot always send headers, use the session-scoped public URLs in section 9, which carry no token.

---

## 2. Endpoint map

| Area | Endpoint | Verified |
|---|---|---|
| Reachability | `GET /ping`, `GET /status`, `GET /healthcheck` | live |
| Login | `POST /login` with `x-return-tokens: true` | live |
| Refresh | `POST /auth/refresh` with `x-refresh-token` | live |
| Logout | `POST /logout` with `x-refresh-token` | live |
| OIDC | `GET /auth/openid`, `/auth/openid/mobile-redirect`, `/auth/openid/callback` | source only |
| Me | `POST /api/authorize` (not GET), `GET /api/me`, `GET /api/me/items-in-progress` | live |
| Libraries | `GET /api/libraries`, `/api/libraries/:id/items`, `/personalized`, `/series`, `/series/:seriesId`, `/authors`, `/narrators`, `/collections`, `/playlists`, `/search`, `/filterdata` | live |
| Items | `GET /api/items/:id?expanded=1&include=progress`, `GET /api/items/:id/cover` | live |
| Authors | `GET /api/authors/:id?include=items,series` (live), `GET /api/authors/:id/image` (live for the 404 case only, no author image on the dev server) | live, partly |
| Files | `GET /api/items/:id/file/:ino`, `GET /api/items/:id/file/:ino/download`, `GET /api/items/:id/download` | live |
| Play | `POST /api/items/:id/play`, `POST /api/items/:id/play/:episodeId` | live |
| Stream | `GET /public/session/:sessionId/track/:index`, `GET /hls/:sessionId/output.m3u8` and segments | live |
| Session | `GET /api/session/:id`, `POST /api/session/:id/sync`, `POST /api/session/:id/close` | live |
| Offline sessions | `POST /api/session/local`, `POST /api/session/local-all` | live |
| Progress | `GET`/`PATCH /api/me/progress/:itemId[/:episodeId]`, `PATCH /api/me/progress/batch/update`, `DELETE /api/me/progress/:progressId`, `GET /api/me/progress` | live |
| Bookmarks | `POST`/`PATCH /api/me/item/:id/bookmark`, `DELETE /api/me/item/:id/bookmark/:time`, `GET /api/me/bookmarks[/:itemId]` | live |
| Stats | `GET /api/me/listening-stats`, `GET /api/me/listening-sessions`, `GET /api/me/item/listening-sessions/:itemId[/:episodeId]`, `GET /api/me/stats/year/:year` | live |
| Playlists | `GET`/`POST /api/playlists`, `GET`/`PATCH`/`DELETE /api/playlists/:id`, `POST /api/playlists/:id/item`, `DELETE /api/playlists/:id/item/:itemId[/:episodeId]`, `POST /api/playlists/:id/batch/add` | live |
| Playlists | `POST /api/playlists/:id/batch/remove`, `POST /api/playlists/collection/:collectionId` | source only |
| Collections | `GET /api/libraries/:id/collections`, `GET /api/collections/:id`, `POST /api/collections` | live |
| Podcasts | `GET /api/libraries/:id/recent-episodes`, `GET /api/podcasts/:id/episode/:episodeId`, `GET /api/podcasts/:id/downloads`, `GET /api/libraries/:id/episode-downloads` | live |
| Podcast admin | `GET /api/podcasts/:id/checknew`, `POST /api/podcasts/feed`, `POST /api/podcasts`, `POST /api/podcasts/:id/download-episodes`, `GET /api/podcasts/:id/clear-queue`, `PATCH`/`DELETE /api/podcasts/:id/episode/:episodeId`, `PATCH /api/items/:id/media` | live for the 403 answers to a normal user, bodies source only |
| Podcast search | `GET /api/search/podcast?term=` | live call returned an empty list (the dev container has no internet), result shape source only |
| Auth sessions | `GET /api/me/sessions`, `DELETE /api/me/sessions/:id` | live (GET), source only (DELETE) |
| Socket | socket.io at `/socket.io`, `auth` event | live |

---

## 3. Reachability

### `GET /ping` (live)

No auth. `200 {"success": true}`. Fixture: `server_ping.json`.

### `GET /healthcheck` (live)

No auth. `200` with the plain text body `OK`.

### `GET /status` (live)

No auth. Fixture: `server_status.json`.

```json
{
  "app": "audiobookshelf",
  "serverVersion": "2.37.2",
  "isInit": true,
  "language": "en-us",
  "authMethods": ["local"],
  "authFormData": { "authLoginCustomMessage": "" }
}
```

- `app` is always the string `audiobookshelf`. Use it for the "not an ABS server" check.
- `isInit` is false until a root user exists. When false the payload also has `ConfigPath` and `MetadataPath` (source only).
- `authMethods` is a list holding `local`, `openid` or both.
- `authFormData.authLoginCustomMessage` is always present. It is server-sanitized HTML set by the admin (empty string when unset).
- When `openid` is active, `authFormData` also has `authOpenIDButtonText` (string, default `Login with OpenId`) and `authOpenIDAutoLaunch` (bool). Source only: OIDC is off on the dev server.
- There is no server name anywhere in `/status` or in the login payload.

---

## 4. Local login, tokens, refresh, logout

### Token facts (live unless noted)

| Token | Format | Claims | Default lifetime in 2.37.2 | Env override |
|---|---|---|---|---|
| `user.accessToken` | JWT, HS256 | `userId`, `username`, `jti`, `type: "access"`, `iat`, `exp` | 3600 s (1 hour) | `ACCESS_TOKEN_EXPIRY` (seconds) |
| `user.refreshToken` | JWT, HS256 | same with `type: "refresh"` | 2592000 s (30 days) | `REFRESH_TOKEN_EXPIRY` (seconds) |
| `user.token` (legacy) | JWT, HS256 | `userId`, `username`, `iat`, no `exp`, no `type` | never expires | none |

- Lifetimes were read from the decoded `exp - iat` of real tokens. Other server versions use other defaults (the 2.26.0 announcement, discussion #4460, describes 12 hours and 7 days), and admins can change them. **Never hardcode a lifetime: read `exp` from the JWT.**
- The legacy `user.token` is still returned by login, refresh, authorize and `/api/me`, and the server still accepts it as a Bearer token (live: 200, and the returned user then has `isOldToken: true`). Earloom must not store or use it.
- Access tokens are stateless. An access token keeps working until its `exp`, even after a refresh, after logout, and after the session is revoked (live: `/api/me` returned 200 with the old access token after `POST /logout`).
- A refresh token is rejected as a Bearer token: `GET /api/me` with a refresh token returns 401 (live). This is the CVE-2026-73085 fix, see section 16.
- With the short-token override (`ACCESS_TOKEN_EXPIRY=60`, `REFRESH_TOKEN_EXPIRY=600`) the decoded lifetimes were 60 s and 600 s; the access token still worked at 53 s and returned 401 at 63 s; a refresh then succeeded (live).

### `POST /login` (live)

Headers: `Content-Type: application/json`, `x-return-tokens: true`.
Body: `{"username": "...", "password": "..."}`. The username is matched in lower case.

`200` response (fixture `auth_login.json`, trimmed):

```json
{
  "user": {
    "id": "ab8411d5-...",
    "username": "affluent",
    "email": null,
    "type": "user",
    "token": "<legacy JWT>",
    "mediaProgress": [ { "...": "see section 6" } ],
    "seriesHideFromContinueListening": [],
    "bookmarks": [],
    "isActive": true,
    "isLocked": false,
    "lastSeen": null,
    "createdAt": 1794490835357,
    "permissions": {
      "download": true, "update": false, "delete": false, "upload": false,
      "createEreader": false, "accessAllLibraries": true, "accessAllTags": true,
      "accessExplicitContent": false, "selectedTagsNotAccessible": false
    },
    "librariesAccessible": [],
    "itemTagsSelected": [],
    "hasOpenIDLink": false,
    "refreshToken": "<JWT>",
    "accessToken": "<JWT>"
  },
  "userDefaultLibraryId": "9c69912d-...",
  "serverSettings": { "version": "2.37.2", "timeZone": "UTC", "...": "many admin settings" },
  "ereaderDevices": [],
  "Source": "docker"
}
```

- Without `x-return-tokens: true` the body has `"refreshToken": null` and the refresh token is set as an HttpOnly cookie `refresh_token` instead (live). Always send the header.
- The response also sets an express session cookie (`connect.sid`). It is not needed for the API. Do not persist cookies for local login.
- `serverSettings.timeZone` is the server host timezone (IANA name). It matters for stats (section 11).
- `serverSettings.rateLimitLoginRequests` and `rateLimitLoginWindow` are leftovers. The real limiter is described below.

Errors (live):

| Case | Status | Body |
|---|---|---|
| Wrong password, unknown user, disabled user | 401 | `Unauthorized` (text) |
| Missing username or password | 400 | `Bad Request` (text) |
| Rate limited (live) | 429 | `{"error":"Too many authentication requests"}` (JSON), with a `Retry-After` header |

### `POST /auth/refresh` (live)

Headers: `x-refresh-token: <refreshToken>`. **No body.** A refresh token in a JSON body is ignored (live: 401 `No refresh token provided`). Without the header the server falls back to the `refresh_token` cookie.

`200`: the same payload as login, with a new `user.accessToken` and `user.refreshToken`. Fixture: `auth_refresh.json`.

Rotation and reuse (all live):

- **Every successful refresh rotates the refresh token.** The reply carries a new one; store it before using the new access token.
- **Reusing the immediately previous refresh token inside the grace period** (10 minutes by default, env `REFRESH_TOKEN_GRACE_PERIOD` in seconds) returns `200` with a new access token and the **already rotated, current** refresh token. It does not rotate again. This exists so a client that lost the rotation response can recover.
- **Reusing it after the grace period, or reusing any older token,** returns `401 {"error":"Invalid refresh token"}`. The session is **not** revoked: the current refresh token kept working afterwards (checked with the grace period set to 20 s).
- There is no reuse detection that logs the user out.
- The old access token stays valid until its own `exp`.

Errors (JSON bodies, all `401`):

| Case | Body | Verified |
|---|---|---|
| No header and no cookie | `{"error":"No refresh token provided"}` | live |
| Garbage, revoked (logged out), or out-of-grace token | `{"error":"Invalid refresh token"}` | live |
| An access token sent as refresh token | `{"error":"Invalid token type"}` | live |
| Refresh token past its `exp`, or session expired in the database | `{"error":"Refresh token expired"}` | live (600 s token, tried at 615 s) |
| User deleted or disabled | `{"error":"User not found or inactive"}` | source only |
| Rate limited | `429 {"error":"Too many authentication requests"}` | live |

The server never answers 403 here. Treat `401` as "sign in again", `429` and network errors as "try later, still signed in".

### `POST /logout` (live)

Headers: `x-refresh-token: <refreshToken>`. No body, no Bearer needed.
`200 {"redirect_url": null}`. Fixture: `auth_logout.json`.

- Deletes the session for that refresh token. A later refresh with it returns 401 (live).
- Always answers 200, also with no token or a garbage token (live).
- `?allDevices=1` deletes every session of that user (source only).
- For OIDC logins `redirect_url` can be the identity provider's end-session URL, but only if the client sends back the `auth_method` and `openid_id_token` cookies it received during the OIDC login (source only).
- The access token is not revoked (see token facts).

### Rate limiter (source, headers live)

- One shared bucket per client IP: **40 requests per 10 minutes** across `POST /login`, `POST /auth/refresh`, `GET /auth/openid`, `/auth/openid/mobile-redirect`, `/auth/openid/callback`, `/auth/openid/config` and `PATCH /api/me/password`. Successful requests count too.
- Every reply from these routes carries `RateLimit-Policy: 40;w=600`, `RateLimit-Limit: 40`, `RateLimit-Remaining: <n>` and `RateLimit-Reset: <seconds until the window resets>` (live).
- When exceeded (live, tripped on purpose): `429 Too Many Requests`, body `{"error":"Too many authentication requests"}`, with `RateLimit-Remaining: 0`, `RateLimit-Reset: <seconds>` and `Retry-After: <seconds>` (330 in the test). The window is fixed: it starts at the first counted request and everything is blocked until it ends, including a correct login. Routes outside the list keep working (`/status`, `/logout`, covers, and `/api` calls with a still-valid access token).
- Admin overrides: `RATE_LIMIT_AUTH_MAX` (0 disables), `RATE_LIMIT_AUTH_WINDOW` (milliseconds), `RATE_LIMIT_AUTH_MESSAGE` (source only).
- The bucket lives in server memory and resets on a server restart (source).
- The key is the client IP as the server sees it. Behind a reverse proxy that does not forward the client address, every user shares one bucket, so a refresh loop in one client can lock everyone out of login for up to 10 minutes. Keep refresh single-flight and never retry auth calls in a tight loop.

### Other auth-related endpoints

- `GET /api/me/sessions?page=&itemsPerPage=` (live): the user's sign-in sessions (one per refresh token chain): `{total, numPages, page, itemsPerPage, sessions: [{id, ipAddress, userAgent, deviceInfo, createdAt, updatedAt, current}]}`. `current` is true only when the request also carries `x-refresh-token`. Fixture: `me_auth_sessions.json`.
- `DELETE /api/me/sessions/:id` (source only): revoke one of them. 200, 404, 400 for a bad id, 403 for guests.
- `PATCH /api/me/password` (source only): body `{password, newPassword}`. Revokes all other sessions. With `x-refresh-token` it returns `{success: true, user: {accessToken, refreshToken}}` for the current session.
- API keys (`type: "api"` JWTs created by admins) also work as Bearer tokens (source only). Earloom does not use them.

---

## 5. OIDC (source only, to be live-tested in Phase 1)

There is no identity provider on the dev server, so everything here is from `server/Auth.js` and `server/auth/OidcAuthStrategy.js`. The only live facts: with OIDC disabled, `GET /auth/openid` and `/auth/openid/callback` answer `500`, and `/auth/openid/mobile-redirect` with an unknown state answers `400 State parameter mismatch`.

### Mobile flow

1. **App to ABS:** `GET /auth/openid?response_type=code&code_challenge=<S256 challenge>&code_challenge_method=S256&redirect_uri=earloom%3A%2F%2Foauth&state=<random>&client_id=Earloom`
   - Send this with the app's HTTP client, **not following redirects**, and **keep the cookies** from the reply.
   - The server treats the request as a mobile flow when any of `response_type=code`, `redirect_uri` or `code_challenge` is present.
   - `code_challenge`: required. `code_challenge_method`: optional, must be `S256` if sent.
   - `redirect_uri`: required, and must be an exact entry in the admin's whitelist, or the whitelist must be the single entry `*`.
   - `response_type`: optional, must be `code` if sent.
   - `state`: optional, the server generates one if missing. Send your own and check it.
   - `client_id`: **ignored by the server.** Sending it does no harm.
   - Reply: `302` with `Location` = the identity provider's authorization URL, plus cookies `connect.sid` (the server session that holds the state) and `auth_method=openid-mobile`.
   - Errors (plain text): `400 Invalid redirect_uri`, `400 code_challenge required for mobile flow (PKCE)`, `400 Only S256 code_challenge_method method supported`, `400 Invalid response_type, only code supported`, `500` with a message if OIDC is misconfigured.
2. **App opens the `Location` URL in the system browser** (`flutter_web_auth_2`). The user signs in at the identity provider.
3. **Identity provider to ABS (in the browser):** `GET /auth/openid/mobile-redirect?code=...&state=...`. ABS looks up the state (kept 10 minutes, single use) and answers `302` to `earloom://oauth?code=...&state=...`. Unknown state: `400 State parameter mismatch`.
4. **App to ABS:** `GET /auth/openid/callback?state=<state>&code=<code>&code_verifier=<PKCE verifier>`, with the **cookies from step 1**.
   - Success: `200` JSON, the same payload as `POST /login`, with `user.accessToken` and `user.refreshToken` in the body.
   - `x-return-tokens` is **not** read here. Tokens come back in the body because of the `auth_method=openid-mobile` cookie. Without that cookie the server treats the login as a web login and answers with a redirect instead of JSON. (In the real web flow that redirect goes to a same-origin callback URL with the tokens in the query string. Earloom must never use the web flow.) Without the `connect.sid` cookie the answer is `400 No session`.
   - Errors (plain text): `400 No session`, `401 Unauthorized` (user not allowed, not found and auto-register off, group claim missing), `500 Error in callback`.
   - The reply also sets an `openid_id_token` cookie, used only to build the provider logout URL at `POST /logout`.

All three routes go through the auth rate limiter.

### Where admins whitelist the redirect URI

ABS web UI: **Settings, Authentication, OpenID Connect Authentication, "Allowed Mobile Redirect URIs"** (setting key `authOpenIDMobileRedirectURIs`, default `["audiobookshelf://oauth"]`). The admin must add `earloom://oauth`. A single `*` entry allows any URI.

### `/status` with OIDC enabled

`authMethods` contains `openid` and `authFormData` gains `authOpenIDButtonText` and `authOpenIDAutoLaunch`. See section 3.

---

## 6. Current user, permissions, progress, bookmarks

### `POST /api/authorize` (live)

**POST, not GET** (`GET /api/authorize` is 404). No body. Returns the login payload (`user`, `userDefaultLibraryId`, `serverSettings`, `ereaderDevices`, `Source`) but `user` has **no** `accessToken` or `refreshToken` key. Fixture: `auth_authorize.json`.

### `GET /api/me` (live)

Returns just the user object: exactly `authorize.user` (compared live, identical keys and values). Fixture: `me_user.json`.

### Where type and permissions live

- `user.type`: `root`, `admin`, `user` or `guest`.
- `user.permissions`: booleans `download`, `update`, `delete`, `upload`, `createEreader`, `accessAllLibraries`, `accessAllTags`, `accessExplicitContent`, `selectedTagsNotAccessible`.
- `user.librariesAccessible` and `user.itemTagsSelected` are top-level arrays on the user (not inside `permissions`).

What the server checks (source, and live where a 403 is listed):

| Action | Rule |
|---|---|
| Podcast admin: add podcast, fetch feed, check new, download episodes, clear queue | `type` is `admin` or `root`. Not a permission flag. Live: 403 for `affluent`. |
| Edit item or podcast media, edit episode, create or edit collections | `permissions.update`. Live: 403 for `affluent`. |
| Delete item, episode | `permissions.delete`. Live: 403 for `affluent` on episode delete. |
| `GET /api/items/:id/file/:ino/download`, `GET /api/items/:id/download` | `permissions.download`, else 403 (source only, `affluent` has it) |
| Upload | `permissions.upload` |
| Playlists, progress, bookmarks, play, stats | any signed-in user |

### `GET /api/me/items-in-progress?limit=25` (live)

`{"libraryItems": [...]}`: minified items across all libraries with unfinished progress and `currentTime > 0`, newest first. Each has `progressLastUpdate`. Podcast entries are the podcast item plus `recentEpisode` (the episode in progress); one podcast can appear several times. Fixture: `me_items_in_progress.json`.

### Media progress object (live)

```json
{
  "id": "301493af-...", "userId": "ab8411d5-...",
  "libraryItemId": "695b9eb3-...", "episodeId": null,
  "mediaItemId": "92a61808-...", "mediaItemType": "book",
  "duration": 1920, "progress": 0.0729, "currentTime": 140,
  "isFinished": false, "hideFromContinueListening": false,
  "ebookLocation": null, "ebookProgress": 0,
  "lastUpdate": 1794491213254, "startedAt": 1794491213113, "finishedAt": null
}
```

Fixtures: `me_progress_book.json`, `me_progress_episode.json`. `mediaItemType` is `book` or `podcastEpisode`.

### Reading progress (live)

- `GET /api/me/progress` returns `{"mediaProgress": [...]}` (everything).
- `GET /api/me/progress/:itemId` and `GET /api/me/progress/:itemId/:episodeId` return one object, or `404 Not Found` when there is none.
- For a podcast, `GET /api/me/progress/:itemId` without an episode id returns some episode's progress of that podcast. Always pass the episode id.
- List endpoints never attach progress to items, even with `include=progress`. Only the single item endpoint does (`userMediaProgress`). Get progress from the login or `/api/me` payload and keep it fresh from the socket.

### `PATCH /api/me/progress/:itemId` and `/:itemId/:episodeId` (live)

Body: any of `currentTime`, `duration`, `progress`, `isFinished`, `hideFromContinueListening`, `finishedAt`, `lastUpdate` (also `ebookLocation`, `ebookProgress`). `200` with the plain text `OK`, no JSON.

Behavior seen live:

- Creates the progress row if there is none.
- **`progress` is stored as sent. The server does not compute it from `currentTime` on this route.** Sending only `currentTime` left the old `progress` value in place. Always send `currentTime`, `duration` and `progress` together.
- **Mark finished:** `{"isFinished": true}`. Sets `progress` to 1 and `finishedAt` to now. On a row created this way `duration` and `currentTime` stay 0.
- **Mark unfinished:** `{"isFinished": false}` resets `progress` and `currentTime` to 0.
- **Auto finish:** when `duration` is known and `duration - currentTime` is under 10 seconds, the server sets `isFinished: true` and `progress: 1` by itself (book 720 s, sent 715 s). Moving `currentTime` back out of that zone clears `isFinished` again (source).
- **`lastUpdate`** in the body overwrites the row timestamp, even with an older value. There is no "newer wins" check on this route: the last writer wins. The client must compare before sending.
- Emits socket `user_updated` (the whole user), **not** `user_item_progress_updated`.

Errors: `404 Library item not found`, `404 Episode not found`, `400 Library item is not a book` (a podcast item id without an episode id).

### `PATCH /api/me/progress/batch/update` (live)

Body: a bare JSON array of the same objects, each with `libraryItemId` and optional `episodeId`:

```json
[{"libraryItemId": "...", "currentTime": 100, "duration": 720, "progress": 0.1389},
 {"libraryItemId": "...", "episodeId": "...", "currentTime": 60, "duration": 300, "progress": 0.2}]
```

`200 OK` even when some entries fail (a bad entry is skipped silently). `400 Missing request payload` for an empty array or a non-array.

### `DELETE /api/me/progress/:progressId` (live)

Takes the **progress row id** (`mediaProgress.id`), not the item id. `200`, or `404` if unknown. Emits `user_updated`.

### Bookmarks (live)

A bookmark is `{libraryItemId, time, title, createdAt}`. Identity is `(libraryItemId, time)`. There is no bookmark id and no episode id, so bookmarks on podcast items cannot say which episode they belong to (the server accepts them anyway).

| Call | Body | Result |
|---|---|---|
| `POST /api/me/item/:id/bookmark` | `{"time": 612, "title": "..."}` | `200` the bookmark. Fixture `me_bookmark_create.json`. |
| `PATCH /api/me/item/:id/bookmark` | `{"time": 612, "title": "New title"}` | `200` the bookmark, `404` if no bookmark at that time. Only the title can change. |
| `DELETE /api/me/item/:id/bookmark/:time` | none | `200 OK`, `404` if none at that time, `400 Invalid time` if not a number |
| `GET /api/me/bookmarks` | | `{"bookmarks": [...]}` for all items. Fixture `me_bookmarks.json`. |
| `GET /api/me/bookmarks/:id` | | `{"bookmarks": [...]}` for one item |

- **Two bookmarks at the same time value:** the second `POST` does not fail and does not add a second bookmark. It overwrites the title of the existing one and returns it (same `createdAt`).
- **Fractional times are fine:** `612` and `612.4` are two different bookmarks, and `DELETE .../bookmark/612.4` works.
- **`time` must be a JSON number.** A bookmark created with `"time": "613"` (a string) is stored as a string and can then not be deleted: `DELETE` answers 200 but the bookmark stays. (The probe had to remove it from the database by hand.) Parse `time` leniently when reading, write it strictly as a number.
- Missing or empty `title`: `400 Invalid title`. Missing `time`: `400 Invalid time`. Unknown item: `404`.
- All three writes emit socket `user_updated`.

---

## 7. Libraries and browsing

All routes here need access to the library: `403` if the user may not see it, `404 Library not found` for an unknown id. `limit` and `page` must be non-negative integers, else `400`. `page` is zero-based. `limit=0` or no limit returns everything.

### `GET /api/libraries` (live)

`{"libraries": [{id, name, folders, displayOrder, icon, mediaType, provider, settings, lastScan, lastScanVersion, createdAt, lastUpdate}]}`. `mediaType` is `book` or `podcast`. Only libraries the user can access. `settings.markAsFinishedTimeRemaining` (default 10) and `settings.markAsFinishedPercentComplete` drive the auto-finish rule used by session sync. `?include=stats` adds stats (source only). Fixture: `libraries_list.json`.

### `GET /api/libraries/:id/items` (live)

Query: `limit`, `page`, `sort`, `desc=1`, `filter`, `minified=1`, `collapseseries=1`, `include`.

Response: `{results, total, limit, page, sortBy, sortDesc, filterBy, mediaType, minified, collapseseries, include, offset}`. Fixtures: `library_items_page.json`, `library_items_page_podcast.json`, `library_items_series_filter.json`, `library_items_collapsed_series.json`.

Book result (always the compact form in 2.37.2; `minified=1` made no visible difference on this route):

```json
{
  "id": "...", "ino": "...", "libraryId": "...", "folderId": "...",
  "path": "...", "relPath": "...", "isFile": false,
  "mtimeMs": 0, "ctimeMs": 0, "birthtimeMs": 0, "addedAt": 0, "updatedAt": 0,
  "isMissing": false, "isInvalid": false, "mediaType": "book",
  "media": {
    "id": "...",
    "metadata": {
      "title": "...", "titleIgnorePrefix": "...", "subtitle": null,
      "authorName": "Mara Ellison", "authorNameLF": "Ellison, Mara",
      "narratorName": "...", "seriesName": "The Example Saga #2",
      "genres": [], "publishedYear": "2024", "publishedDate": null, "publisher": "...",
      "description": "<p>HTML</p>", "isbn": null, "asin": null, "language": "English",
      "explicit": false, "abridged": false
    },
    "coverPath": "...", "tags": [], "numTracks": 8, "numAudioFiles": 8, "numChapters": 8,
    "duration": 1920, "size": 7695908
  },
  "numFiles": 10, "size": 7705670
}
```

- There is no `coverUpdatedAt`. Use the item `updatedAt` as the cover cache key.
- `seriesName` is a display string (`"Name #sequence"`, several series joined by commas). The structured `media.metadata.series: {id, name, sequence}` appears only when filtering by a series. `sequence` is a string (`"1"`, `"2.5"`, `"10"`).
- Podcast results have `media.metadata.{title, author, description, releaseDate, genres, feedUrl, imageUrl, itunesPageUrl, itunesId, itunesArtistId, explicit, language, type, titleIgnorePrefix}` and `media.{numEpisodes, autoDownloadEpisodes, autoDownloadSchedule, lastEpisodeCheck, maxEpisodesToKeep, maxNewEpisodesToDownload, size}`.
- `description` is HTML. The server sanitized the hostile seed description when scanning, but the client must still sanitize.

**Sort keys, books** (source, several live): `media.metadata.title`, `media.metadata.authorName`, `media.metadata.authorNameLF`, `addedAt`, `size`, `birthtimeMs`, `mtimeMs`, `media.duration`, `media.metadata.publishedYear`, `progress` (most recently updated progress), `progress.createdAt`, `progress.finishedAt`, `sequence` (only with a series filter), `random`.
**Sort keys, podcasts** (source only): `media.metadata.title`, `media.metadata.author`, `addedAt`, `size`, `birthtimeMs`, `mtimeMs`, `media.numTracks`, `random`.

**Filters.** `filter=<group>.<value>` where value is **base64 of the raw value, then URL-encoded** (live). Groups for books:

| Group | Value before encoding | Verified |
|---|---|---|
| `progress` | `finished`, `not-started`, `not-finished`, `in-progress` | live (`in-progress`, `finished`) |
| `genres`, `tags`, `narrators` | the name | live (`genres`, `narrators`) |
| `authors`, `series` | the id (`series` also takes `no-series`) | live |
| `languages`, `publishers`, `publishedDecades` | the name, the decade start year | source only |
| `tracks` | `none`, `single`, `multi` | source only |
| `missing`, `ebooks`, `abridged`, `explicit`, `issues`, `feed-open` | see source | source only |

Example: in-progress books are `filter=progress.aW4tcHJvZ3Jlc3M%3D`.

`collapseseries=1` folds a series into one result that carries `collapsedSeries: {id, name, nameIgnorePrefix, sequence, numBooks, libraryItemIds}` (live).

`include`: `rssfeed`, `numEpisodesIncomplete` (podcasts), `share` (admins). Not `progress`.

### `GET /api/libraries/:id/personalized?limit=10` (live)

Home shelves. `limit` is items per shelf (default 10). Response is a **bare JSON array** of shelves, in display order. Empty shelves are left out. Fixtures: `library_personalized_book.json`, `library_personalized_podcast.json`.

Shelf: `{id, label, labelStringKey, type, entities, total}`.

| Library | `id` | `labelStringKey` | `label` | `type` | Entities | Verified |
|---|---|---|---|---|---|---|
| book, podcast | `continue-listening` | `LabelContinueListening` | Continue Listening | `book` or `episode` | items (podcast: item plus `recentEpisode`) | live |
| book | `continue-reading` | `LabelContinueReading` | Continue Reading | `book` | ebook-only items | source only |
| book | `continue-series` | `LabelContinueSeries` | Continue Series | `book` | next unfinished book, with `media.metadata.series: {id, name, sequence}` | live |
| book, podcast | `recently-added` | `LabelRecentlyAdded` | Recently Added | `book` or `podcast` | items | live |
| book | `recent-series` | `LabelRecentSeries` | Recent Series | `series` | series with `books` | live |
| book | `discover` | `LabelDiscover` | Discover | `book` | items picked by the server for discovery (selection rule not checked) | live |
| book, podcast | `listen-again` | `LabelListenAgain` | Listen Again | `book` or `episode` | finished items | live (book) |
| book, podcast | `read-again` | `LabelReadAgain` | Read Again | `book` | finished ebooks | source only |
| book | `newest-authors` | `LabelNewestAuthors` | Newest Authors | `authors` | authors with `numBooks` | live |
| podcast | `newest-episodes` | `LabelNewestEpisodes` | Newest Episodes | `episode` | podcast item plus `recentEpisode` | live |

- `continue-series` shows a series only when the user finished at least one book in it and has **no** book of that series in progress.
- Shelf entities do not carry progress.
- `include=numEpisodesIncomplete` adds that count to podcast items in `recently-added` (live).

### `GET /api/libraries/:id/series` (live)

Query: `limit`, `page`, `sort` (`name`, `numBooks`, `addedAt`, `totalDuration`, `lastBookAdded`, `lastBookUpdated`, `random`), `desc`, `filter`.
Response: `{results, total, limit, page, sortBy, sortDesc, filterBy, minified, include}`; each series is `{id, name, nameIgnorePrefix, description, addedAt, updatedAt, libraryId, books}`. Fixture: `library_series.json`.

`books` are compact items already in sequence order (1, 2, 2.5, 10 on the dev server), but they carry the sequence **only inside `seriesName`**. To get a structured sequence, use `GET /api/libraries/:id/items?filter=series.<base64 id>&sort=sequence`.

### `GET /api/libraries/:id/series/:seriesId?include=progress` (live)

`{id, name, nameIgnorePrefix, description, addedAt, updatedAt, libraryId, progress: {libraryItemIds, libraryItemIdsFinished, isFinished}}`. No books. `GET /api/series/:id?include=progress` returns the same. Fixture: `library_series_one.json`.

### `GET /api/libraries/:id/authors` (live)

- Without paging: `{"authors": [{id, asin, name, description, imagePath, libraryId, addedAt, updatedAt, numBooks, lastFirst}]}`.
- With both `limit` and `page`: `{results, total, limit, page, sortBy, sortDesc, filterBy, minified, include}`.
- `sort`: `name`, `lastFirst`, `addedAt`, `updatedAt`, `numBooks`.
- Normal users only see authors that have at least one book they can access.

Fixture: `library_authors.json`.

### `GET /api/authors/:id?include=items,series` (live)

Author plus `libraryItems` (compact items) and `series: [{id, name, items}]`, where each item has `media.metadata.series: {id, name, nameIgnorePrefix, sequence}` and items are in natural sequence order. `404` if the author is in a library the user cannot access. Fixture: `author_expanded.json`.

### `GET /api/libraries/:id/narrators` (live)

`{"narrators": [{id, name, numBooks}]}`. There is no narrator entity: `id` is the URL-encoded base64 of the name, ready to use as `filter=narrators.<id>`. Fixture: `library_narrators.json`.

### `GET /api/libraries/:id/collections` (live)

`{results, total, limit, page, sortDesc, minified, include}`; each collection is `{id, libraryId, name, description, books, lastUpdate, createdAt}` and `books` are full (non-minified) items. `GET /api/collections/:id` returns one collection in the same shape. Fixture: `library_collections.json`.

### `GET /api/libraries/:id/playlists` (live)

`{results, total, limit, page}`: the current user's playlists in that library. See section 12. Fixtures: `library_playlists.json`, `library_playlists_podcast.json`.

### `GET /api/libraries/:id/filterdata` (live)

`{authors: [{id, name}], genres: [], tags: [], series: [{id, name}], narrators: [], languages: [], publishers: [], publishedDecades: [], bookCount, authorCount, seriesCount, podcastCount, numIssues, loadedAt}`. The four `*Count` fields were all 0 on the dev server even though the library has books: do not use them. Fixtures: `library_filterdata_book.json`, `library_filterdata_podcast.json`.

### `GET /api/libraries/:id/search?q=<text>&limit=12` (live)

`q` is required (`400` without it). `limit` is per group.

- Book library: `{book: [{libraryItem}], authors: [author with numBooks], series: [{series, books}], narrators: [{name, numBooks}], tags: [{name, numItems}], genres: [{name, numItems}]}`.
- Podcast library: `{podcast: [{libraryItem}], episodes: [{libraryItem}], tags, genres}`. An episode hit is the podcast item with a `recentEpisode`.
- `libraryItem` here is the full expanded item.

Fixtures: `library_search_book.json`, `library_search_podcast.json`.

### `GET /api/libraries/:id/recent-episodes?limit=&page=` (live)

Podcast libraries only (`404` on a book library). `{episodes, limit, page}`, no `total`. Each episode is the episode object (section 13) plus `podcast` (the podcast media with metadata), `libraryId`, `audioTrack`, `size`, `duration`. Fixture: `library_recent_episodes.json`.

---

## 8. Items, covers, author images, files

### `GET /api/items/:id?expanded=1&include=progress` (live)

- `include`: `progress` (adds `userMediaProgress`, or `null`), `rssfeed` (adds `rssFeed`), `downloads` (podcasts: adds `episodeDownloadsQueued` and `episodesDownloading`), `share` (admins).
- For a podcast, `&episode=<episodeId>` selects which episode's progress goes into `userMediaProgress`.
- `404` unknown item, `403` no access.

Fixtures: `item_book_expanded.json` (multi-file MP3), `item_book_expanded_m4b.json` (single file, embedded chapters), `item_podcast_expanded.json`.

Expanded book, the parts Earloom uses:

```json
{
  "id": "...", "libraryId": "...", "mediaType": "book", "addedAt": 0, "updatedAt": 0,
  "libraryFiles": [{"ino": "950725", "metadata": {"filename": "cover.jpg", "ext": ".jpg", "size": 9329, "...": ""}, "fileType": "image"}],
  "media": {
    "id": "...", "libraryItemId": "...",
    "metadata": {
      "title": "...", "subtitle": null,
      "authors": [{"id": "...", "name": "Mara Ellison"}],
      "narrators": ["Jonah Pryce"],
      "series": [{"id": "...", "name": "The Example Saga", "sequence": "2"}],
      "genres": [], "publishedYear": "2024", "publisher": "...",
      "description": "<p>HTML</p>", "descriptionPlain": "plain text",
      "isbn": null, "asin": null, "language": "English", "explicit": false, "abridged": false,
      "titleIgnorePrefix": "...", "authorName": "...", "authorNameLF": "...", "narratorName": "...", "seriesName": "..."
    },
    "coverPath": "...", "tags": [],
    "audioFiles": [{"index": 1, "ino": "950727", "metadata": {"filename": "...", "ext": ".mp3", "size": 960585}, "duration": 240, "bitRate": 32000, "codec": "mp3", "channels": 1, "mimeType": "audio/mpeg", "chapters": [], "metaTags": {}}],
    "chapters": [{"id": 0, "start": 0, "end": 240, "title": "Chapter 1"}],
    "tracks": [{"index": 1, "ino": "950727", "startOffset": 0, "duration": 240, "title": "... - 01.mp3", "contentUrl": "/api/items/<id>/file/950727", "mimeType": "audio/mpeg", "...": "all audioFile fields"}],
    "ebookFile": null,
    "numTracks": 8, "numAudioFiles": 8, "numChapters": 8, "duration": 1920, "size": 7695908
  },
  "userMediaProgress": { "...": "progress object or null" }
}
```

- In the expanded form `series` is an array and `authors` is an array of `{id, name}`.
- `media.tracks` already has `startOffset` and `contentUrl`, so the download manager can build its file list from the item alone, without opening a play session.
- `audioFiles[].metadata.size` matched the `Content-Length` of the file exactly (960585). Use it to verify downloads.
- Without `expanded=1` the item has no `tracks`, `numTracks`, `duration` or `size` (live).

Expanded podcast: `media.{metadata, coverPath, tags, episodes, autoDownloadEpisodes, autoDownloadSchedule, lastEpisodeCheck, maxEpisodesToKeep, maxNewEpisodesToDownload, numEpisodes, size}`. Each episode: `{libraryItemId, podcastId, id, index, season, episode, episodeType, title, subtitle, description, enclosure, guid, pubDate, chapters, audioFile, publishedAt, addedAt, updatedAt, audioTrack, size, duration}`. `season` and `episode` are strings or null. `audioTrack.contentUrl` is `/api/items/<podcast item id>/file/<ino>`.

### `GET /api/items/:id/cover` (live)

**No auth required** (no header, no cookie: 200). Other methods on this path need auth.

| Query | Effect (live) |
|---|---|
| none | resized to **width 400**, aspect kept. Format WebP if the `Accept` header contains `image/webp` or is exactly `*/*`, else JPEG. |
| `width=N` | N pixels wide, aspect kept. Clamped to 4096. It also **upscales** (a 400 px cover came back 4096 px wide for `width=99999`). `width=0` or a non-number falls back to 400. |
| `height=N` | N pixels high, but the width stays 400 unless `width` is also given, so `height` alone distorts the image (400x200 from a square). |
| `width=W&height=H` | exactly WxH, stretched. Send `width` only. |
| `format=webp`, `jpeg` or `png` | that format, with the matching `Content-Type`. Anything else: `400`. |
| `raw=1` | the original file, untouched, with `ETag`, `Last-Modified`, `Content-Length`. All other params are ignored. |
| `ts=<anything>` | adds `Cache-Control: private, max-age=86400`. |

- Resized covers are sent chunked with **no `Content-Length`, no `ETag` and no cache header** (unless `ts` is given). Cache on the client by `(itemId, updatedAt, width)`.
- `404` when the item has no cover or is unknown. The id must be a UUID.
- Always send `format` explicitly. For lists use `?width=<bucket>&format=webp`.

### `GET /api/authors/:id/image` (live for 404 only)

No auth. Same query params and code path as the cover (source). `404` when the author has no image (`imagePath: null`), which is the case for every author on the dev server.

### Audio files (live)

| Endpoint | Auth | Permission | Range | Notes |
|---|---|---|---|---|
| `GET /api/items/:id/file/:ino` | Bearer (401 without) | library access | yes | This is the direct-play `contentUrl`. Works with or without an open session. `Content-Type` from the extension (`audio/mpeg`, `audio/mp4` for m4b). |
| `GET /api/items/:id/file/:ino/download` | Bearer | `download` (403 otherwise, source only) | yes | Same bytes, plus `Content-Disposition: attachment; filename="..."`. **Use this for offline downloads.** |
| `GET /public/session/:sessionId/track/:index` | none | an open session | yes | See section 9. |
| `GET /api/items/:id/download` | Bearer | `download` | no | Whole item as a ZIP built on the fly (`Transfer-Encoding: chunked`, no length, Range ignored). Not resumable: do not use. |

Range behavior, identical on the first three (live): `Accept-Ranges: bytes`; `Range: bytes=1000-1999` returns `206` with `Content-Range: bytes 1000-1999/<size>` and exactly 1000 bytes; open-ended ranges work; `If-Range` with the `ETag` works; an out-of-bounds range returns `416` with `Content-Range: bytes */<size>`. `ETag` and `Last-Modified` are present. `HEAD` works.

`404` for an unknown `ino`. Behind an nginx `X-Accel` setup the server answers `204` with an `X-Accel-Redirect` header and nginx serves the file (source only).

---

## 9. Playback sessions and streaming

### `POST /api/items/:id/play` and `POST /api/items/:id/play/:episodeId` (live)

Any signed-in user with access to the item. Body fields the server reads (all optional, but see the warnings):

```json
{
  "deviceInfo": {
    "deviceId": "stable-per-install-id",
    "clientName": "Earloom",
    "clientVersion": "1.0.0",
    "manufacturer": "...",
    "model": "...",
    "sdkVersion": "34"
  },
  "forceDirectPlay": false,
  "forceTranscode": false,
  "supportedMimeTypes": ["audio/mpeg", "audio/mp4"],
  "mediaPlayer": "earloom"
}
```

How the server decides (source, each case live):

- Direct play if `forceDirectPlay` is true, or if `forceTranscode` is not true **and** every audio file's `mimeType` is in `supportedMimeTypes`. `forceDirectPlay` wins over `forceTranscode`.
- **If `supportedMimeTypes` is missing or not an array, the server transcodes**, even a plain MP3 book. An empty body gives a transcode session.
- `mediaPlayer` defaults to `unknown`. It is stored with the session and comes back in the listening sessions list.
- `deviceInfo.deviceId` should be a stable id. The server keeps one device record per `deviceId`, and **starting a session closes every other open session of the same user on the same device**. Without a `deviceId` each call creates a new device record and nothing is closed.
- `sdkVersion` may be a number or a string. Any other `deviceInfo` keys are ignored. HTML tags are stripped from the strings.
- The server also reads the `User-Agent` header for browser and OS fields.

Response: the PlaybackSession. Fixtures: `session_play_book_multifile.json`, `session_play_book_m4b.json`, `session_play_book_transcode_hls.json`, `session_play_episode.json`.

```json
{
  "id": "fc9d56a4-...", "userId": "...", "libraryId": "...", "libraryItemId": "...",
  "bookId": "...", "episodeId": null, "mediaType": "book",
  "mediaMetadata": { "title": "...", "authors": [], "narrators": [], "series": [], "...": "" },
  "chapters": [{"id": 0, "start": 0, "end": 240, "title": "Chapter 1"}],
  "displayTitle": "The Clockmaker's Tide", "displayAuthor": "Mara Ellison",
  "coverPath": "...", "duration": 1920,
  "playMethod": 0, "mediaPlayer": "earloom",
  "deviceInfo": {"id": "...", "userId": "...", "deviceId": "...", "ipAddress": "...", "clientVersion": "...", "manufacturer": "...", "model": "...", "sdkVersion": "34", "clientName": "Earloom", "deviceName": "..."},
  "serverVersion": "2.37.2", "date": "2026-11-12", "dayOfWeek": "Thursday",
  "timeListening": 0, "startTime": 140, "currentTime": 140,
  "startedAt": 1794491173519, "updatedAt": 1794491173519,
  "audioTracks": [
    {"index": 1, "ino": "950727", "startOffset": 0, "duration": 240, "title": "... - 01.mp3",
     "contentUrl": "/api/items/<itemId>/file/950727", "mimeType": "audio/mpeg", "codec": "mp3",
     "metadata": {"filename": "...", "ext": ".mp3", "size": 960585}, "...": "all audioFile fields"}
  ],
  "libraryItem": { "...": "the full expanded item" }
}
```

- `playMethod`: `0` direct play, `1` direct stream (never returned by this endpoint), `2` transcode, `3` local (the value clients send for offline sessions).
- `currentTime` and `startTime` are the resume position from the user's progress (live: 140 after syncing to 140). If the item is marked finished they are `0`, so a finished book starts over (source only).
- `audioTracks[].index` is the file's own index and **starts at 1**. `startOffset` and `duration` are seconds; tracks are in play order.
- `chapters`: `{id, start, end, title}` in whole-book seconds. For the M4B they are the embedded chapters (9), for the multi-file book one per file (8), for a podcast episode the episode chapters (empty on the dev server).
- For an episode: `episodeId` set, `bookId` null, `displayTitle` is the episode title, `displayAuthor` the podcast author, `mediaMetadata` the podcast metadata.

Errors: `404` unknown item, unknown episode, or an item with no audio; `400` when `/play/:episodeId` is used on a book; `403` no access.

**Never call `/play` without an episode id on a podcast item.** The server answers 200 with a broken transcode session (empty title, duration 0) and starts ffmpeg (live).

### Direct play URLs and how they are authorized (live)

Each track can be fetched two ways:

1. `contentUrl` as given: `/api/items/<itemId>/file/<ino>`. **Needs `Authorization: Bearer`** (401 without, 401 with an expired token). Not tied to the session.
2. `/public/session/<sessionId>/track/<index>`: **no auth at all.** The session id is the capability.

### `GET /public/session/:sessionId/track/:index` (live)

- Streams with **no `Authorization` header and no cookie** (200, full file).
- **Honors HTTP Range**: `Range: bytes=1000-1999` gave `206`, `Content-Range: bytes 1000-1999/960585`, 1000 bytes, byte-identical to the same range of the authenticated URL. Seeking works.
- `:index` is `audioTracks[].index` (1-based), not the list position. For podcast episodes both `0` and `1` work.
- It keeps working after the access token that opened the session has expired (live with 60 s tokens).
- **It stops when the session closes**: `404` right after `POST /api/session/:id/close`. A session also disappears when the same user starts another session with the same `deviceId` (live), when the server restarts, because open sessions live in memory (live: sync and the public URL both answered 404 after a container restart, while the access token kept working), and when it has had no sync for 36 hours (source only).
- `404` unknown session or index, `400` non-numeric index.
- For a transcode session it answers `302` to the HLS playlist.
- Anyone who learns the session id can stream until the session closes. It is a random UUID; never log it or put it in analytics.

### Transcode: HLS (live)

When the session is a transcode, `playMethod` is `2` and there is exactly **one** audio track:

```json
{"index": 1, "startOffset": 0, "duration": 600.013, "title": "Lanterns Under the Ice",
 "contentUrl": "/hls/<sessionId>/output.m3u8", "mimeType": "application/vnd.apple.mpegurl", "codec": null}
```

- URL shape: `/hls/<sessionId>/output.m3u8`, segments `/hls/<sessionId>/output-<n>.ts`.
- **No auth**: the playlist and segments were served with no header at all. The session id is the capability. There is no token in the URL.
- The playlist is a complete VOD playlist written up front (`#EXT-X-PLAYLIST-TYPE:VOD`, 6 second segments, `#EXT-X-ENDLIST`), while ffmpeg is still producing segments. Segments are MPEG-TS (`video/mp2t`); the source hardcodes this segment type.
- Positions are whole-book seconds: the stream covers the whole book as one track, starting the encode near the resume position.
- A segment that is not encoded yet answers `404`; if it is far from the encoder position the server restarts ffmpeg there and emits socket `stream_reset {startTime, streamId}` (source only).
- Only `.m3u8` and `.ts` are served (`400` otherwise). After close: `404`.
- Sync and close work exactly as for direct play.

### `GET /api/session/:id` (live)

The open session in the same shape as the play response, with the current `currentTime` and `timeListening`. `404` once closed.

### `POST /api/session/:id/sync` (live)

Body: `{"currentTime": 95.5, "timeListened": 30, "duration": 1920}`. `200` with the text `OK`.

- `currentTime`: whole-book position in seconds. **Required in practice**: a sync without it (for example `{}`) still answers 200 but blanks the stored position (the progress object came back without a `currentTime`). Always send a number, never a string (a string is stored as a string).
- `timeListened`: seconds of real listening **since the previous sync** (a delta). The server adds it to the session's `timeListening`. `0` or missing adds nothing.
- `duration`: optional since ABS 2.15.1 (source comment); the session duration is used when missing.
- Each sync writes the user's progress (`progress = currentTime / duration`, computed by the server on this route), applies the library's auto-finish rule (default: under 10 seconds left), and emits socket `user_item_progress_updated`.
- The session row is only stored once it has listening time. A session opened and closed with no `timeListened` leaves no trace in stats.

Status codes (live): `404 Not Found` for a closed, unknown or malformed session id; `403` for another user's session (source only); `401` with an expired access token; `500` if the item or library was deleted meanwhile (source only).

### `POST /api/session/:id/close` (live)

Body: optional, the same object as sync (a final sync). `200 OK`. Emits `user_session_closed` with the session id as a bare string. Closing twice: `404`.

### How often the official clients sync

- Web client (source in the ABS repo): first sync after 20 seconds of listening, then every 10 seconds, plus a final sync in the close call.
- Official mobile app (read from `audiobookshelf-app`, `MediaProgressSyncer.kt` on the master branch, 2026-11-12): checks every 15 seconds while playing, syncs every time on unmetered networks and at most once per 60 seconds on metered ones; payload `timeListened`, `duration`, `currentTime`.

Earloom's planned 15 second interval is in line with both.

---

## 10. Offline (local) sessions

Both routes take sessions the client recorded itself and merge them into listening stats and progress. Verified live with hand-built payloads. Fixtures: `session_local_all_request.json` (a payload the server accepted), `session_local_all_response.json`.

### `POST /api/session/local-all`

```json
{
  "deviceInfo": { "deviceId": "...", "clientName": "Earloom", "clientVersion": "...", "manufacturer": "...", "model": "..." },
  "sessions": [ { "...": "local session" } ]
}
```

`200 {"results": [{"id": "...", "success": true, "progressSynced": true}, {"id": "...", "success": false, "error": "Media item not found"}]}`. Always 200; failures are per entry. An empty or missing `sessions` gives `{"results": []}`.

### `POST /api/session/local`

Body: one local session object, with `deviceInfo` inside it. `200 OK` (text) on success. On a per-session failure it answers **`500`** with the error text (`Media item not found`, `Library not found`). That 500 is permanent, not a server crash: prefer `local-all`, which reports the same thing as `success: false`.

### Local session object

Minimum that worked (live):

```json
{
  "id": "11111111-2222-4333-8444-555555555501",
  "libraryItemId": "...",
  "currentTime": 100,
  "timeListening": 40,
  "startedAt": 1794491419118,
  "updatedAt": 1794491459118
}
```

plus `episodeId` for a podcast episode. Recommended full shape (live, see the fixture):

| Field | Notes |
|---|---|
| `id` | UUID made by the client. The idempotency key. |
| `libraryItemId`, `episodeId` | Required to find the item. Unknown item: `Media item not found`. |
| `currentTime` | Position at the end of the session, seconds. |
| `timeListening` | **Total** real seconds listened in this session. Note the name: `timeListening` here, `timeListened` (a delta) in online sync. |
| `startedAt`, `updatedAt` | Epoch ms. `updatedAt` decides whether progress is applied. |
| `startTime` | Position at session start. Defaults to 0. |
| `date`, `dayOfWeek` | Optional `YYYY-MM-DD` and English weekday name. Used as given when the session is first stored. See section 11. |
| `displayTitle`, `displayAuthor` | Send them. Defaults are the item title and author, which for an episode is the **podcast** title, not the episode title. |
| `playMethod`, `mediaPlayer`, `mediaType` | Stored as sent (`playMethod: 3` is "local"). Null if missing. |
| `mediaMetadata`, `chapters`, `coverPath` | Optional. Missing metadata keys are filled from the item. |
| `duration` | Ignored: the server uses the item's duration. |
| `userId`, `serverVersion`, `libraryId`, `bookId` | Overwritten or filled by the server. |

### How the server merges (live)

1. **Session row.** If no session with that `id` exists, it is inserted. If one exists, the server **replaces** `currentTime`, `timeListening` and `updatedAt`. So sending the same session id twice does **not** double count: stats went 92 to 132 (first send, 40 s), to 162 after re-sending the same id with `timeListening: 70`, and stayed 162 when the identical payload was sent again.
2. **Progress.** If the user has no progress for the item, it is created from the session (`currentTime`, `progress = currentTime / duration`); its `lastUpdate` is then the server time of the upload, not the session's `updatedAt`. If progress exists and its `lastUpdate` is **newer than the session's `updatedAt`**, progress is left alone and the result says `progressSynced: false` (the session is still stored for stats). Otherwise progress is updated to the session's position with `lastUpdate` set to the session's `updatedAt`. The library's auto-finish rule applies.
3. When progress changed, the server emits socket `user_item_progress_updated` with `sessionId` set to the local session id.
4. Nothing checks plausibility: a `timeListening` of 600 s on a 360 s book was accepted.

Gotcha: when an existing session is updated, the server recomputes its `date` and `dayOfWeek` from the new `updatedAt` in the **server's** timezone and ignores any `date` in the payload. Re-sending a session with a later `updatedAt` moved its whole listening time to the new day (live). Send each finished local session once, with its final values.

---

## 11. Listening stats

### `GET /api/me/listening-stats` (live)

Fixture: `me_listening_stats.json`.

```json
{
  "totalTime": 850,
  "items": {
    "<libraryItemId>": {"id": "<libraryItemId>", "timeListening": 60, "mediaMetadata": {"title": "...", "...": ""}}
  },
  "days": {"2026-11-12": 250, "2026-11-11": 600},
  "dayOfWeek": {"Thursday": 250, "Wednesday": 600},
  "today": 250,
  "recentSessions": [ { "...": "the 10 most recently updated sessions, full objects" } ]
}
```

- All values are **seconds of real listening**: the sum of the `timeListened` the clients sent (or `timeListening` of local sessions). Playback speed plays no part.
- `items` is keyed by library item id. For podcasts all episodes of a show add up under the podcast item id.
- `days` only has days with listening. `dayOfWeek` keys are English names.
- The whole thing is computed from all of the user's sessions on every call. It is not paged.

**Day bucketing (source and live):**

- Each session lands in **one** day: its `date` field. For a streamed session that is the **server-local date when the session was opened**. A session that runs past midnight is **not** split.
- "Server-local" means the server process timezone. The dev container has no `TZ` set, so it is UTC; `serverSettings.timeZone` in the login payload reports it (`"UTC"`).
- `today` compares against the server's current date.
- For a local session the client may send its own `date` and `dayOfWeek` on first upload and the server stores them as given (live: a session uploaded today with `date: "2026-11-11"` landed under 2026-11-11). If they are missing, the server derives them from `updatedAt` in server time.

Consequence for Phase 7: the pre-bucketed `days` are in server time and cannot be re-bucketed. For device-local days and midnight splitting, build the buckets from `GET /api/me/listening-sessions` (`startedAt`, `updatedAt`, `timeListening`); a session only tells its total and its start and end, so a split across midnight is an estimate.

### `GET /api/me/listening-sessions?itemsPerPage=10&page=0` (live)

`{total, numPages, page, itemsPerPage, sessions}`, newest `updatedAt` first. A session: `{id, userId, libraryId, libraryItemId, bookId, episodeId, mediaType, mediaMetadata, chapters, displayTitle, displayAuthor, coverPath, duration, playMethod, mediaPlayer, deviceInfo, serverVersion, date, dayOfWeek, timeListening, startTime, currentTime, startedAt, updatedAt}`. Fixture: `me_listening_sessions.json`.

`currentTime - startTime` is the book time covered, `timeListening` the real time: together they give the "speed dividend".

### `GET /api/me/item/listening-sessions/:itemId[/:episodeId]` (live)

Same paged shape, for one book or one episode. For the per-book stats block.

### `GET /api/me/stats/year/:year` (live)

`{totalListeningSessions, totalListeningTime, totalBookListeningTime, totalPodcastListeningTime, topAuthors: [{name, time}], topGenres: [{genre, time}], mostListenedNarrator: {name, time}, mostListenedMonth: {month, time}, numBooksFinished, numBooksListened, longestAudiobookFinished, booksWithCovers: [ids], finishedBooksWithCovers: [ids]}`. `mostListenedMonth.month` is **zero-based** (10 for November). Fixture: `me_stats_year.json`.

---

## 12. Playlists and collections

### Playlists (live unless noted)

Playlists belong to one user and one library. Other users, admins included, get `403` (live: `root` reading `affluent`'s playlist).

Playlist: `{id, name, libraryId, userId, description, lastUpdate, createdAt, items}`. Book item: `{libraryItemId, libraryItem}`. Episode item: `{libraryItemId, libraryItem, episodeId, episode}`. `libraryItem` is a full item.

| Call | Body | Notes |
|---|---|---|
| `GET /api/playlists` | | `{"playlists": [...]}` across libraries |
| `GET /api/libraries/:id/playlists` | | paged shape, one library |
| `POST /api/playlists` | `{libraryId, name, description?, items?: [{libraryItemId, episodeId?}]}` | `200` the playlist. `400 Invalid playlist data` without name or library. A playlist is all books or all episodes. |
| `GET /api/playlists/:id` | | the playlist |
| `PATCH /api/playlists/:id` | `{name?, description?, items?}` | Rename, or **reorder** by sending the complete item list in the new order. A list of a different length: `400 Invalid playlist items. Length mismatch`. |
| `DELETE /api/playlists/:id` | | `200` (source only) |
| `POST /api/playlists/:id/item` | `{libraryItemId, episodeId?}` | `400 Item already in playlist` on a duplicate |
| `DELETE /api/playlists/:id/item/:libraryItemId[/:episodeId]` | | returns the playlist. **Removing the last item deletes the playlist.** |
| `POST /api/playlists/:id/batch/add` | `{items: [{libraryItemId, episodeId?}]}` | live |
| `POST /api/playlists/:id/batch/remove` | same | source only; also deletes the playlist when it becomes empty |
| `POST /api/playlists/collection/:collectionId` | | makes a playlist from a collection (source only) |

Socket: `playlist_added`, `playlist_updated`, `playlist_removed`, each with the full playlist, sent to the owner only.

### Collections (live for reads)

Library-wide. Any user with library access can read them (`GET /api/libraries/:id/collections`, `GET /api/collections/:id`). Creating and editing needs `permissions.update` (live: `403` for `affluent`, `200` for `root` with `{libraryId, name, description, books: [itemIds]}`). Earloom treats them as read-only.

---

## 13. Podcasts

### Reading (any user with library access, live)

- Episodes come inside the expanded podcast item (section 8). There is no paged episode list endpoint.
- `GET /api/podcasts/:id/episode/:episodeId`: one episode `{libraryItemId, podcastId, id, oldEpisodeId, index, season, episode, episodeType, title, subtitle, description, enclosure, guid, pubDate, chapters, audioFile, publishedAt, addedAt, updatedAt}`. Fixture: `podcast_episode.json`.
- `GET /api/libraries/:id/recent-episodes` (section 7).
- Progress is per episode: `GET`/`PATCH /api/me/progress/:itemId/:episodeId`.
- Play: `POST /api/items/:itemId/play/:episodeId`.
- `GET /api/podcasts/:id/downloads` gives `{"downloads": []}` and `GET /api/libraries/:id/episode-downloads` gives `{"queue": []}`: the server-side download queue (live, both readable by a normal user).

### Admin actions

The gate is the **user type** (`admin` or `root`), not a permission flag. A normal user gets `403 Forbidden` (live for every row marked 403). Request and response bodies are from source: the dev container has no internet access, so no real feed could be fetched.

| Action | Endpoint | Gate | Body and result (source only) |
|---|---|---|---|
| Search for podcasts | `GET /api/search/podcast?term=<text>&country=us` | any user | iTunes search. Array of `{id, artistId, title, artistName, description, descriptionPlain, releaseDate, genres, cover, trackCount, feedUrl, pageUrl, explicit}`. Live call returned `[]`. |
| Preview a feed | `POST /api/podcasts/feed` | admin (403 live) | `{"rssFeed": "<url>"}` gives `{"podcast": {...}}` (feed metadata with `metadata.feedUrl`, and the feed's episodes; exact keys not captured). `400` bad URL, `404` feed failed. |
| Add a podcast | `POST /api/podcasts` | admin (403 live) | `{libraryId, folderId, path, media: {metadata: {...}, autoDownloadEpisodes, autoDownloadSchedule}}`. `path` must be inside the library folder. Returns the new item. `400 Podcast already exists`. |
| Check for new episodes | `GET /api/podcasts/:id/checknew?limit=3` | admin (403 live) | `{"episodes": [...]}`; also queues downloads of up to `limit` new ones. `400` if the podcast has no feed URL. |
| Download episodes to the server | `POST /api/podcasts/:id/download-episodes` | admin (403 live) | a JSON array of episode objects taken from the feed preview. `200`. |
| Clear the download queue | `GET /api/podcasts/:id/clear-queue` | admin (403 live) | `200` |
| Find an episode in the feed | `GET /api/podcasts/:id/search-episode?title=` | any user | `{"episodes": [...]}`; `400` without a feed URL (live) |
| Edit feed URL or auto-download schedule | `PATCH /api/items/:id/media` | `permissions.update` (403 live) | `{metadata: {feedUrl}, autoDownloadEpisodes, autoDownloadSchedule}` (cron string, `400` if invalid). Returns `{updated, libraryItem}`. |
| Edit an episode | `PATCH /api/podcasts/:id/episode/:episodeId` | `permissions.update` (403 live) | episode fields |
| Delete an episode | `DELETE /api/podcasts/:id/episode/:episodeId?hard=1` | `permissions.delete` (403 live) | |

Show admin actions when `user.type` is `admin` or `root`; for the edit and delete rows also check the matching permission flag (admins have them by default).

Socket events for podcasts (source only): `episode_added`, `episode_download_queued`, `episode_download_started`, `episode_download_finished`, `episode_download_queue_cleared`, and `item_updated` for the podcast item.

---

## 14. Socket

socket.io v4 (the server ships socket.io 4.7.4). Path `/socket.io` (with a subpath install, `<subpath>/socket.io` as well). Both long-polling and a direct WebSocket transport work (live). Connecting needs no credentials.

### Authentication (live)

1. Connect.
2. Emit **`auth`** with the **access token as a bare string**: `socket.emit('auth', accessToken)`. Not an object.
3. Success: the server emits **`init`** `{"userId": "...", "username": "..."}`. Admins also get `usersOnline: [{id, username, type, session, lastSeen, createdAt, connections}]`.
4. Failure: the server emits **`auth_failed`** `{"message": "..."}` and leaves the connection open. Messages: `Invalid token` (garbage, or a refresh token), `Token expired`, `Invalid user`, `Invalid API key`, `API key expired`.

A connected socket that never sends `auth` receives nothing (live).

Fixtures: `socket_init.json`, `socket_init_admin.json`, `socket_auth_failed.json`.

### When the access token expires mid-connection (live, 60 s tokens)

**Nothing happens.** The token is only checked when `auth` is emitted. The socket stayed connected and kept receiving `user_item_progress_updated` after its token had expired. The server does not disconnect and sends no event.

- Emitting `auth` again with the expired token gives `auth_failed {"message": "Token expired"}`, but the socket **stays associated with the user** and keeps receiving events.
- Emitting `auth` again with a fresh token on the same connection works and answers `init` again. No reconnect is needed after a rotation.
- After any reconnect the client must emit `auth` again with the current access token; an expired one then really fails, so refresh first.
- `ping` (application event) answers `pong`.

### Events Earloom cares about

| Event | Sent to | Payload | Trigger | Verified |
|---|---|---|---|---|
| `user_item_progress_updated` | the user's sockets | `{id, sessionId, deviceDescription, data: <progress object>}` | session sync, session close with a payload, local session sync that changed progress | live |
| `user_updated` | the user's sockets | the **whole user object** (same as `GET /api/me`, including `mediaProgress`, `bookmarks` and the legacy `token`) | `PATCH` progress (single and batch), delete progress, bookmark create, update, delete, hide from continue listening | live |
| `user_session_closed` | the user's sockets | the session id as a bare string | session close | live |
| `item_updated` | users who can access the item | the full expanded item | metadata or file change | live |
| `item_added` | same | the full expanded item | new item | source only |
| `items_updated`, `items_added` | same | **array** of expanded items | scans and batch edits | source only |
| `item_removed` | all signed-in sockets | `{id, libraryId}` | item deleted | source only |
| `playlist_added`, `playlist_updated`, `playlist_removed` | the owner | the full playlist | playlist changes | live (`playlist_updated`) |
| `collection_added`, `collection_updated`, `collection_removed` | all | the collection | collection changes | source only |
| `series_added`, `series_updated`, `series_removed`, `author_added`, `author_updated`, `author_removed` | all | the entity | metadata changes | source only |
| `library_added`, `library_updated`, `library_removed` | all | the library | admin changes | source only |
| `episode_added` and the `episode_download_*` events | all | episode or download object | podcast downloads | source only |
| `stream_reset` | all | `{startTime, streamId}` | HLS transcode restarted at a new position | source only |
| `admin_message` | all | a string | admin broadcast | source only |

Fixtures: `socket_user_item_progress_updated.json`, `socket_user_item_progress_updated_episode.json`, `socket_user_updated.json`, `socket_user_session_closed.json`, `socket_item_updated.json`, `socket_playlist_updated.json`.

Notes:

- **Progress changes arrive on two different events.** Playback elsewhere arrives as `user_item_progress_updated` (one item). Mark finished, manual progress edits and anything through `PATCH /api/me/progress` arrive as `user_updated` (diff the `mediaProgress` array). A client that only listens to the first misses "marked finished on the web".
- `deviceDescription` in `user_item_progress_updated` is a display string (`"Probe SDK 34 / v0.0.1"`); `sessionId` lets the player ignore echoes of its own session.
- `user_updated` contains the legacy token. The socket logger must redact it like HTTP logs.
- Admin sockets additionally get `user_online`, `user_offline`, `user_stream_update` and task events. Ignore them.

---

## 15. Fixtures and the probe script

### Fixtures

`test/fixtures/abs/<area>_<name>.json` are real responses from the dev server, captured on 2026-11-12 as `affluent` (plus `root` for `socket_init_admin.json`).

- Tokens and IP addresses are replaced with `"<redacted>"`. The `affluent` user has no email (`null`).
- Long arrays of objects are cut to 2 or 3 entries, so counts such as `total`, `numTracks` and `duration` do not match array lengths. The play session fixtures keep **all** `audioTracks` and `chapters`; `item_*_expanded` keep all chapters and (podcast) all episodes.
- `libraryFiles` keeps one file per `fileType`.
- Three files are not raw responses: `auth_error_bodies.json` (a hand-made table of the error statuses and bodies seen live), `session_sync_request.json` and `session_local_all_request.json` (request bodies the server accepted). `session_local_all_response.json` is the real response to an earlier three-session batch (one stale, one unknown item).
- Socket fixtures hold the first argument of the event.

| Area | Files |
|---|---|
| server | `server_status`, `server_ping` |
| auth | `auth_login`, `auth_refresh`, `auth_authorize`, `auth_logout`, `auth_error_bodies` |
| me | `me_user`, `me_items_in_progress`, `me_progress_book`, `me_progress_episode`, `me_bookmark_create`, `me_bookmarks`, `me_listening_stats`, `me_listening_sessions`, `me_stats_year`, `me_auth_sessions` |
| libraries | `libraries_list`, `library_items_page`, `library_items_page_podcast`, `library_items_series_filter`, `library_items_collapsed_series`, `library_personalized_book`, `library_personalized_podcast`, `library_series`, `library_series_one`, `library_authors`, `library_narrators`, `library_collections`, `library_playlists`, `library_playlists_podcast`, `library_filterdata_book`, `library_filterdata_podcast`, `library_search_book`, `library_search_podcast`, `library_recent_episodes` |
| items | `item_book_expanded`, `item_book_expanded_m4b`, `item_podcast_expanded`, `podcast_episode`, `author_expanded` |
| sessions | `session_play_book_multifile`, `session_play_book_m4b`, `session_play_book_transcode_hls`, `session_play_episode`, `session_sync_request`, `session_local_all_request`, `session_local_all_response` |
| socket | `socket_init`, `socket_init_admin`, `socket_auth_failed`, `socket_user_item_progress_updated`, `socket_user_item_progress_updated_episode`, `socket_user_updated`, `socket_user_session_closed`, `socket_item_updated`, `socket_playlist_updated` |

### `tool/api_probe.dart`

`dart run tool/api_probe.dart [--url=http://localhost:13378]`. Uses only `dart:io` and `dart:convert`. Logs in as `affluent` with the password from `tool/abs-dev/.env.local` (never printed), runs 39 checks over the endpoints above (including Range on the public track route, HLS without auth, refresh rotation, the refresh-token-as-Bearer check and the socket `auth` handshake) and prints `OK` or `FAIL` with what differed. Exit code 1 on any failure. Each run uses 5 of the 40 rate-limited auth requests.

---

## 16. Security advisories and minimum version

### CVE-2026-73085: refresh token accepted as access token (confirmed)

Confirmed on the ABS GitHub security advisories page on 2026-11-12:

- Advisory **GHSA-798w-wv6c-2c3h**, "Moderate Severity: Refresh Token Accepted on Resource Endpoints", CVE id **CVE-2026-73085**, severity Moderate, published 2026-08-04.
- The advisory lists affected versions as `2.35.0` and patched versions as `2.36.0`. It does not spell out whether versions before 2.35.0 are affected; since the refresh tokens exist from 2.26.0 and the fix is a new type check, treat everything from 2.26.0 up to and including 2.35.x as affected.
- The fix in source (2.37.2): the Bearer and socket checks reject any JWT whose `type` claim is `refresh`, so a refresh token is only accepted at `POST /auth/refresh`. Live: `GET /api/me` with a refresh token returns 401, and socket `auth` with a refresh token returns `auth_failed`.

The plan's CVE id and fixed version are both right.

### Not in the plan: critical cover endpoint path traversal

The same advisories page lists a **Critical** one (CVSS 4.0 score 9.4) that the plan does not mention:

- **GHSA-m5hp-x2xc-7jqq**, "Unauthenticated path traversal leading to constrained and unconstrained arbitrary file read", published 2026-10-19, **no CVE id**. It is in the unauthenticated cover endpoint `/api/items/{id}/cover`.
- The advisory's version fields contradict each other: affected `<= v2.36.1`, patched `>= v2.36.1`, and its text says 2.36.1 is still partly affected.
- Release notes: 2.36.1 says "Cover endpoints only allow `webp`, `jpeg` and `png` as optional format param"; **2.37.0** says "Cover and author image cache endpoints require a valid id and positive width/height". The 2.37.2 source checks that the id is a UUID before touching the cache path.
- Reading these together, the complete fix looks to be **2.37.0**. That is an inference from the release notes and source, not a statement in the advisory.

This is a server-side hole (it does not involve the client), but it is more serious than the one the plan warns about. The plan's admin warning threshold is raised from 2.36.0 to 2.37.0 to cover it.

A related Moderate advisory, GHSA-mq55-hpc4-49gf ("Unbounded image resize parameters allow CPU and disk exhaustion via ffmpeg", 2026-08-11), is why cover `width` and `height` are clamped to 4096 in 2.37.2. Its fixed version was not looked up.

### Minimum version 2.26.0 (confirmed)

- The v2.26.0 release notes say: "JWT authentication with refresh tokens to replace old authentication system", "Session model for managing sessions in the new auth system" and "Rate limiter for authentication endpoints". The release page shows "12 Jul" without a year.
- The maintainer's announcement, discussion #4460 ("New JWT authentication", posted 2025-07-05), describes `x-return-tokens: true` on `/login`, `x-refresh-token` on `/auth/refresh` and `/logout`, `user.accessToken` and `user.refreshToken`, rotation on every use, and says the old `user.token` stays "for backwards compatibility".
- Not checked: whether every detail in this document (the refresh grace period, `/api/me/sessions`, the exact error bodies) already exists in 2.26.0. Only 2.37.2 was tested. The grace period in particular may be newer; the client must work with and without it (the probe accepts both).

---

## 17. Answers to the Phase 0 questions

In the order of `docs/plan/01-phase0-recon-scaffold.md`, section 0.2.

**1. Does `/status` return `serverVersion` and `authMethods`? Exact shape of the OIDC button config (`authFormData`)?**
Yes to both (live). `authMethods` is a list of `local` and `openid`. `authFormData` always has `authLoginCustomMessage` (sanitized HTML string). When OIDC is on it also has `authOpenIDButtonText` (string, default `Login with OpenId`) and `authOpenIDAutoLaunch` (bool). The OIDC part is source only. Section 3.

**2. Login with `x-return-tokens: true`: exact field names? Is legacy `user.token` still present?**
`user.accessToken` and `user.refreshToken`, both JWTs (live). Yes, `user.token` (a JWT with no expiry) is still present and still accepted by the server. Do not use it. Section 4.

**3. Refresh: body or header? Rotation? Same refresh token used twice?**
Header only: `x-refresh-token`, no body (a body is ignored). Every refresh returns a new refresh token. Using the previous refresh token again within the 10 minute grace period returns 200 with the current (already rotated) refresh token and a fresh access token. After the grace period, or for older tokens, it returns `401 {"error":"Invalid refresh token"}` and the newer session is **not** revoked. All live. Section 4.

**4. OIDC mobile flow: query params, how the callback returns tokens, does `x-return-tokens` apply, where admins whitelist redirect URIs?**
Source only, to be live-tested in Phase 1. Required on `/auth/openid`: `code_challenge` and `redirect_uri` (whitelisted). Optional: `code_challenge_method` (must be `S256`), `response_type` (must be `code`), `state`. `client_id` is ignored. The app must keep the cookies from that call and send them to `GET /auth/openid/callback?state=&code=&code_verifier=`, which answers with the login JSON including `user.accessToken` and `user.refreshToken`. `x-return-tokens` does not apply; the `auth_method=openid-mobile` cookie decides. Whitelist: ABS Settings, Authentication, "Allowed Mobile Redirect URIs". Section 5.

**5. `POST /api/items/:id/play` request body and PlaybackSession response?**
Body: `deviceInfo` (`deviceId`, `clientName`, `clientVersion`, `manufacturer`, `model`, `sdkVersion`), `forceDirectPlay`, `forceTranscode`, `supportedMimeTypes`, `mediaPlayer`. All five plan fields exist. A missing `supportedMimeTypes` forces a transcode. Response has `id`, `audioTracks[].{index, contentUrl, startOffset, duration, mimeType, codec, title, metadata}`, `chapters[].{id, start, end, title}`, `currentTime`, `startTime`, `duration`, `playMethod`, `displayTitle`, `displayAuthor`, `mediaMetadata`, `deviceInfo`, `libraryItem`. Live. Section 9.

**6. Does `GET /public/session/:id/track/:index` stream without auth? Range? When does it stop?**
Yes, with no auth header at all. Yes, Range works (206 with `Content-Range`). It returns 404 as soon as the session is closed, and also when the session is replaced by a new one from the same device, after a server restart, or after 36 hours without a sync. `:index` is the track's 1-based `index`. Live (the 36 hour rule: source only). Section 9.

**7. Session sync body and how often the official app syncs?**
`{currentTime, timeListened, duration}`: `currentTime` is the whole-book position, `timeListened` the real seconds since the last sync, `duration` optional. The official mobile app syncs every 15 s on unmetered networks and at most every 60 s on metered ones; the web client every 10 s after a first sync at 20 s. Section 9.

**8. Local session shape for `/api/session/local` and `/local-all`, and how the server merges?**
`local` takes one session object; `local-all` takes `{deviceInfo, sessions: [...]}` and returns per-session results. Minimum fields: `id`, `libraryItemId` (plus `episodeId`), `currentTime`, `timeListening` (a total, not a delta), `startedAt`, `updatedAt`. Merge: the session row is inserted or replaced by id (no double counting), and progress is updated only if the server's progress is not newer than the session's `updatedAt`. Live. Section 10.

**9. Does the cover endpoint require auth? Query params?**
No auth. `width` (default 400, max 4096, upscales), `height` (distorts unless you know what you are doing), `format` (`webp`, `jpeg`, `png`), `raw=1` (original file), `ts` (adds a cache header). Live. Section 8.

**10. Socket: auth event name and payload, expiry mid-connection, event names and payloads?**
Emit `auth` with the access token string; the reply is `init` (or `auth_failed`). When the access token expires mid-connection nothing happens: the socket keeps working. Progress arrives as `user_item_progress_updated` (playback) or `user_updated` (manual edits, finished flag, bookmarks); items as `item_updated`, `item_added`, `items_updated`, `items_added` (full items) and `item_removed` (`{id, libraryId}`). Live except the item add and remove events. Section 14.

**11. Download endpoint for individual audio files, and does it need auth?**
`GET /api/items/:itemId/file/:ino/download`, with `ino` from `media.audioFiles[].ino` (or `media.tracks[]`). Needs a Bearer token and the `download` permission. Supports Range and `If-Range`, so downloads can resume. `GET /api/items/:itemId/file/:ino` is the same without the attachment header and without the permission check. Live. Section 8.

**12. Listening stats shape?**
`{totalTime, items, days, dayOfWeek, today, recentSessions}`, all six present, values in seconds of real listening. Days are bucketed in the server's timezone, one bucket per session. Live. Section 11.

---

## 18. Differences from the plan

Where the plan docs guessed wrong or left something out. "Overview" is `00-overview.md`; "P1" to "P7" are the phase docs.

### Auth and accounts

1. **`/api/authorize` is POST, not GET** (overview API map, P1 1.3). `GET` returns 404.
2. **A reused refresh token does not log the user out** (overview rule 10, P1 1.5). The previous token is honored for 10 minutes and returns the current one; older tokens get a 401 but the session survives. Single-flight refresh is still right (it saves rate-limit budget and avoids confusion), but "two refreshers will log the user out" is not what 2.37.2 does. Older servers may have no grace period.
3. **`/auth/refresh` never returns 403** (P1 1.5 says "401 or 403"). It returns 401 for a dead token and **429** when rate limited. 429 must be handled as "wait", never as sign-out.
4. **The rate limit window is 10 minutes, shared, and counts successes** (P1 1.3 "wait a minute"). 40 auth requests per IP per 10 minutes over login, refresh, OIDC and password change. Use the `RateLimit-Reset` header for the wait time. The P1 soak test with 60 second tokens must stay under 4 refreshes a minute per IP.
5. **401 responses carry no reason** (P1 1.5). Body is the text `Unauthorized` for expired, invalid and revoked alike.
6. **Logout does not kill the access token** (P1 1.8). It stays valid until `exp` (up to an hour by default).
7. **Token lifetimes vary by server version and config.** 2.37.2 defaults are 1 hour and 30 days; the 2.26.0 announcement names 12 hours and 7 days. The plan's "refresh when under 2 minutes remain" must come from the JWT `exp` (it does).
8. **There is no server name** in `/status` or the login payload (P1 1.1 `serverName` "from server settings if present"). Use the host name or let the user name it.
9. **OIDC: `client_id` is ignored and `x-return-tokens` does not apply** (overview API map, P0 question). The flow depends on cookies set by `GET /auth/openid` being sent back to `/auth/openid/callback`. If the `auth_method` cookie is lost the server answers with a web-login redirect instead of the token JSON. The web flow itself puts tokens in a redirect URL and must not be used.
10. **The server accepts `?token=` on API URLs and the legacy `user.token`.** Not in the plan; listed so nobody uses them.

### Library and items

11. **Podcast shelf ids** (P5 5.2 lists `episodes-recently-added`). The real ids are `continue-listening`, `newest-episodes`, `recently-added`, `listen-again`.
12. **Extra shelves exist** (P2 2.3): `continue-reading` and `read-again` (ebooks). Shelves are omitted when empty, and the response is a bare array.
13. **Lists never include progress** (P2 2.1, 2.3 "cover cards with progress ring overlay"). Progress comes from `user.mediaProgress` (login, `/api/me`) and the socket, joined by item id on the client.
14. **No `coverUpdatedAt` field** (P0 0.5, P2 2.1, 2.8). Use the item's `updatedAt`.
15. **Covers need no auth** (overview stack table "cached_network_image (with auth headers)", P2 2.8). Sending the Bearer header is unnecessary; custom reverse-proxy headers may still be needed. Also: resized covers have no cache headers and no length, `height` alone distorts, and the default width is 400.
16. **Series sequence is not in the series list** (P2 2.1 `series_items.sequence`). `/series` books only carry it inside `seriesName`. Use `items?filter=series.<base64 id>&sort=sequence`, the expanded item, or the author endpoint.
17. **Filter values are base64 then URL-encoded** (P2 2.4). Narrator "ids" are just the encoded name.
18. **`filterdata` counts are zero** on the dev server (`bookCount` and friends). Do not show them.
19. **`minified=1` made no difference on `/items`** in 2.37.2 (P2 2.2). Harmless to keep sending.
20. **Authors list shape depends on paging**: `{authors: [...]}` without `limit` and `page`, `{results, total, ...}` with them.

### Player

21. **Missing `supportedMimeTypes` means transcode** (P3 3.2). The plan sends it, good; an empty or missing list silently turns every book into HLS.
22. **Starting a session closes the same device's other sessions**, sessions live in server memory (gone after a restart, seen live), and a closed or unknown session answers **404** on sync (P3 3.6 "if the server says the session no longer exists").
23. **The public track URL uses the track's `index` (1-based)**, dies with the session (404), and redirects to HLS for transcodes (P3 3.2, P10 Chromecast). `contentUrl` is relative and needs a Bearer token.
24. **HLS is `/hls/<sessionId>/output.m3u8` with no auth**, one track covering the whole book (P3 3.2).
25. **A sync without `currentTime` blanks the stored position; strings are stored as strings.** Not in the plan. Always send numbers.
26. **`/play` on a podcast item without an episode id "succeeds" with a broken session.** Not in the plan.
27. **Bookmarks** (P3 3.9 "round to the whole second and nudge +1s if one already exists there"): fractional times are allowed, so two bookmarks in the same second can simply keep their fractional times. A second `POST` at an existing time overwrites the title instead of failing. `time` must be sent as a number or the bookmark becomes undeletable. Bookmarks have no episode id.
28. **`PATCH /api/me/progress` does not compute `progress`** and has no conflict check; `lastUpdate` can be set by the client (P3 3.7, P4 4.7). Send `currentTime`, `duration`, `progress` together and compare timestamps client-side before overwriting, as the plan already intends.
29. **Auto finish at under 10 seconds left** is done by the server (library setting), not only by the client (P3 3.10 uses 5 seconds). The server may mark a book finished before the client does.

### Offline

30. **Local sessions use `timeListening` (total), online sync uses `timeListened` (delta)** (P4 4.1 column `timeListened`).
31. **`/api/session/local` answers 500 for a permanent per-session failure** such as a deleted item (P4 4.7 "4xx other than 401 means the payload is bad"). `local-all` answers 200 with `success: false` per entry. Use `local-all` and dead-letter on `success: false`.
32. **Re-sending a local session with a later `updatedAt` moves its day bucket**, and the server ignores a session's progress if server progress is newer (P4 4.6). Upload each local session once, when it is final. The online direct progress sync the plan describes is fine.
33. **Offline downloads**: `/api/items/:id/file/:ino/download` needs the `download` permission (403 otherwise); the whole-item ZIP endpoint is not resumable (P4 4.3 leaves the URL open).

### Podcasts

34. **Admin actions are gated by user type, not permission names** (P5 5.5 "verify permission names"). `admin` or `root` for add, feed preview, check new, download episodes; `permissions.update` and `permissions.delete` for edits and deletes. `checknew` and `clear-queue` are GET requests with side effects.
35. **Podcast search (`/api/search/podcast`) is open to every user** and needs the server to reach the internet.

### Stats

36. **Server day buckets are in server time and are not split at midnight** (P7 7.1). Client-supplied `date` is honored for new local sessions. Device-local buckets must be built from the sessions list.
37. **`mostListenedMonth.month` is zero-based.**

### Socket

38. **Manual progress changes arrive as `user_updated`, not `user_item_progress_updated`** (overview API map, P1 1.9, P2 2.2). `ProgressUpdated` must be fed from both.
39. **Batch item events exist**: `items_added` and `items_updated` carry arrays (overview lists only the singular ones). `item_removed` is `{id, libraryId}`; the others carry full items.
40. **Token expiry does not affect a connected socket** (P1 1.9 "Re-authenticate on tokensRotated"). Re-emitting `auth` after a rotation is harmless but only required after a reconnect.

### Security

41. **CVE-2026-73085 and the 2.36.0 fix are confirmed** (overview). Its advisory id is GHSA-798w-wv6c-2c3h.
42. **A critical unauthenticated file-read advisory (GHSA-m5hp-x2xc-7jqq, no CVE) was missing from the plan**; the full fix appears to be 2.37.0. The plan now warns admins below 2.37.0 (overview and P1).

---

## 19. Not verified

| Item | Why | Where it matters |
|---|---|---|
| The whole OIDC flow | No identity provider on the dev server | Phase 1 (optional `oidc` compose profile) |
| `/status` with OIDC enabled | Same | Phase 1 |
| Podcast feed preview, add, check new, download episodes: request and response bodies | The dev container has no internet access; only the 403 for a normal user was seen | Phase 5 |
| `/api/search/podcast` result shape | Live call returned `[]` | Phase 5 |
| Author image success case | No author on the dev server has an image | Phase 2 |
| `403` on file download without the `download` permission | `affluent` has that permission | Phase 4 |
| `item_added`, `item_removed`, `items_added`, `items_updated`, `stream_reset` payloads | Would need adding or deleting seed items; not triggered | Phases 2 and 3 |
| Subpath installs (`ROUTER_BASE_PATH`) | Dev server runs at `/` | Phase 1 probe |
| `X-Accel` deployments (204 plus `X-Accel-Redirect`) | Needs nginx in front | Phase 3 and 4 |
| Behavior of versions between 2.26.0 and 2.37.1 | Only 2.37.2 was run | Minimum version support |
| Fixed version of GHSA-m5hp-x2xc-7jqq | The advisory's version fields contradict each other; 2.37.0 is inferred | Security banner |
| HLS seeking far ahead of the encoder (`stream_reset`) | Not exercised | Phase 3 |
