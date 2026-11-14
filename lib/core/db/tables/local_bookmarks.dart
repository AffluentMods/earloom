// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'local_books.dart';

/// Bookmarks of a book (LocalDb). Like Audiobookshelf, a bookmark is
/// identified by its book and position: one bookmark per position.
class LocalBookmarks extends Table {
  TextColumn get bookId => text().references(LocalBooks, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer()();
  TextColumn get title => text()();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, positionMs};
}
