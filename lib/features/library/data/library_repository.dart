// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:drift/drift.dart' show Value;

import '../../../core/db/account_db.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_client.dart';
import '../../../core/net/abs_errors.dart';
import '../../../core/socket/abs_socket.dart';
import '../../../core/util/search_fold.dart';
import 'abs_json.dart';

/// How long cached lists count as fresh before a screen refetches them on
/// open (docs/plan/03-phase2-library.md section 2.2). Pull to refresh
/// always refetches.
abstract final class Freshness {
  static const shelves = Duration(minutes: 2);
  static const item = Duration(minutes: 10);
  static const lists = Duration(minutes: 30);
  static const fullSync = Duration(hours: 6);
}

/// The browsing data of one Audiobookshelf account: everything is written
/// to the account's cache database and read back from it, so screens render
/// instantly and offline. Each `refresh` fetches from the server and
/// upserts; errors are thrown as [AbsFailure] for the screen to show next to
/// the cached content, never instead of it.
class AbsLibraryRepository {
  AbsLibraryRepository({required this.db, required this.client, required this.source, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AccountDb db;
  final AbsClient client;
  final AbsSource source;
  final DateTime Function() _clock;

  CatalogDao get _dao => db.catalogDao;
  int get _now => _clock().millisecondsSinceEpoch;

  /// Page size of a full library sync.
  static const syncPageSize = 200;

  /// Only one full sync per library runs at a time.
  final _syncs = <String, Future<void>>{};

  Future<bool> _isStale(String key, Duration maxAge) async {
    final at = int.tryParse(await _dao.meta(key) ?? '');
    return at == null || _now - at > maxAge.inMilliseconds;
  }

  Future<void> _touch(String key) => _dao.setMeta(key, '$_now');

  /// Runs [fetch] when the data behind [key] is older than [maxAge] (or
  /// always with [force]), then records the time.
  Future<void> _fresh(String key, Duration maxAge, bool force, Future<void> Function() fetch) async {
    if (!force && !await _isStale(key, maxAge)) return;
    await fetch();
    await _touch(key);
  }

  // --- Libraries and progress ---

  Stream<List<LibraryInfo>> watchLibraries() => _dao.watchLibraries().map(
    (rows) => [
      for (final r in rows) LibraryInfo(source: source, id: r.id, name: r.name, isPodcast: r.mediaType == 'podcast'),
    ],
  );

  Future<void> refreshLibraries({bool force = false}) => _fresh('libraries', Freshness.lists, force, () async {
    final json = await client.get<Map<String, Object?>>('/api/libraries');
    await _dao.replaceLibraries([
      for (final l in AbsJson.maps(json['libraries']))
        if (AbsJson.str(l['id']) != null) AbsJson.library(l),
    ]);
  });

  /// All progress from `/api/me`, plus the in-progress items themselves so
  /// Continue listening works before a library has synced.
  Future<void> refreshProgress() async {
    final user = await client.get<Map<String, Object?>>('/api/me');
    await _writeUserProgress(user);
    final inProgress = await client.get<Map<String, Object?>>('/api/me/items-in-progress', query: {'limit': 25});
    await _dao.upsertItems([
      for (final i in AbsJson.maps(inProgress['libraryItems']))
        if (AbsJson.str(i['id']) != null) AbsJson.item(i),
    ]);
  }

  Future<void> _writeUserProgress(Map<String, Object?> user) {
    return _dao.replaceProgress([
      for (final p in AbsJson.maps(user['mediaProgress']))
        if (AbsJson.str(p['libraryItemId']) != null) AbsJson.progress(p),
    ]);
  }

  Stream<List<BookSummary>> watchContinueListening({int limit = 20}) => _dao
      .watchContinueListening(limit: limit)
      .map((rows) => [for (final r in rows) AbsJson.summary(source, r.item, r.progress)]);

  Stream<ListeningProgress?> watchProgress(String itemId) =>
      _dao.watchProgress(itemId).map((row) => row == null ? null : AbsJson.listening(row));

  /// Marks a book finished or not. The cache changes at once; the server
  /// call follows, and the cache goes back if it fails.
  Future<void> setFinished(String itemId, {required bool finished}) async {
    final before = await _dao.progressOf(itemId);
    await _dao.upsertProgress(
      ProgressCompanion.insert(
        itemId: itemId,
        progressId: Value(before?.progressId),
        currentTime: Value(finished ? (before?.currentTime ?? 0) : 0),
        duration: Value(before?.duration ?? 0),
        progress: Value(finished ? 1 : 0),
        isFinished: Value(finished),
        finishedAt: Value(finished ? _now : null),
        lastUpdate: _now,
      ),
    );
    try {
      await client.patch<Object?>('/api/me/progress/$itemId', body: {'isFinished': finished});
    } on Object {
      if (before == null) {
        await _dao.deleteProgress(itemId);
      } else {
        await _dao.upsertProgress(before.toCompanion(true));
      }
      rethrow;
    }
  }

  // --- Items ---

  Stream<List<BookSummary>> watchBooks(String libraryId, LibraryQuery query, {int? limit}) => _dao
      .watchBooks(libraryId, query, limit: limit)
      .map((rows) => [for (final r in rows) AbsJson.summary(source, r.item, r.progress)]);

  /// Pages through the whole library so browsing, filters and offline
  /// search work on everything. At most once per [Freshness.fullSync]
  /// unless forced. Items the server no longer lists are removed.
  Future<void> syncLibrary(String libraryId, {bool force = false}) {
    final running = _syncs[libraryId];
    if (running != null) return running;
    final future =
        _fresh('items:$libraryId', Freshness.fullSync, force, () async {
          final seen = <String>{};
          for (var page = 0; ; page++) {
            final json = await client.get<Map<String, Object?>>(
              '/api/libraries/$libraryId/items',
              query: {'limit': syncPageSize, 'page': page, 'minified': 1, 'sort': 'addedAt', 'desc': 1},
            );
            final results = AbsJson.maps(json['results']);
            final rows = [
              for (final r in results)
                if (AbsJson.str(r['id']) != null) AbsJson.item(r),
            ];
            seen.addAll(rows.map((r) => r.id.value));
            await _dao.upsertItems(rows);
            final total = AbsJson.integer(json['total']);
            if (results.length < syncPageSize || (page + 1) * syncPageSize >= total) break;
          }
          await _dao.deleteItemsNotIn(libraryId, seen);
        }).whenComplete(() {
          _syncs.remove(libraryId);
        });
    _syncs[libraryId] = future;
    return future;
  }

  Stream<BookDetail?> watchBook(String itemId) {
    // The list row renders the header at once; the expanded item fills in
    // the rest when it is cached, without moving what is already there.
    final controller = StreamController<BookDetail?>();
    ItemWithProgress? row;
    ItemDetailRow? detail;
    var haveRow = false;
    void emit() {
      if (!haveRow) return;
      final r = row;
      if (r == null) {
        controller.add(null);
        return;
      }
      final summary = AbsJson.summary(source, r.item, r.progress);
      final d = detail;
      if (d == null) {
        controller.add(BookDetail(summary: summary));
        return;
      }
      try {
        controller.add(AbsJson.detail(summary, AbsJson.map(jsonDecode(d.json))));
      } on FormatException {
        controller.add(BookDetail(summary: summary));
      }
    }

    late final StreamSubscription<ItemWithProgress?> a;
    late final StreamSubscription<ItemDetailRow?> b;
    controller
      ..onListen = () {
        a = _dao.watchItem(itemId).listen((value) {
          row = value;
          haveRow = true;
          emit();
        }, onError: controller.addError);
        b = _dao.watchDetail(itemId).listen((value) {
          detail = value;
          emit();
        }, onError: controller.addError);
      }
      ..onCancel = () async {
        await a.cancel();
        await b.cancel();
      };
    return controller.stream;
  }

  /// The expanded item with the user's progress. A 404 means the item is
  /// gone from the server: it is removed from the cache.
  Future<void> refreshItem(String itemId, {bool force = false}) async {
    final cached = await _dao.detail(itemId);
    if (!force && cached != null && _now - cached.fetchedAt < Freshness.item.inMilliseconds) return;
    final Map<String, Object?> json;
    try {
      json = await client.get<Map<String, Object?>>(
        '/api/items/$itemId',
        query: {'expanded': 1, 'include': 'progress'},
      );
    } on AbsHttpError catch (e) {
      if (e.status == 404) await _dao.deleteItem(itemId);
      rethrow;
    }
    await _writeExpanded(json);
    final progress = json['userMediaProgress'];
    if (progress is Map) await _dao.upsertProgress(AbsJson.progress(AbsJson.map(progress)));
  }

  Future<void> _writeExpanded(Map<String, Object?> json) async {
    final id = AbsJson.str(json['id']);
    if (id == null) return;
    final copy = Map<String, Object?>.from(json)..remove('userMediaProgress');
    await _dao.upsertItems([AbsJson.item(copy)]);
    await _dao.putDetail(id, jsonEncode(copy), _now);
    final meta = AbsJson.map(AbsJson.map(json['media'])['metadata']);
    final series = AbsJson.maps(meta['series']);
    if (series.isNotEmpty) {
      await _dao.mergeSeries(
        [for (final s in series) AbsJson.series(s, libraryId: AbsJson.str(json['libraryId']))],
        [for (final s in series) AbsJson.seriesMember(s['id'] as String, id, AbsJson.str(s['sequence']), 0)],
      );
    }
  }

  // --- Series ---

  Stream<List<SeriesSummary>> watchSeriesList(String libraryId) =>
      _dao.watchSeriesList(libraryId).map((list) => [for (final s in list) _seriesSummary(s)]);

  Stream<SeriesSummary?> watchSeries(String seriesId) =>
      _dao.watchSeries(seriesId).map((s) => s == null ? null : _seriesSummary(s));

  SeriesSummary _seriesSummary(SeriesWithBooks s) => SeriesSummary(
    source: source,
    id: s.series.id,
    name: s.series.name,
    description: s.series.description,
    books: [for (final b in s.books) AbsJson.summary(source, b.item, b.progress)],
    bookCount: s.books.length,
  );

  Future<void> refreshSeriesList(String libraryId, {bool force = false}) =>
      _fresh('series:$libraryId', Freshness.lists, force, () async {
        final rows = <SeriesCompanion>[];
        final members = <SeriesItemsCompanion>[];
        final books = <ItemsCompanion>[];
        for (var page = 0; ; page++) {
          final json = await client.get<Map<String, Object?>>(
            '/api/libraries/$libraryId/series',
            query: {'limit': 100, 'page': page},
          );
          final results = AbsJson.maps(json['results']);
          for (final s in results) {
            final id = AbsJson.str(s['id']);
            if (id == null) continue;
            final name = AbsJson.str(s['name']) ?? '';
            rows.add(AbsJson.series(s, libraryId: libraryId));
            for (final (i, b) in AbsJson.maps(s['books']).indexed) {
              final itemId = AbsJson.str(b['id']);
              if (itemId == null) continue;
              books.add(AbsJson.item(b));
              members.add(
                AbsJson.seriesMember(id, itemId, AbsJson.sequenceIn(b, seriesId: id, seriesName: name), i),
              );
            }
          }
          if (results.length < 100 || (page + 1) * 100 >= AbsJson.integer(json['total'])) break;
        }
        await _dao.upsertItems(books);
        await _dao.replaceSeries(libraryId, rows, members);
      });

  /// The books of one series with their exact sequence.
  Future<void> refreshSeries(String seriesId, {bool force = false}) =>
      _fresh('series-one:$seriesId', Freshness.lists, force, () async {
        final head = await client.get<Map<String, Object?>>('/api/series/$seriesId');
        final libraryId = AbsJson.str(head['libraryId']);
        if (libraryId == null) return;
        final json = await client.get<Map<String, Object?>>(
          '/api/libraries/$libraryId/items',
          query: {'filter': 'series.${_b64(seriesId)}', 'sort': 'sequence', 'limit': 0, 'minified': 1},
        );
        final results = AbsJson.maps(json['results']);
        final name = AbsJson.str(head['name']) ?? '';
        await _dao.upsertItems([
          for (final r in results)
            if (AbsJson.str(r['id']) != null) AbsJson.item(r),
        ]);
        await _dao.mergeSeries(
          [AbsJson.series(head, libraryId: libraryId)],
          [
            for (final (i, r) in results.indexed)
              if (AbsJson.str(r['id']) != null)
                AbsJson.seriesMember(
                  seriesId,
                  r['id'] as String,
                  AbsJson.sequenceIn(r, seriesId: seriesId, seriesName: name),
                  i,
                ),
          ],
        );
      });

  // --- Authors and narrators ---

  Stream<List<AuthorSummary>> watchAuthors(String libraryId) =>
      _dao.watchAuthors(libraryId).map((rows) => [for (final a in rows) authorSummary(a)]);

  Stream<AuthorSummary?> watchAuthor(String id) => _dao.watchAuthor(id).map((a) => a == null ? null : authorSummary(a));

  AuthorSummary authorSummary(AuthorRow a) => AuthorSummary(
    source: source,
    libraryId: a.libraryId,
    id: a.id,
    name: a.name,
    bookCount: a.numBooks,
    description: a.description,
    imageUrl: a.hasImage ? client.url('/api/authors/${a.id}/image') : null,
    imageKey: a.hasImage ? 'author-${a.id}-${a.updatedAt}' : null,
  );

  Future<void> refreshAuthors(String libraryId, {bool force = false}) =>
      _fresh('authors:$libraryId', Freshness.lists, force, () async {
        final json = await client.get<Map<String, Object?>>('/api/libraries/$libraryId/authors');
        await _dao.replaceAuthors(libraryId, [
          for (final a in AbsJson.maps(json['authors']))
            if (AbsJson.str(a['id']) != null) AbsJson.author(a, libraryId: libraryId),
        ]);
      });

  /// The author with all their books and series positions.
  Future<void> refreshAuthor(String authorId, {bool force = false}) =>
      _fresh('author:$authorId', Freshness.lists, force, () async {
        final json = await client.get<Map<String, Object?>>(
          '/api/authors/$authorId',
          query: {'include': 'items,series'},
        );
        final libraryId = AbsJson.str(json['libraryId']);
        final books = AbsJson.maps(json['libraryItems']);
        await _dao.upsertAuthor(AbsJson.author({...json, 'numBooks': books.length}, libraryId: libraryId));
        await _dao.upsertItems([
          for (final b in books)
            if (AbsJson.str(b['id']) != null) AbsJson.item(b),
        ]);
        final series = AbsJson.maps(json['series']);
        await _dao.mergeSeries(
          [for (final s in series) AbsJson.series(s, libraryId: libraryId)],
          [
            for (final s in series)
              for (final (i, b) in AbsJson.maps(s['items']).indexed)
                if (AbsJson.str(b['id']) != null)
                  AbsJson.seriesMember(
                    s['id'] as String,
                    b['id'] as String,
                    AbsJson.sequenceIn(b, seriesId: s['id'] as String, seriesName: AbsJson.str(s['name']) ?? ''),
                    i,
                  ),
          ],
        );
      });

  /// Books by [authorName], grouped by series (in sequence) then the rest.
  Stream<List<SeriesSummary>> watchSeriesOfAuthor(String libraryId, String authorName) =>
      _dao.watchSeriesOfAuthor(libraryId, authorName).map((list) => [for (final s in list) _seriesSummary(s)]);

  // --- Collections and playlists ---

  BookListSummary _list(ListWithBooks l) => BookListSummary(
    source: source,
    id: l.id,
    name: l.name,
    description: l.description,
    books: [for (final b in l.books) AbsJson.summary(source, b.item, b.progress)],
  );

  Stream<List<BookListSummary>> watchCollections(String libraryId) =>
      _dao.watchCollections(libraryId).map((l) => [for (final c in l) _list(c)]);

  Stream<BookListSummary?> watchCollection(String id) =>
      _dao.watchCollection(id).map((c) => c == null ? null : _list(c));

  Stream<List<BookListSummary>> watchPlaylists(String libraryId) =>
      _dao.watchPlaylists(libraryId).map((l) => [for (final c in l) _list(c)]);

  Stream<BookListSummary?> watchPlaylist(String id) => _dao.watchPlaylist(id).map((c) => c == null ? null : _list(c));

  Future<void> refreshCollections(String libraryId, {bool force = false}) =>
      _fresh('collections:$libraryId', Freshness.lists, force, () async {
        final json = await client.get<Map<String, Object?>>('/api/libraries/$libraryId/collections');
        final rows = <CollectionsCompanion>[];
        final members = <CollectionItemsCompanion>[];
        final books = <ItemsCompanion>[];
        for (final c in AbsJson.maps(json['results'])) {
          final id = AbsJson.str(c['id']);
          if (id == null) continue;
          rows.add(
            CollectionsCompanion.insert(
              id: id,
              libraryId: libraryId,
              name: AbsJson.str(c['name']) ?? '',
              description: Value(AbsJson.str(c['description'])),
              lastUpdate: Value(AbsJson.integer(c['lastUpdate'])),
            ),
          );
          for (final (i, b) in AbsJson.maps(c['books']).indexed) {
            final itemId = AbsJson.str(b['id']);
            if (itemId == null) continue;
            books.add(AbsJson.item(b));
            members.add(CollectionItemsCompanion.insert(collectionId: id, itemId: itemId, position: i));
          }
        }
        await _dao.upsertItems(books);
        await _dao.replaceCollections(libraryId, rows, members);
      });

  Future<void> refreshPlaylists(String libraryId, {bool force = false}) =>
      _fresh('playlists:$libraryId', Freshness.lists, force, () async {
        final json = await client.get<Map<String, Object?>>('/api/libraries/$libraryId/playlists');
        final rows = <PlaylistsCompanion>[];
        final members = <PlaylistItemsCompanion>[];
        final books = <ItemsCompanion>[];
        for (final p in AbsJson.maps(json['results'])) {
          final parsed = _playlist(p, libraryId: libraryId);
          if (parsed == null) continue;
          rows.add(parsed.$1);
          members.addAll(parsed.$2);
          books.addAll(parsed.$3);
        }
        await _dao.upsertItems(books);
        await _dao.replacePlaylists(libraryId, rows, members);
      });

  (PlaylistsCompanion, List<PlaylistItemsCompanion>, List<ItemsCompanion>)? _playlist(
    Map<String, Object?> p, {
    String? libraryId,
  }) {
    final id = AbsJson.str(p['id']);
    if (id == null) return null;
    final members = <PlaylistItemsCompanion>[];
    final books = <ItemsCompanion>[];
    for (final (i, entry) in AbsJson.maps(p['items']).indexed) {
      final itemId = AbsJson.str(entry['libraryItemId']);
      if (itemId == null) continue;
      final item = AbsJson.map(entry['libraryItem']);
      if (item.isNotEmpty) books.add(AbsJson.item(item));
      members.add(
        PlaylistItemsCompanion.insert(
          playlistId: id,
          itemId: itemId,
          episodeId: Value(AbsJson.str(entry['episodeId']) ?? ''),
          position: i,
        ),
      );
    }
    return (
      PlaylistsCompanion.insert(
        id: id,
        libraryId: AbsJson.str(p['libraryId']) ?? libraryId ?? '',
        name: AbsJson.str(p['name']) ?? '',
        description: Value(AbsJson.str(p['description'])),
        lastUpdate: Value(AbsJson.integer(p['lastUpdate'])),
      ),
      members,
      books,
    );
  }

  Future<void> _putPlaylist(Object? json) async {
    final parsed = _playlist(AbsJson.map(json));
    if (parsed == null) return;
    await _dao.upsertItems(parsed.$3);
    await _dao.putPlaylist(parsed.$1, parsed.$2);
  }

  /// Creates a playlist, optionally with its first book. Returns its id.
  Future<String> createPlaylist(String libraryId, String name, {String? firstItemId}) async {
    final json = await client.post<Map<String, Object?>>(
      '/api/playlists',
      body: {
        'libraryId': libraryId,
        'name': name,
        if (firstItemId != null)
          'items': [
            {'libraryItemId': firstItemId},
          ],
      },
    );
    await _putPlaylist(json);
    return AbsJson.str(json['id']) ?? '';
  }

  Future<void> renamePlaylist(String id, String name) async {
    await _putPlaylist(await client.patch<Map<String, Object?>>('/api/playlists/$id', body: {'name': name}));
  }

  Future<void> deletePlaylist(String id) async {
    await client.delete<Object?>('/api/playlists/$id');
    await _dao.deletePlaylist(id);
  }

  Future<void> addToPlaylist(String id, String itemId) async {
    await _putPlaylist(
      await client.post<Map<String, Object?>>('/api/playlists/$id/item', body: {'libraryItemId': itemId}),
    );
  }

  /// Removing the last book deletes the playlist on the server, and here.
  Future<void> removeFromPlaylist(String id, String itemId) async {
    final members = await _dao.playlistMembers(id);
    final json = await client.delete<Object?>('/api/playlists/$id/item/$itemId');
    if (members.length <= 1 || json is! Map) {
      await _dao.deletePlaylist(id);
    } else {
      await _putPlaylist(json);
    }
  }

  /// Saves a new order: the server takes the complete list.
  Future<void> reorderPlaylist(String id, List<String> itemIds) async {
    final json = await client.patch<Map<String, Object?>>(
      '/api/playlists/$id',
      body: {
        'items': [
          for (final i in itemIds) {'libraryItemId': i},
        ],
      },
    );
    await _putPlaylist(json);
  }

  // --- Shelves and filter data ---

  Stream<String?> watchShelvesJson(String libraryId) => _dao.watchShelves(libraryId).map((r) => r?.json);

  Future<void> refreshShelves(String libraryId, {bool force = false}) async {
    final cached = await _dao.shelvesOf(libraryId);
    if (!force && cached != null && _now - cached.fetchedAt < Freshness.shelves.inMilliseconds) return;
    final json = await client.get<List<Object?>>('/api/libraries/$libraryId/personalized', query: {'limit': 12});
    final books = <ItemsCompanion>[];
    for (final shelf in AbsJson.maps(json)) {
      final type = shelf['type'];
      if (type == 'book' || type == 'podcast') {
        books.addAll([
          for (final e in AbsJson.maps(shelf['entities']))
            if (AbsJson.str(e['id']) != null) AbsJson.item(e),
        ]);
      }
    }
    await _dao.upsertItems(books);
    await _dao.putShelves(libraryId, jsonEncode(json), _now);
  }

  Stream<FilterChoices> watchFilterChoices(String libraryId) => _dao.watchFilterData(libraryId).map((row) {
    if (row == null) return FilterChoices.empty;
    try {
      return AbsJson.filterChoices(AbsJson.map(jsonDecode(row.json)));
    } on FormatException {
      return FilterChoices.empty;
    }
  });

  Future<void> refreshFilterData(String libraryId, {bool force = false}) =>
      _fresh('filterdata:$libraryId', Freshness.lists, force, () async {
        final json = await client.get<Map<String, Object?>>('/api/libraries/$libraryId/filterdata');
        await _dao.putFilterData(libraryId, jsonEncode(json), _now);
      });

  // --- Search ---

  /// Server search in one library. [cancel] drops it when a newer query
  /// starts.
  Future<SearchResults> search(String libraryId, String query, {CancelToken? cancel}) async {
    final json = await client.get<Map<String, Object?>>(
      '/api/libraries/$libraryId/search',
      query: {'q': query, 'limit': 12},
      cancelToken: cancel,
    );
    final books = <BookSummary>[];
    final rows = <ItemsCompanion>[];
    for (final hit in [...AbsJson.maps(json['book']), ...AbsJson.maps(json['podcast'])]) {
      final item = AbsJson.map(hit['libraryItem']);
      final id = AbsJson.str(item['id']);
      if (id == null) continue;
      rows.add(AbsJson.item(item));
      books.add(AbsJson.summaryFromJson(source, item, await _dao.progressOf(id)));
    }
    // Search hits are full items: keep them for offline use.
    await _dao.upsertItems(rows);
    return SearchResults(
      query: query,
      books: books,
      series: [
        for (final s in AbsJson.maps(json['series']))
          if (AbsJson.str(AbsJson.map(s['series'])['id']) != null)
            SeriesSummary(
              source: source,
              id: AbsJson.map(s['series'])['id'] as String,
              name: AbsJson.str(AbsJson.map(s['series'])['name']) ?? '',
              books: [for (final b in AbsJson.maps(s['books'])) AbsJson.summaryFromJson(source, b, null)],
              bookCount: AbsJson.maps(s['books']).length,
            ),
      ],
      authors: [
        for (final a in AbsJson.maps(json['authors']))
          if (AbsJson.str(a['id']) != null)
            AuthorSummary(
              source: source,
              id: a['id'] as String,
              name: AbsJson.str(a['name']) ?? '',
              bookCount: AbsJson.integer(a['numBooks']),
              imageUrl: AbsJson.str(a['imagePath']) == null ? null : client.url('/api/authors/${a['id']}/image'),
              imageKey: 'author-${a['id']}-${AbsJson.integer(a['updatedAt'])}',
            ),
      ],
      narrators: [
        for (final n in AbsJson.maps(json['narrators']))
          if (AbsJson.str(n['name']) != null) NamedCount(n['name'] as String, AbsJson.integer(n['numBooks'])),
      ],
      genres: [
        for (final n in AbsJson.maps(json['genres']))
          if (AbsJson.str(n['name']) != null) NamedCount(n['name'] as String, AbsJson.integer(n['numItems'])),
      ],
      tags: [
        for (final n in AbsJson.maps(json['tags']))
          if (AbsJson.str(n['name']) != null) NamedCount(n['name'] as String, AbsJson.integer(n['numItems'])),
      ],
    );
  }

  /// Search over the cache, for when the server cannot be reached. Finds
  /// books by title, subtitle, author, narrator, series, genre and tag.
  Future<SearchResults> searchOffline(String query, {String? libraryId}) async {
    final pattern = likePattern(query);
    if (pattern == null) return SearchResults(query: query, offline: true);
    final books = await _dao.searchItems(pattern, libraryId: libraryId);
    final series = await _dao.searchSeries(pattern, libraryId: libraryId);
    final authors = await _dao.searchAuthors(pattern, libraryId: libraryId);
    final folded = pattern.substring(1, pattern.length - 1).replaceAll(r'\', '');
    final narrators = <String, int>{};
    final genres = <String, int>{};
    final tags = <String, int>{};
    for (final b in books) {
      for (final n in b.item.narrators) {
        if (_folds(n).contains(folded)) narrators[n] = (narrators[n] ?? 0) + 1;
      }
      for (final g in b.item.genres) {
        if (_folds(g).contains(folded)) genres[g] = (genres[g] ?? 0) + 1;
      }
      for (final t in b.item.tags) {
        if (_folds(t).contains(folded)) tags[t] = (tags[t] ?? 0) + 1;
      }
    }
    return SearchResults(
      query: query,
      offline: true,
      books: [for (final b in books) AbsJson.summary(source, b.item, b.progress)],
      series: [for (final s in series) SeriesSummary(source: source, id: s.id, name: s.name)],
      authors: [for (final a in authors) authorSummary(a)],
      narrators: [for (final e in narrators.entries) NamedCount(e.key, e.value)],
      genres: [for (final e in genres.entries) NamedCount(e.key, e.value)],
      tags: [for (final e in tags.entries) NamedCount(e.key, e.value)],
    );
  }

  static String _folds(String v) => foldForSearch(v);

  /// A LIKE pattern over folded text, matching how `searchText` is stored.
  static String? likePattern(String query) {
    final folded = foldForSearch(query).trim();
    if (folded.isEmpty) return null;
    final escaped = folded.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    return '%$escaped%';
  }

  // --- Socket ---

  /// Applies a live change from the server to the cache.
  Future<void> apply(AbsSocketEvent event) async {
    switch (event) {
      case ProgressUpdated(:final progress):
        if (AbsJson.str(progress['libraryItemId']) != null) await _dao.upsertProgress(AbsJson.progress(progress));
      case UserUpdated(:final user):
        if (user['mediaProgress'] is List) await _writeUserProgress(user);
      case ItemsChanged(:final items):
        for (final item in items) {
          await _writeExpanded(item);
        }
      case ItemRemoved(:final itemId):
        await _dao.deleteItem(itemId);
      case CatalogChanged(:final kind):
        await _catalogChanged(kind);
    }
  }

  Future<void> _catalogChanged(String kind) async {
    final libraries = await _dao.allLibraries();
    // One library failing (no access any more) must not stop the others.
    Future<void> each(Future<void> Function(String libraryId) refresh) async {
      for (final l in libraries) {
        try {
          await refresh(l.id);
        } on AbsFailure {
          // Picked up by the next refresh of that library.
        }
      }
    }

    switch (kind) {
      case 'library':
        await refreshLibraries(force: true);
      case 'playlist':
        await each((id) => refreshPlaylists(id, force: true));
      case 'collection':
        await each((id) => refreshCollections(id, force: true));
      case 'series':
        await each((id) => _dao.setMeta('series:$id', '0'));
      case 'author':
        await each((id) => _dao.setMeta('authors:$id', '0'));
    }
  }

  static String _b64(String value) => base64.encode(utf8.encode(value));
}
