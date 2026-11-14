// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'local_books.dart' show StringListConverter;

// The browsing cache of one Audiobookshelf account (AccountDb). Everything
// here is a copy of what the server said, written by the repositories in
// lib/features/library/data and read by the UI. Times are epoch
// milliseconds, durations seconds, as the server sends them.

/// Libraries the user can see on the server.
@DataClassName('LibraryRow')
class Libraries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `book` or `podcast`.
  TextColumn get mediaType => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The list form of every item: what grids, lists, shelves and offline
/// search need. The full item lives in [ItemDetails].
@DataClassName('ItemRow')
@TableIndex(name: 'items_library_title', columns: {#libraryId, #sortTitle})
@TableIndex(name: 'items_library_added', columns: {#libraryId, #addedAt})
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get libraryId => text()();

  /// `book` or `podcast`.
  TextColumn get mediaType => text()();
  TextColumn get title => text()();

  /// Folded, number-padded `titleIgnorePrefix` ("Field Guide, A").
  TextColumn get sortTitle => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get authors => text().map(const StringListConverter())();

  /// Folded, number-padded "Last, First" of the first author.
  TextColumn get sortAuthor => text()();
  TextColumn get narrators => text().map(const StringListConverter())();

  /// The server's display string: "The Example Saga #2", several joined by
  /// commas.
  TextColumn get seriesSummary => text().nullable()();
  TextColumn get genres => text().map(const StringListConverter())();
  TextColumn get tags => text().map(const StringListConverter())();
  TextColumn get language => text().nullable()();
  TextColumn get publishedYear => text().nullable()();
  RealColumn get durationSec => real().withDefault(const Constant(0))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  BoolColumn get hasCover => boolean().withDefault(const Constant(false))();
  IntColumn get addedAt => integer()();

  /// There is no coverUpdatedAt on the server: this doubles as the cover
  /// cache key (docs/abs-api.md section 18, item 14).
  IntColumn get updatedAt => integer()();

  /// Phase 4 sets this when every file is on the phone.
  BoolColumn get isDownloaded => boolean().withDefault(const Constant(false))();

  /// Folded title, subtitle, authors, narrators, series, genres and tags,
  /// for offline search.
  TextColumn get searchText => text()();

  /// Podcasts: how many episodes the server has (Phase 5). Lists that leave
  /// the count out (shelves, search) never overwrite it.
  IntColumn get numEpisodes => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The full expanded item for the detail screen, as JSON.
@DataClassName('ItemDetailRow')
class ItemDetails extends Table {
  TextColumn get itemId => text()();
  TextColumn get json => text()();
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}

/// The user's progress, mirroring ABS mediaProgress. Books have an empty
/// [episodeId] so the pair is a primary key.
@DataClassName('ProgressRow')
@TableIndex(name: 'progress_last_update', columns: {#lastUpdate})
class Progress extends Table {
  TextColumn get itemId => text()();
  TextColumn get episodeId => text().withDefault(const Constant(''))();

  /// The server's id of the progress row.
  TextColumn get progressId => text().nullable()();
  RealColumn get currentTime => real().withDefault(const Constant(0))();
  RealColumn get duration => real().withDefault(const Constant(0))();
  RealColumn get progress => real().withDefault(const Constant(0))();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  BoolColumn get hideFromContinueListening => boolean().withDefault(const Constant(false))();
  IntColumn get finishedAt => integer().nullable()();
  IntColumn get lastUpdate => integer()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, episodeId};
}

@DataClassName('SeriesRow')
class Series extends Table {
  TextColumn get id => text()();
  TextColumn get libraryId => text()();
  TextColumn get name => text()();

  /// Folded, number-padded `nameIgnorePrefix`.
  TextColumn get sortName => text()();
  TextColumn get description => text().nullable()();
  IntColumn get addedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Which books are in a series, at which position.
@DataClassName('SeriesItemRow')
@TableIndex(name: 'series_items_series', columns: {#seriesId})
class SeriesItems extends Table {
  TextColumn get seriesId => text()();
  TextColumn get itemId => text()();

  /// As the server writes it: "1", "2.5", "Book 2", or null.
  TextColumn get sequence => text().nullable()();

  /// [sequence] with its numbers padded, so SQL sorts it naturally
  /// (1, 2, 2.5, 10). Empty for no sequence.
  TextColumn get sortKey => text().withDefault(const Constant(''))();

  /// The server's order, for ties and books without a sequence.
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {seriesId, itemId};
}

@DataClassName('AuthorRow')
class Authors extends Table {
  TextColumn get id => text()();
  TextColumn get libraryId => text()();
  TextColumn get name => text()();

  /// Folded "Last, First".
  TextColumn get sortName => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get hasImage => boolean().withDefault(const Constant(false))();
  IntColumn get numBooks => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CollectionRow')
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get libraryId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get lastUpdate => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CollectionItemRow')
class CollectionItems extends Table {
  TextColumn get collectionId => text()();
  TextColumn get itemId => text()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {collectionId, itemId};
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get libraryId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get lastUpdate => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PlaylistItemRow')
class PlaylistItems extends Table {
  TextColumn get playlistId => text()();
  TextColumn get itemId => text()();
  TextColumn get episodeId => text().withDefault(const Constant(''))();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {playlistId, itemId, episodeId};
}

/// The cached `/personalized` answer of a library (Home shelves).
@DataClassName('ShelfRow')
class Shelves extends Table {
  TextColumn get libraryId => text()();
  TextColumn get json => text()();
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {libraryId};
}

/// The cached `/filterdata` answer of a library (filter choices).
@DataClassName('FilterDataRow')
class FilterData extends Table {
  TextColumn get libraryId => text()();
  TextColumn get json => text()();
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {libraryId};
}

/// Small facts about the cache: when each list was last synced.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
