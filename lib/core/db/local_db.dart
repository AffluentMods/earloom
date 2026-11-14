// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'db_location.dart';
import 'tables/local_bookmarks.dart';
import 'tables/local_books.dart';
import 'tables/local_chapters.dart';
import 'tables/local_files.dart';
import 'tables/local_progress.dart';

export 'tables/local_books.dart' show StringListConverter;

part 'local_db.g.dart';

/// The On this device library (docs/architecture.md section 5): books
/// imported from files on the phone, their files, chapters, progress and
/// bookmarks. Needs no account and no server.
///
/// The audio itself lives next to the database, in `<support>/local/<id>/`
/// (see `LocalStorage`).
@DriftDatabase(tables: [LocalBooks, LocalFiles, LocalChapters, LocalProgress, LocalBookmarks])
class LocalDb extends _$LocalDb {
  LocalDb(super.executor);

  /// Opens the on-device database file.
  LocalDb.open() : super(openAppDatabase('local'));

  /// Bump on every schema change, add the step to [migration], dump the new
  /// schema to `drift_schemas/local/` and extend the migration test.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Version 1 is the first schema. Each later version adds one block
      // here, in order and guarded by `if (from < N)`, so a phone that
      // skipped releases still walks through every change.
    },
    beforeOpen: (details) async {
      // Deleting a book deletes its files, chapters, progress and bookmarks.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
