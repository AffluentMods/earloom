// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/library/browse_models.dart';
import 'package:earloom/features/library/data/abs_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tables and columns of a drift schema dump.
Map<String, Set<String>> _tablesOfDump(int version) {
  final dump = jsonDecode(File('drift_schemas/account/drift_schema_v$version.json').readAsStringSync());
  return {
    for (final entity in (dump as Map<String, dynamic>)['entities'] as List<dynamic>)
      if ((entity as Map<String, dynamic>)['type'] == 'table')
        (entity['data'] as Map<String, dynamic>)['name'] as String: {
          for (final column in (entity['data'] as Map<String, dynamic>)['columns'] as List<dynamic>)
            (column as Map<String, dynamic>)['name'] as String,
        },
  };
}

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('the schema matches drift_schemas/account at the current version', () async {
    // If this fails, the tables changed: bump schemaVersion, add the
    // migration step and dump the new schema (see AccountDb.schemaVersion).
    final db = AccountDb(NativeDatabase.memory());
    addTearDown(db.close);
    final actual = {
      for (final t in db.allTables) t.actualTableName: {for (final c in t.$columns) c.name},
    };
    expect(actual, _tablesOfDump(db.schemaVersion));
  });

  test('version 1 (cover colors only) migrates to version 2 and keeps its rows', () async {
    expect(_tablesOfDump(1).keys, ['cover_colors']);
    // A database exactly as Phase 0 created it.
    final db = AccountDb(
      NativeDatabase.memory(
        setup: (raw) {
          if (raw.userVersion != 0) return;
          raw.execute(
            'CREATE TABLE "cover_colors" ("item_id" TEXT NOT NULL, "cover_updated_at" INTEGER NOT NULL, '
            '"seed_argb" INTEGER NOT NULL, PRIMARY KEY ("item_id"));',
          );
          raw.execute("INSERT INTO cover_colors VALUES ('item-1', 100, 4279312947)");
          raw.userVersion = 1;
        },
      ),
    );
    addTearDown(db.close);
    expect((await db.coverColorsDao.lookup('item-1', 100))?.seedArgb, 4279312947);
    // Every table, column and index is exactly what a fresh install gets.
    await db.validateDatabaseSchema();
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 2);
    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      containsAll(['items_library_title', 'items_library_added', 'progress_last_update', 'series_items_series']),
    );
    // The new tables work.
    await db.catalogDao.setMeta('k', 'v');
    expect(await db.catalogDao.meta('k'), 'v');
  });

  group('series order', () {
    late AccountDb db;
    setUp(() {
      db = AccountDb(NativeDatabase.memory());
      addTearDown(db.close);
    });

    test('sequence sorts naturally: 1, 2, 2.5, 10, then books without one', () async {
      Future<void> book(String id) => db.catalogDao.upsertItems([
        AbsJson.item({
          'id': id,
          'libraryId': 'lib',
          'mediaType': 'book',
          'addedAt': 1,
          'updatedAt': 1,
          'media': {
            'metadata': {'title': 'Book $id'},
          },
        }),
      ]);
      final sequences = {'a': '10', 'b': '2', 'c': null, 'd': '2.5', 'e': '1'};
      for (final id in sequences.keys) {
        await book(id);
      }
      await db.catalogDao.replaceSeries(
        'lib',
        [
          AbsJson.series({'id': 's', 'name': 'The Example Saga', 'libraryId': 'lib'}),
        ],
        [for (final (i, e) in sequences.entries.indexed) AbsJson.seriesMember('s', e.key, e.value, i)],
      );
      final series = await db.catalogDao.watchSeries('s').first;
      expect(series!.books.map((b) => b.item.id), ['e', 'b', 'd', 'a', 'c']);

      // The same order through the Books list with a series filter.
      final filtered = await db.catalogDao
          .watchBooks('lib', const LibraryQuery(filters: [LibraryFilter(FilterKind.series, 's')]))
          .first;
      expect(filtered.map((b) => b.item.id), ['e', 'b', 'd', 'a', 'c']);
    });
  });
}
