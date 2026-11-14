// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

/// Real listening time on this phone, per local hour and book (GlobalDb).
/// Every source writes here, so stats work offline and for books on this
/// device. A stretch that crosses an hour or midnight is split exactly.
@DataClassName('ListeningBucket')
class ListeningBuckets extends Table {
  /// Local date, yyyy-mm-dd.
  TextColumn get day => text()();

  /// Local hour of day, 0 to 23.
  IntColumn get hour => integer()();

  /// `ItemRef.key` of the book.
  TextColumn get refKey => text()();
  RealColumn get seconds => real()();

  /// Book time covered, larger than [seconds] above 1x.
  RealColumn get bookSeconds => real()();

  @override
  Set<Column<Object>> get primaryKey => {day, hour, refKey};
}

/// One row per time a book was opened and listened to on this phone.
@DataClassName('ListeningSessionRow')
class ListeningSessions extends Table {
  TextColumn get id => text()();
  TextColumn get refKey => text()();
  IntColumn get startedAt => integer()();
  IntColumn get updatedAt => integer()();
  RealColumn get seconds => real()();
  RealColumn get bookSeconds => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What the stats screen needs to show a book that was listened to here,
/// even after it left the library.
@DataClassName('ListenedBook')
class ListenedBooks extends Table {
  TextColumn get refKey => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get narrator => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get coverKey => text().nullable()();
  IntColumn get firstAt => integer()();
  IntColumn get lastAt => integer()();
  IntColumn get finishedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {refKey};
}
