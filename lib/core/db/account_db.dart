// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'catalog_dao.dart';
import 'db_location.dart';
import 'tables/cover_colors.dart';
import 'tables/library_cache.dart';
import 'tables/local_books.dart' show StringListConverter;

export 'catalog_dao.dart';

part 'account_db.g.dart';

/// The cache for one account (one user on one server). Each account gets its
/// own file, `account_<id>.sqlite`, so data from one account can never show
/// under another.
@DriftDatabase(
  tables: [
    CoverColors,
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
  daos: [CoverColorsDao, CatalogDao],
)
class AccountDb extends _$AccountDb {
  AccountDb(super.executor);

  /// Opens the on-device database file for [accountId].
  AccountDb.open(String accountId) : super(openAppDatabase('account_$accountId'));

  /// Bump on every schema change, add the step to [migration], dump the new
  /// schema with `dart run drift_dev schema dump lib/core/db/account_db.dart
  /// drift_schemas/account/drift_schema_vN.json` and extend the migration
  /// test.
  ///
  /// 1: cover colors (Phase 0). 2: the browsing cache (Phase 2).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Everything new in version 2 is cache: created empty, filled by
        // the next refresh.
        for (final TableInfo<Table, Object?> table in [
          libraries,
          items,
          itemDetails,
          progress,
          series,
          seriesItems,
          authors,
          collections,
          collectionItems,
          playlists,
          playlistItems,
          shelves,
          filterData,
          syncMeta,
        ]) {
          await m.createTable(table);
        }
        for (final index in [itemsLibraryTitle, itemsLibraryAdded, progressLastUpdate, seriesItemsSeries]) {
          await m.createIndex(index);
        }
      }
    },
  );
}

@DriftAccessor(tables: [CoverColors])
class CoverColorsDao extends DatabaseAccessor<AccountDb> with _$CoverColorsDaoMixin {
  CoverColorsDao(super.db);

  /// The cached seed for this exact cover revision, or null.
  Future<CoverColor?> lookup(String itemId, int coverUpdatedAt) {
    return (select(
      coverColors,
    )..where((t) => t.itemId.equals(itemId) & t.coverUpdatedAt.equals(coverUpdatedAt))).getSingleOrNull();
  }

  /// Stores the seed, replacing the one from an older cover revision.
  Future<void> put(String itemId, int coverUpdatedAt, int seedArgb) {
    return into(coverColors).insertOnConflictUpdate(
      CoverColorsCompanion.insert(itemId: itemId, coverUpdatedAt: coverUpdatedAt, seedArgb: seedArgb),
    );
  }
}
