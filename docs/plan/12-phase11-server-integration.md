# Earloom Phase 11: Earloom Server integration

Build this after app Phase 9 and after Earloom Server (separate repo) finishes its Phase 4, since it needs the server API, requests and ABS linking. Read the server's `api/openapi.yaml` before starting.

Goal: one app for the whole audiobook life cycle. Listen through ABS, and from the same app see what is coming, request or add books, watch progress, and import your own files from the phone into the library.

Branch: `phase-11-server`

---

## Rules for this phase

1. **The app never configures sources.** No indexer settings, no download client settings, no interactive release search, no release names shown. Those live in the Earloom Server web UI. The app shows books, statuses and progress. This keeps the store listing about library management and keeps App Review simple.
2. Everything here is free, like the rest of the app. All existing global rules apply (l10n keys, no em dashes, no hardcoded colors, tokens never in URLs or logs, main isolate owns auth).
3. Every server call goes through the server's OpenAPI contract. Generate a Dart client from `api/openapi.yaml` (`openapi-generator` dart-dio or a hand-written thin client, decide in 11.1) rather than ad hoc JSON.

---

## 11.1 Connect a server

Files:
- `lib/core/net/server_client.dart` (typed client, generated or thin)
- `lib/core/db/tables/servers.dart` (GlobalDb)
- `lib/features/server_connect/ui/add_server_connection_screen.dart`

- You tab > Library server > Connect. Probe `GET /api/v1/system/status` (version, auth methods).
- Sign in with username/password (`POST /api/v1/auth/login` with device info) or OIDC. Tokens follow the same rules as ABS in Phase 1: access + rotating refresh, single-flight refresh, secure storage only. Generalize `TokenRefresher` and `AuthInterceptor` to take a service id (`abs:<accountId>` or `srv:<serverId>`) instead of duplicating them.
- Link the server connection to the current ABS account (one server per ABS account by default). The server already knows which ABS library its folders map to; the app verifies the server's configured ABS URL matches the current account's server and warns if not.
- Role awareness: admin, member, guest (from `GET /api/v1/me`) controls which screens show.

### Acceptance
- [ ] Connect, sign out, re-auth, token rotation all behave like ABS accounts (reuse the Phase 1 test suite with the server service id)
- [ ] Mismatched ABS server shows a clear warning

---

## 11.2 Status everywhere

Files: `lib/features/server/data/server_status_repository.dart`, `lib/features/item_detail/ui/server_status_section.dart`

- On ABS item detail, show the server's view of the same book (looked up by the ABS item id the server stores, then ASIN): monitored or not, other editions (for example a full-cast narration), series completeness ("3 of 7 in your library, 2 coming"), upgrade pending.
- Series and author screens show missing books from the server as ghost cards (dimmed cover, "Not in library" with Request or Add).
- Library cards can show a small "new" or "downloading" badge (setting).
- Cached in AccountDb with the same stale-while-revalidate rules as Phase 2. Offline shows last known status.

### Acceptance
- [ ] Ghost cards appear for missing series entries and disappear once ABS has the book

---

## 11.3 Discover, add and request

Files: `lib/features/discover/ui/*`

- Search gains a "Not in library" section powered by the server lookup endpoint.
- Book preview: cover-tinted, editions with narrators and runtime, series context.
- Admin: Add with monitor options (book, series, author, narrator), profile and root folder defaults from the server.
- Member: Request (book, series or author), sees quota and existing requests.
- Free and public domain: a section that searches the server's LibriVox source and adds with one tap.

### Acceptance
- [ ] Member request appears in the server within 2 seconds and shows "Pending" in the app
- [ ] Admin add triggers the server's search-on-add setting

---

## 11.4 Requests and activity

Files: `lib/features/requests/ui/*`, `lib/features/activity/ui/*`

- My requests: pending, approved, downloading (progress), available (opens the ABS item), declined (with reason).
- Admin requests inbox: approve or decline with a reason, swipe actions.
- Activity (admin): current downloads as book cards with progress and ETA (no release names), recent imports, items needing review.
- Review queue (admin, simplified): accept the top candidate or open the item in the web UI for complex cases.
- Live updates over the server's SSE stream while the screen is open; no background streaming.

