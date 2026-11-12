// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

/// Seed color extracted from an item's cover (AccountDb), so a screen can be
/// themed instantly and offline the second time it opens.
class CoverColors extends Table {
  TextColumn get itemId => text()();

  /// The cover revision the seed belongs to. A new cover means a new seed.
  IntColumn get coverUpdatedAt => integer()();

  /// ARGB seed color.
  IntColumn get seedArgb => integer()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}
