// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'db_location.dart';
import 'tables/cover_colors.dart';

part 'account_db.g.dart';

/// The cache for one account (one user on one server). Each account gets its
/// own file, `account_<id>.sqlite`, so data from one account can never show
/// under another.
@DriftDatabase(tables: [CoverColors], daos: [CoverColorsDao])
class AccountDb extends _$AccountDb {
  AccountDb(super.executor);

  /// Opens the on-device database file for [accountId].
  AccountDb.open(String accountId) : super(openAppDatabase('account_$accountId'));

  @override
  int get schemaVersion => 1;
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