### Acceptance
- [ ] Progress updates live while open and stop when the app backgrounds
- [ ] No release name, indexer name or tracker info appears anywhere in the app (UI test asserts on fixture data containing such fields)

---

## 11.5 Import from the phone

Files: `lib/features/phone_import/*`, iOS share extension `ios/ImportShareExtension/`, Android intent filters

- Entry points: You > Import files (system file picker), share sheet ("Import to library" from Files, Drive, email attachments), and drag and drop on iPad.
- Accepts audio (m4b, m4a, mp3, flac, ogg, opus) and ebook (epub, pdf) files, single or multiple, and zip folders of a book.
- Optional metadata hint before upload: search and pick the book so the server skips identification.
- Upload via the server's resumable upload endpoint using `background_downloader` upload tasks (background, resumable, progress notification). Auth headers captured at enqueue with the same refresh-then-requeue rule as Phase 4 downloads.
- After upload the app shows the import status (identifying, needs review, importing, available) and notifies when the book is in ABS.

### Acceptance
- [ ] Share a 700 MB M4B from the Files app: uploads in the background, survives app kill, ends as a correctly matched ABS item
- [ ] Unsupported file types are rejected before upload with a clear message

---

## 11.6 Calendar

- Upcoming releases for monitored authors and series, month and list views.
- "Subscribe in calendar" opens the server's iCal feed URL in the system calendar app (calendar-scoped key, created on demand by the server).

---

## 11.7 Notifications (DECIDE)

Options:
1. **In-app and local only:** status refresh on open and best-effort background refresh, local notifications for request available, import done, needs review. No servers involved. Recommended for 1.x.
2. **ntfy:** the app shows a one-tap setup that creates an ntfy target on the server (user's own ntfy URL and topic) and opens the ntfy app to subscribe. Push without Affluent Labs infrastructure.
3. **Affluent Labs push relay:** the server sends end-to-end encrypted payloads to a relay that forwards via APNs/FCM. Best experience, but it is infrastructure to run and a privacy policy change. Later, if ever.

Recommendation: ship 1 and 2.

---

## 11.8 Store listing changes

- Describe the feature as "manage and grow your self-hosted library: see what is missing from a series, request books, import your own files."
- Screenshots use public-domain books (LibriVox) only.
- The App Review demo server gets a demo Earloom Server instance with only the LibriVox source and watched folders, no indexers or download clients.
- Never mention torrents, Usenet, indexers, or any site by name in the listing, screenshots or release notes.

---

## l10n keys added in Phase 11

```
serverConnectTitle, serverConnectAddress, serverConnectSignIn, serverConnectMismatch(absUrl),
serverRoleAdmin, serverRoleMember, serverRoleGuest, serverStatusMonitored, serverStatusNotMonitored,
serverStatusOtherEditions(count), serverSeriesCompleteness(have, total, upcoming), serverGhostNotInLibrary,
serverRequest, serverRequestPending, serverRequestApproved, serverRequestDownloading(percent),
serverRequestAvailable, serverRequestDeclined(reason), serverRequestQuota(used, limit), serverAdd,
serverAddMonitorBook, serverAddMonitorSeries, serverAddMonitorAuthor, serverAddMonitorNarrator,
discoverNotInLibrary, discoverPublicDomain, requestsMine, requestsInbox, requestsApprove, requestsDecline,
requestsDeclineReason, activityTitle, activityDownloading, activityEta(time), activityRecentImports,
activityNeedsReview(count), reviewAcceptTop, reviewOpenInWeb, phoneImportTitle, phoneImportPick,
phoneImportShareTarget, phoneImportHint, phoneImportUploading(percent), phoneImportIdentifying,
phoneImportNeedsReview, phoneImportAvailable(title), phoneImportUnsupported, calendarTitle,
calendarSubscribe, notifySetupNtfy, notifyLocalOnly
```

## Phase 11 done when
- [ ] All checklists ticked
- [ ] Full loop on real devices: request a public-domain book from the app, server fetches it from LibriVox, imports, ABS scans, app notifies, book plays
