# Phase 2: Library, home, search, item detail

Goal: browsing feels instant and gorgeous. Everything renders from the local cache first and refreshes in the background. Works offline with whatever was last synced.

Branch: `phase-2-library`

---

## 2.1 Cache schema (AccountDb)

Files: `lib/core/db/account_db.dart`, `lib/core/db/tables/*.dart`

| Table | Key columns | Notes |
|---|---|---|
| `libraries` | id, name, mediaType (book/podcast), displayOrder, icon | |
| `items` | id, libraryId, mediaType, title, titleIgnorePrefix, subtitle, authorNames, narratorNames, seriesSummary, durationSec, addedAt, updatedAt, coverUpdatedAt, isDownloaded | Minified fields for lists |
| `item_details` | itemId, json, fetchedAt | Full expanded item JSON for detail screen |
| `progress` | itemId, episodeId (nullable), currentTime, duration, progress, isFinished, finishedAt, lastUpdate | Mirrors ABS mediaProgress |
| `series` / `series_items` | seriesId, name / seriesId, itemId, sequence | Sequence is a string in ABS ("1", "1.5", "Book 2"): sort with natural ordering |
| `authors` | id, name, imagePath, description, numBooks | |
| `collections`, `playlists` (+ join tables) | | |
| `shelves` | libraryId, json, fetchedAt | Cached `/personalized` response |
| `filter_data` | libraryId, json, fetchedAt | |
| `cover_colors` | itemId, coverUpdatedAt, seedArgb | From Phase 0 |
| `sync_meta` | key, value | Last full sync times per library |

Indexes: `items(libraryId, titleIgnorePrefix)`, `items(libraryId, addedAt)`, `progress(lastUpdate)`, `series_items(seriesId)`.

### Acceptance
- [ ] Schema has a migration test (drift `SchemaVerifier`) from v1
- [ ] Natural sort for series sequence: 1, 2, 2.5, 10 (not 1, 10, 2)

---

## 2.2 Repository pattern

Every repository exposes a `Stream` from the DB and a `refresh()` that fetches and upserts. UI watches the stream. Refresh errors surface as a non-blocking state, never replace content with an error.

```dart
// lib/features/library/data/library_repository.dart
class LibraryRepository {
  LibraryRepository(this._db, this._api);
  final AccountDb _db;
  final AbsClient _api;

  Stream<List<ItemSummary>> watchItems(String libraryId, LibraryQuery q) =>
      _db.itemsDao.watchPage(libraryId, q);

  /// Pulls one page from the server and upserts it. Returns whether more pages exist.
  Future<bool> fetchPage(String libraryId, LibraryQuery q, int page) async {
    final res = await _api.libraryItems(libraryId, q.toApiParams(page: page, limit: 50, minified: true));
    await _db.itemsDao.upsertSummaries(res.results);
    return (page + 1) * 50 < res.total;
  }

  /// Full background sync of a library so offline browsing and search work.
  /// Runs on first login, then at most once per 6 hours, on Wi-Fi or when user pulls to refresh.
  Future<void> fullSync(String libraryId) async { /* page through all, delete rows not seen */ }
}
```

Freshness rules:
- Home shelves: refetch on open if older than 2 minutes.
- Item detail: refetch on open if older than 10 minutes, always after playback ends.
- Socket `ItemUpdated` / `ItemAdded` / `ItemRemoved`: refetch or delete that item.
- Socket `ProgressUpdated`: write to `progress` directly (Phase 3 handles conflicts with active playback).

### Acceptance
- [ ] Airplane mode cold start: Home, Library, Item detail and Search all render cached data
- [ ] Item deleted on server disappears from the app after the socket event or next sync

---

## 2.3 Home

File: `lib/features/home/ui/home_screen.dart`

Layout, top to bottom:
1. **Library switcher** (only if more than one library): pill at top left, opens a sheet.
2. **Hero card**: the most recently played in-progress item. Large cover, cover-tinted card background, title, author, chapter name, progress bar, time left, big Resume button. Tapping Resume starts playback without navigating.
3. **Shelves** from `/personalized` in server order: Continue listening, Continue series, Recently added, Recent series, Discover, Listen again, Newest authors. Horizontal lists, cover cards with progress ring overlay.
4. **Downloaded** shelf when offline (built locally from `isDownloaded`).

Pull to refresh refetches shelves and progress. Shelf labels come from ABS `labelStringKey` mapped to our own l10n keys; unknown keys fall back to the server `label`.

### Acceptance
- [ ] Hero card color animates when the current book changes
- [ ] Shelves render from cache in under 300ms on a mid-range Android (profile build)
- [ ] Empty states: no libraries, empty library, nothing in progress

---

## 2.4 Library tab

File: `lib/features/library/ui/library_screen.dart`

- Segmented control: Books, Series, Authors, Collections, Playlists (Podcasts libraries get their own layout in Phase 5).
- Books: grid (default) or list toggle, remembered per library.
- Sort: title, author, date added, duration, progress, published year, ascending/descending.
- Filters from `filter_data`: progress state (not started, in progress, finished), genres, tags, series, authors, narrators, languages, downloaded only. Active filters show as removable chips.
- Infinite scroll, 50 per page, prefetch next page at 70% scroll.
- Alphabet fast-scroll rail when sorted by title or author.

### Acceptance
- [ ] 5,000 item fixture library scrolls at 60fps in a profile build (perf test in `integration_test/library_scroll_test.dart`)
- [ ] Filters and sort combine correctly (matches the ABS web UI for the same query on the dev server)

---

## 2.5 Item detail

File: `lib/features/item_detail/ui/item_detail_screen.dart`

