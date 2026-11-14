// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'local_books.dart';

/// Chapters of a book (LocalDb), on the whole-book timeline.
class LocalChapters extends Table {
  TextColumn get bookId => text().references(LocalBooks, #id, onDelete: KeyAction.cascade)();
  IntColumn get idx => integer()();

  /// Null when the tags had no title. The UI shows "Chapter N" then, in the
  /// user's language.
  TextColumn get title => text().nullable()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, idx};
}
