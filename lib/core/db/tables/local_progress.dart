// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'local_books.dart';

/// Listening progress of a book (LocalDb). At most one row per book.
@TableIndex(name: 'local_progress_last_played', columns: {#lastPlayedAtMs})
class LocalProgress extends Table {
  TextColumn get bookId => text().references(LocalBooks, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  IntColumn get finishedAtMs => integer().nullable()();

  /// Any change: playback, marking finished or unfinished.
  IntColumn get updatedAtMs => integer()();

  /// Playback only, for the "recently played" order.
  IntColumn get lastPlayedAtMs => integer().nullable()();

  /// Real time spent listening, summed over all sessions (for stats).
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {bookId};
}
