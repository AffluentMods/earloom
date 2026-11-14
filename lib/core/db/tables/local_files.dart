// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'local_books.dart';

/// The audio files of a book (LocalDb), in playback order.
class LocalFiles extends Table {
  TextColumn get bookId => text().references(LocalBooks, #id, onDelete: KeyAction.cascade)();

  /// Playback order, from 0.
  IntColumn get idx => integer()();

  /// Relative to the book folder, always one of our own names such as
  /// `track_000.mp3`. Never built from tags or the original file name.
  TextColumn get fileName => text()();

  /// The name the file had when it was imported. Shown to the user only,
  /// never used to build a path.
  TextColumn get originalName => text()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get sizeBytes => integer()();
  TextColumn get mimeType => text()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, idx};
}
