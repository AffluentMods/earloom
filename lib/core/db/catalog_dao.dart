// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:drift/drift.dart';

import '../library/browse_models.dart';
import 'account_db.dart';
import 'tables/library_cache.dart';

part 'catalog_dao.g.dart';

/// An item row with the user's progress on it (null when never started).
typedef ItemWithProgress = ({ItemRow item, ProgressRow? progress});

/// A series with its books in reading order.
typedef SeriesWithBooks = ({SeriesRow series, List<ItemWithProgress> books});

/// A collection or playlist with its books in order.
typedef ListWithBooks = ({String id, String libraryId, String name, String? description, List<ItemWithProgress> books});

/// Reads and writes the browsing cache of one account. Every `watch` method
/// is what a screen shows; every write comes from a repository that just
/// heard from the server.
@DriftAccessor(
  tables: [
    Libraries,
    Items,
    ItemDetails,
    Progress,
    Series,
    SeriesItems,
    Authors,
    Collections,
    CollectionItems,
    Playlists,
    PlaylistItems,
    Shelves,
    FilterData,
    SyncMeta,
  ],
)
class CatalogDao extends DatabaseAccessor<AccountDb> with _$CatalogDaoMixin {
  CatalogDao(super.db);

  // --- Libraries ---

  Stream<List<LibraryRow>> watchLibraries() =>
      (select(libraries)..orderBy([(t) => OrderingTerm.asc(t.displayOrder), (t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<LibraryRow>> allLibraries() =>
      (select(libraries)..orderBy([(t) => OrderingTerm.asc(t.displayOrder)])).get();

  /// Replaces the library list. Cached content of a library that is gone
  /// (deleted, or the user lost access) is removed with it.
  Future<void> replaceLibraries(List<LibrariesCompanion> rows) {
    return transaction(() async {
      final keep = {for (final r in rows) r.id.value};
      final gone = (await select(libraries).get()).where((l) => !keep.contains(l.id)).map((l) => l.id).toList();
      for (final id in gone) {
        await _deleteLibraryContent(id);
      }
      await (delete(libraries)..where((t) => t.id.isNotIn(keep))).go();
      await batch((b) => b.insertAllOnConflictUpdate(libraries, rows));
    });
  }

  Future<void> _deleteLibraryContent(String libraryId) async {
    final ids = selectOnly(items)
      ..addColumns([items.id])
      ..where(items.libraryId.equals(libraryId));
    await (delete(itemDetails)..where((t) => t.itemId.isInQuery(ids))).go();
    await (delete(items)..where((t) => t.libraryId.equals(libraryId))).go();
    final seriesIds = selectOnly(series)
      ..addColumns([series.id])
      ..where(series.libraryId.equals(libraryId));
    await (delete(seriesItems)..where((t) => t.seriesId.isInQuery(seriesIds))).go();
    await (delete(series)..where((t) => t.libraryId.equals(libraryId))).go();
    await (delete(authors)..where((t) => t.libraryId.equals(libraryId))).go();
    await (delete(collections)..where((t) => t.libraryId.equals(libraryId))).go();
    await (delete(playlists)..where((t) => t.libraryId.equals(libraryId))).go();
    await (delete(shelves)..where((t) => t.libraryId.equals(libraryId))).go();
    await (delete(filterData)..where((t) => t.libraryId.equals(libraryId))).go();
  }

  // --- Items ---

  Future<void> upsertItems(List<ItemsCompanion> rows) {
    if (rows.isEmpty) return Future.value();
    return batch((b) => b.insertAllOnConflictUpdate(items, rows));
  }

  /// Removes an item everywhere it is cached.
  Future<void> deleteItem(String id) {
    return transaction(() async {
      await (delete(items)..where((t) => t.id.equals(id))).go();
      await (delete(itemDetails)..where((t) => t.itemId.equals(id))).go();
      await (delete(seriesItems)..where((t) => t.itemId.equals(id))).go();
      await (delete(collectionItems)..where((t) => t.itemId.equals(id))).go();
      await (delete(playlistItems)..where((t) => t.itemId.equals(id))).go();
    });
  }

  /// After a full sync: everything in [libraryId] the server did not list
  /// is gone from the server.
  Future<void> deleteItemsNotIn(String libraryId, Set<String> seen) async {
    final stale =
        await (selectOnly(items)
              ..addColumns([items.id])
              ..where(items.libraryId.equals(libraryId)))
            .map((r) => r.read(items.id)!)
            .get();
    for (final id in stale.where((id) => !seen.contains(id))) {
      await deleteItem(id);
    }
  }

  Future<int> countItems(String libraryId) async {
    final count = items.id.count();
    final query = selectOnly(items)
      ..addColumns([count])
      ..where(items.libraryId.equals(libraryId));
    return (await query.getSingle()).read(count) ?? 0;
  }

  JoinedSelectStatement<HasResultSet, dynamic> _itemsWithProgress(List<Join<HasResultSet, dynamic>> extra) {
    return select(items).join([
      leftOuterJoin(progress, progress.itemId.equalsExp(items.id) & progress.episodeId.equals('')),
      ...extra,
    ]);
  }

  ItemWithProgress _read(TypedResult row) => (item: row.readTable(items), progress: row.readTableOrNull(progress));

  /// One page (from the top) of a library's books for [query].
  Stream<List<ItemWithProgress>> watchBooks(String libraryId, LibraryQuery query, {int? limit}) {
    final seriesFilter = query.filterOf(FilterKind.series);
    final statement = _itemsWithProgress([
      if (seriesFilter != null)
        innerJoin(
          seriesItems,
          seriesItems.itemId.equalsExp(items.id) & seriesItems.seriesId.equals(seriesFilter.value),
        ),
    ])..where(items.libraryId.equals(libraryId));
    for (final filter in query.filters) {
      final condition = _condition(filter);
      if (condition != null) statement.where(condition);
    }
    final mode = query.descending ? OrderingMode.desc : OrderingMode.asc;
    statement.orderBy([
      if (seriesFilter != null) ...[
        OrderingTerm.asc(seriesItems.sortKey.equals('')),
        OrderingTerm(expression: seriesItems.sortKey, mode: mode),
        OrderingTerm.asc(seriesItems.position),
      ],
      ...switch (query.sort) {
        LibrarySort.title => [OrderingTerm(expression: items.sortTitle, mode: mode)],
        LibrarySort.author => [
          OrderingTerm.asc(items.sortAuthor.equals('')),
          OrderingTerm(expression: items.sortAuthor, mode: mode),
          OrderingTerm.asc(items.sortTitle),
        ],
        LibrarySort.addedAt => [OrderingTerm(expression: items.addedAt, mode: mode)],
        LibrarySort.duration => [OrderingTerm(expression: items.durationSec, mode: mode)],
        LibrarySort.progress => [
          OrderingTerm(
            expression: progress.lastUpdate,
            mode: query.descending ? OrderingMode.asc : OrderingMode.desc,
            nulls: NullsOrder.last,
          ),
        ],
        LibrarySort.publishedYear => [
          OrderingTerm(expression: items.publishedYear, mode: mode, nulls: NullsOrder.last),
        ],
      },
      OrderingTerm.asc(items.sortTitle),
      OrderingTerm.asc(items.id),
    ]);
    if (limit != null) statement.limit(limit);
    return statement.watch().map((rows) => [for (final r in rows) _read(r)]);
  }

  Expression<bool>? _condition(LibraryFilter filter) {
    switch (filter.kind) {
      case FilterKind.progress:
        return switch (filter.value) {
          ProgressFilterValue.finished => progress.isFinished.equals(true),
          ProgressFilterValue.inProgress =>
            progress.isFinished.equals(false) & progress.currentTime.isBiggerThanValue(0),
          _ =>
            progress.itemId.isNull() |
                (progress.isFinished.equals(false) & progress.currentTime.isSmallerOrEqualValue(0)),
        };
      case FilterKind.genre:
        return items.genres.like(jsonListPattern(filter.value), escapeChar: r'\');
      case FilterKind.tag:
        return items.tags.like(jsonListPattern(filter.value), escapeChar: r'\');
      case FilterKind.author:
        return items.authors.like(jsonListPattern(filter.value), escapeChar: r'\');
      case FilterKind.narrator:
        return items.narrators.like(jsonListPattern(filter.value), escapeChar: r'\');
      case FilterKind.language:
        return items.language.equals(filter.value);
      case FilterKind.downloaded:
        return items.isDownloaded.equals(true);
      case FilterKind.series:
        return null; // A join, see watchBooks.
    }
  }

  /// Matches one exact name inside a JSON list column.
  static String jsonListPattern(String value) {
    final escaped = jsonEncode(value).replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    return '%$escaped%';
  }

  Stream<ItemWithProgress?> watchItem(String id) {
    final statement = _itemsWithProgress(const [])..where(items.id.equals(id));
    return statement.watchSingleOrNull().map((r) => r == null ? null : _read(r));
  }

  Stream<List<ItemWithProgress>> watchItemsByIds(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const []);
    final statement = _itemsWithProgress(const [])..where(items.id.isIn(ids));
    return statement.watch().map((rows) {
      final byId = {for (final r in rows) r.readTable(items).id: _read(r)};
      return [
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ];
    });
  }

  /// Books whose folded search text contains [pattern] (a LIKE pattern),
  /// in all libraries or one.
  Future<List<ItemWithProgress>> searchItems(String pattern, {String? libraryId, int limit = 50}) {
    final statement = _itemsWithProgress(const [])..where(items.searchText.like(pattern, escapeChar: r'\'));
    if (libraryId != null) statement.where(items.libraryId.equals(libraryId));
    statement
      ..orderBy([OrderingTerm.asc(items.sortTitle)])
      ..limit(limit);
    return statement.get().then((rows) => [for (final r in rows) _read(r)]);
  }

  /// Every book in a library, for building filter choices and author lists
  /// offline.
  Future<List<ItemRow>> itemsOfLibrary(String libraryId) =>
      (select(items)..where((t) => t.libraryId.equals(libraryId))).get();

  // --- Item details ---

  Future<ItemDetailRow?> detail(String itemId) =>
      (select(itemDetails)..where((t) => t.itemId.equals(itemId))).getSingleOrNull();

  Stream<ItemDetailRow?> watchDetail(String itemId) =>
      (select(itemDetails)..where((t) => t.itemId.equals(itemId))).watchSingleOrNull();

  Future<void> putDetail(String itemId, String json, int fetchedAt) => into(
    itemDetails,
  ).insertOnConflictUpdate(ItemDetailsCompanion.insert(itemId: itemId, json: json, fetchedAt: fetchedAt));

  // --- Progress ---

  /// Replaces all progress with the server's full list (from `/api/me`).
  Future<void> replaceProgress(List<ProgressCompanion> rows) {
    return transaction(() async {
      await delete(progress).go();
      await batch((b) => b.insertAll(progress, rows, mode: InsertMode.insertOrReplace));
    });
  }

  Future<void> upsertProgress(ProgressCompanion row) => into(progress).insertOnConflictUpdate(row);

  Future<void> deleteProgress(String itemId, {String episodeId = ''}) =>
      (delete(progress)..where((t) => t.itemId.equals(itemId) & t.episodeId.equals(episodeId))).go();

  Stream<ProgressRow?> watchProgress(String itemId, {String episodeId = ''}) => (select(
    progress,
  )..where((t) => t.itemId.equals(itemId) & t.episodeId.equals(episodeId))).watchSingleOrNull();

  Future<ProgressRow?> progressOf(String itemId, {String episodeId = ''}) => (select(
    progress,
  )..where((t) => t.itemId.equals(itemId) & t.episodeId.equals(episodeId))).getSingleOrNull();

  /// Started, unfinished books the user did not hide, most recent first.
  Stream<List<ItemWithProgress>> watchContinueListening({int limit = 20}) {
    final statement = select(progress).join([innerJoin(items, items.id.equalsExp(progress.itemId))])
      ..where(
        progress.episodeId.equals('') &
            progress.isFinished.equals(false) &
            progress.hideFromContinueListening.equals(false) &
            progress.currentTime.isBiggerThanValue(0),
      )
      ..orderBy([OrderingTerm.desc(progress.lastUpdate)])
      ..limit(limit);
    return statement.watch().map((rows) => [for (final r in rows) _read(r)]);
  }

  // --- Series ---

  /// Replaces the series of a library and their book positions.
  Future<void> replaceSeries(String libraryId, List<SeriesCompanion> rows, List<SeriesItemsCompanion> members) {
    return transaction(() async {
      final ids = selectOnly(series)
        ..addColumns([series.id])
        ..where(series.libraryId.equals(libraryId));
      await (delete(seriesItems)..where((t) => t.seriesId.isInQuery(ids))).go();
      await (delete(series)..where((t) => t.libraryId.equals(libraryId))).go();
      await batch((b) {
        b.insertAllOnConflictUpdate(series, rows);
        b.insertAllOnConflictUpdate(seriesItems, members);
      });
    });
  }

  /// Adds or updates series and their positions without touching others
  /// (from an author or a single series).
  Future<void> mergeSeries(List<SeriesCompanion> rows, List<SeriesItemsCompanion> members) {
    return batch((b) {
      b.insertAllOnConflictUpdate(series, rows);
      b.insertAllOnConflictUpdate(seriesItems, members);
    });
  }

  JoinedSelectStatement<HasResultSet, dynamic> _seriesWithBooks() {
    return select(series).join([
      leftOuterJoin(seriesItems, seriesItems.seriesId.equalsExp(series.id)),
      leftOuterJoin(items, items.id.equalsExp(seriesItems.itemId)),
      leftOuterJoin(progress, progress.itemId.equalsExp(items.id) & progress.episodeId.equals('')),
    ]);
  }

  List<SeriesWithBooks> _groupSeries(List<TypedResult> rows) {
    final order = <String>[];
    final heads = <String, SeriesRow>{};
    final books = <String, List<ItemWithProgress>>{};
    for (final r in rows) {
      final s = r.readTable(series);
      if (!heads.containsKey(s.id)) {
        order.add(s.id);
        heads[s.id] = s;
        books[s.id] = [];
      }
      final item = r.readTableOrNull(items);
      if (item != null) books[s.id]!.add((item: item, progress: r.readTableOrNull(progress)));
    }
    return [for (final id in order) (series: heads[id]!, books: books[id]!)];
  }

  List<OrderingTerm> get _seriesBookOrder => [
    OrderingTerm.asc(seriesItems.sortKey.equals('')),
    OrderingTerm.asc(seriesItems.sortKey),
    OrderingTerm.asc(seriesItems.position),
  ];

  Stream<List<SeriesWithBooks>> watchSeriesList(String libraryId) {
    final statement = _seriesWithBooks()
      ..where(series.libraryId.equals(libraryId))
      ..orderBy([OrderingTerm.asc(series.sortName), OrderingTerm.asc(series.id), ..._seriesBookOrder]);
    return statement.watch().map(_groupSeries);
  }

  Stream<SeriesWithBooks?> watchSeries(String seriesId) {
    final statement = _seriesWithBooks()
      ..where(series.id.equals(seriesId))
      ..orderBy(_seriesBookOrder);
    return statement.watch().map((rows) {
      final grouped = _groupSeries(rows);
      return grouped.isEmpty ? null : grouped.first;
    });
  }

  /// The series (with sequence) that [itemIds] belong to.
  Future<List<({SeriesRow series, SeriesItemRow member})>> seriesOfItems(List<String> itemIds) async {
    if (itemIds.isEmpty) return const [];
    final statement = select(seriesItems).join([innerJoin(series, series.id.equalsExp(seriesItems.seriesId))])
      ..where(seriesItems.itemId.isIn(itemIds));
    final rows = await statement.get();
    return [for (final r in rows) (series: r.readTable(series), member: r.readTable(seriesItems))];
  }

  Stream<List<SeriesWithBooks>> watchSeriesOfAuthor(String libraryId, String authorName) {
    final ids = selectOnly(seriesItems).join([innerJoin(items, items.id.equalsExp(seriesItems.itemId))])
      ..addColumns([seriesItems.seriesId])
      ..where(items.authors.like(jsonListPattern(authorName), escapeChar: r'\'));
    final statement = _seriesWithBooks()
      ..where(series.libraryId.equals(libraryId) & series.id.isInQuery(ids))
      ..orderBy([OrderingTerm.asc(series.sortName), OrderingTerm.asc(series.id), ..._seriesBookOrder]);
    return statement.watch().map(_groupSeries);
  }

  // --- Authors ---

  Future<void> replaceAuthors(String libraryId, List<AuthorsCompanion> rows) {
    return transaction(() async {
      await (delete(authors)..where((t) => t.libraryId.equals(libraryId))).go();
      await batch((b) => b.insertAllOnConflictUpdate(authors, rows));
    });
  }

  Future<void> upsertAuthor(AuthorsCompanion row) => into(authors).insertOnConflictUpdate(row);

  Stream<List<AuthorRow>> watchAuthors(String libraryId) =>
      (select(authors)
            ..where((t) => t.libraryId.equals(libraryId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortName)]))
          .watch();

  Stream<AuthorRow?> watchAuthor(String id) => (select(authors)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<List<AuthorRow>> searchAuthors(String pattern, {String? libraryId, int limit = 12}) {
    final q = select(authors)
      ..where((t) => t.sortName.like(pattern, escapeChar: r'\') | t.name.like(pattern, escapeChar: r'\'))
      ..orderBy([(t) => OrderingTerm.asc(t.sortName)])
      ..limit(limit);
    if (libraryId != null) q.where((t) => t.libraryId.equals(libraryId));
    return q.get();
  }

  Future<List<SeriesRow>> searchSeries(String pattern, {String? libraryId, int limit = 12}) {
    final q = select(series)
      ..where((t) => t.sortName.like(pattern, escapeChar: r'\'))
      ..orderBy([(t) => OrderingTerm.asc(t.sortName)])
      ..limit(limit);
    if (libraryId != null) q.where((t) => t.libraryId.equals(libraryId));
    return q.get();
  }

  // --- Collections and playlists ---

  Future<void> replaceCollections(
    String libraryId,
    List<CollectionsCompanion> rows,
    List<CollectionItemsCompanion> members,
  ) {
    return transaction(() async {
      final ids = selectOnly(collections)
        ..addColumns([collections.id])
        ..where(collections.libraryId.equals(libraryId));
      await (delete(collectionItems)..where((t) => t.collectionId.isInQuery(ids))).go();
      await (delete(collections)..where((t) => t.libraryId.equals(libraryId))).go();
      await batch((b) {
        b.insertAllOnConflictUpdate(collections, rows);
        b.insertAllOnConflictUpdate(collectionItems, members);
      });
    });
  }

  Future<void> replacePlaylists(String libraryId, List<PlaylistsCompanion> rows, List<PlaylistItemsCompanion> members) {
    return transaction(() async {
      final ids = selectOnly(playlists)
        ..addColumns([playlists.id])
        ..where(playlists.libraryId.equals(libraryId));
      await (delete(playlistItems)..where((t) => t.playlistId.isInQuery(ids))).go();
      await (delete(playlists)..where((t) => t.libraryId.equals(libraryId))).go();
      await batch((b) {
        b.insertAllOnConflictUpdate(playlists, rows);
        b.insertAllOnConflictUpdate(playlistItems, members);
      });
    });
  }

  /// Replaces one playlist (after an edit the server answered with it).
  Future<void> putPlaylist(PlaylistsCompanion row, List<PlaylistItemsCompanion> members) {
    return transaction(() async {
      await (delete(playlistItems)..where((t) => t.playlistId.equals(row.id.value))).go();
      await into(playlists).insertOnConflictUpdate(row);
      await batch((b) => b.insertAllOnConflictUpdate(playlistItems, members));
    });
  }

  Future<void> deletePlaylist(String id) {
    return transaction(() async {
      await (delete(playlistItems)..where((t) => t.playlistId.equals(id))).go();
      await (delete(playlists)..where((t) => t.id.equals(id))).go();
    });
  }

  Stream<List<ListWithBooks>> watchCollections(String libraryId) => _watchLists(
    head: collections,
    members: collectionItems,
    headId: collections.id,
    headLibrary: collections.libraryId,
    headName: collections.name,
    memberList: collectionItems.collectionId,
    memberItem: collectionItems.itemId,
    memberPosition: collectionItems.position,
    where: collections.libraryId.equals(libraryId),
    read: (r) {
      final c = r.readTable(collections);
      return (id: c.id, libraryId: c.libraryId, name: c.name, description: c.description);
    },
  );

  Stream<ListWithBooks?> watchCollection(String id) => _watchLists(
    head: collections,
    members: collectionItems,
    headId: collections.id,
    headLibrary: collections.libraryId,
    headName: collections.name,
    memberList: collectionItems.collectionId,
    memberItem: collectionItems.itemId,
    memberPosition: collectionItems.position,
    where: collections.id.equals(id),
    read: (r) {
      final c = r.readTable(collections);
      return (id: c.id, libraryId: c.libraryId, name: c.name, description: c.description);
    },
  ).map((l) => l.isEmpty ? null : l.first);

  Stream<List<ListWithBooks>> watchPlaylists(String libraryId) => _watchLists(
    head: playlists,
    members: playlistItems,
    headId: playlists.id,
    headLibrary: playlists.libraryId,
    headName: playlists.name,
    memberList: playlistItems.playlistId,
    memberItem: playlistItems.itemId,
    memberPosition: playlistItems.position,
    where: playlists.libraryId.equals(libraryId),
    read: (r) {
      final p = r.readTable(playlists);
      return (id: p.id, libraryId: p.libraryId, name: p.name, description: p.description);
    },
  );

  Stream<ListWithBooks?> watchPlaylist(String id) => _watchLists(
    head: playlists,
    members: playlistItems,
    headId: playlists.id,
    headLibrary: playlists.libraryId,
    headName: playlists.name,
    memberList: playlistItems.playlistId,
    memberItem: playlistItems.itemId,
    memberPosition: playlistItems.position,
    where: playlists.id.equals(id),
    read: (r) {
      final p = r.readTable(playlists);
      return (id: p.id, libraryId: p.libraryId, name: p.name, description: p.description);
    },
  ).map((l) => l.isEmpty ? null : l.first);

  Future<List<PlaylistItemRow>> playlistMembers(String playlistId) =>
      (select(playlistItems)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  Stream<List<ListWithBooks>> _watchLists({
    required TableInfo<Table, dynamic> head,
    required TableInfo<Table, dynamic> members,
    required GeneratedColumn<String> headId,
    required GeneratedColumn<String> headLibrary,
    required GeneratedColumn<String> headName,
    required GeneratedColumn<String> memberList,
    required GeneratedColumn<String> memberItem,
    required GeneratedColumn<int> memberPosition,
    required Expression<bool> where,
    required ({String id, String libraryId, String name, String? description}) Function(TypedResult) read,
  }) {
    final statement =
        select(head).join([
            leftOuterJoin(members, memberList.equalsExp(headId)),
            leftOuterJoin(items, items.id.equalsExp(memberItem)),
            leftOuterJoin(progress, progress.itemId.equalsExp(items.id) & progress.episodeId.equals('')),
          ])
          ..where(where)
          ..orderBy([
            OrderingTerm.asc(headName.collate(Collate.noCase)),
            OrderingTerm.asc(headId),
            OrderingTerm.asc(memberPosition),
          ]);
    return statement.watch().map((rows) {
      final order = <String>[];
      final heads = <String, ({String id, String libraryId, String name, String? description})>{};
      final books = <String, List<ItemWithProgress>>{};
      for (final r in rows) {
        final h = read(r);
        if (!heads.containsKey(h.id)) {
          order.add(h.id);
          heads[h.id] = h;
          books[h.id] = [];
        }
        final item = r.readTableOrNull(items);
        if (item != null) books[h.id]!.add((item: item, progress: r.readTableOrNull(progress)));
      }
      return [
        for (final id in order)
          (
            id: id,
            libraryId: heads[id]!.libraryId,
            name: heads[id]!.name,
            description: heads[id]!.description,
            books: books[id]!,
          ),
      ];
    });
  }

  // --- Shelves, filter data, sync times ---

  Future<void> putShelves(String libraryId, String json, int fetchedAt) => into(
    shelves,
  ).insertOnConflictUpdate(ShelvesCompanion.insert(libraryId: libraryId, json: json, fetchedAt: fetchedAt));

  Stream<ShelfRow?> watchShelves(String libraryId) =>
      (select(shelves)..where((t) => t.libraryId.equals(libraryId))).watchSingleOrNull();

  Future<ShelfRow?> shelvesOf(String libraryId) =>
      (select(shelves)..where((t) => t.libraryId.equals(libraryId))).getSingleOrNull();

  Future<void> putFilterData(String libraryId, String json, int fetchedAt) => into(
    filterData,
  ).insertOnConflictUpdate(FilterDataCompanion.insert(libraryId: libraryId, json: json, fetchedAt: fetchedAt));

  Stream<FilterDataRow?> watchFilterData(String libraryId) =>
      (select(filterData)..where((t) => t.libraryId.equals(libraryId))).watchSingleOrNull();

  Future<String?> meta(String key) async =>
      (await (select(syncMeta)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String value) =>
      into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: value));
}