- Whole screen themed with the cover `ColorScheme` (Phase 0 `CoverSchemeService`). Background: soft vertical gradient from `primaryContainer` to `surface`.
- Header: cover (hero animation from wherever it came from), title (serif), subtitle, author links, narrator links, series link with sequence ("Book 2 of The Example Saga").
- Primary action: Play / Resume (with time left) / Listen again. Secondary row: Download (Phase 4 state), Mark finished / Mark unfinished, Add to playlist, More (share link if server supports it later, open in ABS web).
- Progress: bar plus "3 hr 12 min left, 64%".
- Description: HTML sanitized to a safe subset (paragraphs, line breaks, bold, italic, links) via `lib/core/util/html_sanitize.dart`. Collapsed to 6 lines with "More".
- Chapters: list with start times and durations, current chapter highlighted, tap to play from that chapter.
- Bookmarks (Phase 3) section if any.
- Details: genres and tags as chips (tap filters the library), publisher, published year, language, ISBN/ASIN, file format, bitrate, total size.
- More in this series: horizontal shelf.

### Acceptance
- [ ] Malicious HTML in a description (script tags, onerror attributes, javascript: links) renders as plain safe text (unit test)
- [ ] Opening the same item twice shows cached content immediately with no layout jump when fresh data arrives
- [ ] Contrast check passes on 20 random covers (golden test with contrast assertion)

---

## 2.6 Series, authors, collections, playlists

- **Series screen**: name, book count, total duration, combined progress, books in natural sequence order, "Continue series" button that plays the first unfinished book.
- **Author screen**: photo (ABS author image endpoint), bio (sanitized, collapsible), books grouped by series then standalone.
- **Narrator**: filtered library view (ABS has no narrator entity).
- **Collections**: read-only list and detail (collections are library-wide, admin-managed).
- **Playlists**: user-owned. Create, rename, delete, add/remove items, reorder (drag). Writes go through the outbox when offline (Phase 4 adds the outbox, until then require online).

### Acceptance
- [ ] Playlist edits made in the ABS web UI show in the app and vice versa
- [ ] Continue series picks the right book when earlier books are finished

---

## 2.7 Search

Files: `lib/features/search/ui/search_screen.dart`, `lib/features/search/data/search_repository.dart`

- Online: ABS library search endpoint, debounced 300ms, cancels stale requests.
- Offline: local FTS over `items` (drift FTS5 virtual table on title, subtitle, author, narrator, series).
- Results grouped: Books, Series, Authors, Narrators, Genres and tags (and Podcasts, Episodes in Phase 5).
- Recent searches stored locally, clearable.
- Search across all libraries toggle (runs per library, merges).

### Acceptance
- [ ] Typing fast never shows results for an older query after a newer one
- [ ] Offline search finds books by narrator name

---

## 2.8 Covers

File: `lib/features/library/ui/cover_image.dart`

```dart
class CoverImage extends ConsumerWidget {
  const CoverImage({super.key, required this.itemId, required this.coverUpdatedAt, required this.logicalSize, this.heroTag});
  final String itemId;
  final int coverUpdatedAt;
  final double logicalSize;
  final Object? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final px = (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
    final width = _bucket(px); // 128, 256, 512, 1024 to keep the cache small
    // 1. Downloaded cover file if present (Phase 4)
    // 2. cached_network_image with auth headers and cacheKey "$itemId-$coverUpdatedAt-$width"
    // 3. Placeholder: gradient from a hash of the title using theme tokens, plus initials
  }
}
```

- Request covers with `width` and `format=webp` (confirm params in `docs/abs-api.md`).
- Cache key includes `coverUpdatedAt` so changed covers refresh.
- Disk cache cap: 300 MB, LRU.

### Acceptance
- [ ] No cover request ever fetches a full-resolution original for a list cell
- [ ] Updating a cover on the server shows the new one after the next sync

---

## l10n keys added in Phase 2

```
homeContinueListening, homeResume, homeShelfContinueSeries, homeShelfRecentlyAdded,
homeShelfRecentSeries, homeShelfDiscover, homeShelfListenAgain, homeShelfNewestAuthors,
homeShelfDownloaded, homeEmptyNoLibraries, homeEmptyNothingInProgress, librarySwitcherTitle,
libraryBooks, librarySeries, libraryAuthors, libraryCollections, libraryPlaylists,
libraryGrid, libraryList, librarySort, librarySortTitle, librarySortAuthor, librarySortAdded,
librarySortDuration, librarySortProgress, librarySortPublished, libraryFilter,
filterNotStarted, filterInProgress, filterFinished, filterGenres, filterTags, filterNarrators,
filterLanguages, filterDownloadedOnly, filterClearAll,
itemPlay, itemResume, itemListenAgain, itemMarkFinished, itemMarkUnfinished, itemAddToPlaylist,
itemMore, itemTimeLeftPercent(timeLeft, percent), itemSeriesPosition(sequence, series),
itemDescriptionMore, itemDescriptionLess, itemChapters, itemDetails, itemGenres, itemTags,
itemPublisher, itemPublished, itemLanguage, itemFormat, itemSize, itemMoreInSeries,
seriesBooksCount(count), seriesContinue, authorBooks, authorStandalone,
playlistNew, playlistRename, playlistDelete, playlistDeleteConfirm(name), playlistEmpty,
searchHint, searchRecent, searchClearRecent, searchAllLibraries, searchNoResults(query),
searchGroupBooks, searchGroupSeries, searchGroupAuthors, searchGroupNarrators, searchGroupTags
```

## Phase 2 done when
- [ ] All section checklists ticked
- [ ] Demo video (screen recording) of Home, Library, Item detail and Search on both platforms shared with the owner for design review before Phase 3
