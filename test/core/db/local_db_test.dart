// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:earloom/core/db/local_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDb db;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = LocalDb(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> insertBook(String id) {
    return db
        .into(db.localBooks)
        .insert(
          LocalBooksCompanion.insert(
            id: id,
            title: 'The Glass Orchard',
            authors: const ['Mira Example'],
            narrators: const [],
            genres: const [],
            sourceFormat: 'mp3',
            fingerprint: '1:abc',
            sortTitle: 'the glass orchard',
            sortAuthor: 'mira example',
            searchText: 'the glass orchard | mira example',
            addedAtMs: 1,
            updatedAtMs: 1,
          ),
        );
  }

  test('a fresh database opens at the current schema version', () async {
    expect(db.schemaVersion, 1);
    expect(await db.select(db.localBooks).get(), isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 1);
  });

  test('foreign keys are on: deleting a book deletes its rows', () async {
    const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';
    await insertBook(id);
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            bookId: id,
            idx: 0,
            fileName: 'track_000.mp3',
            originalName: '01.mp3',
            sizeBytes: 10,
            mimeType: 'audio/mpeg',
          ),
        );
    await db.into(db.localChapters).insert(LocalChaptersCompanion.insert(bookId: id, idx: 0, startMs: 0, endMs: 10));
    await db
        .into(db.localProgress)
        .insert(LocalProgressCompanion.insert(bookId: id, positionMs: 1, durationMs: 10, updatedAtMs: 1));
    await db
        .into(db.localBookmarks)
        .insert(LocalBookmarksCompanion.insert(bookId: id, positionMs: 5, title: 'Here', createdAtMs: 1));

    await (db.delete(db.localBooks)..where((t) => t.id.equals(id))).go();

    expect(await db.select(db.localFiles).get(), isEmpty);
    expect(await db.select(db.localChapters).get(), isEmpty);
    expect(await db.select(db.localProgress).get(), isEmpty);
    expect(await db.select(db.localBookmarks).get(), isEmpty);
  });

  test('a row for a book that does not exist is refused', () async {
    await expectLater(
      db
          .into(db.localProgress)
          .insert(LocalProgressCompanion.insert(bookId: 'missing', positionMs: 1, durationMs: 10, updatedAtMs: 1)),
      throwsA(isA<SqliteException>()),
    );
  });

  test('name lists round-trip as JSON', () async {
    const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';
    await insertBook(id);
    final row = await db.select(db.localBooks).getSingle();
    expect(row.authors, ['Mira Example']);
    expect(const StringListConverter().fromSql('["a",1,"b"]'), ['a', 'b']);
    expect(const StringListConverter().fromSql('{}'), isEmpty);
  });

  test('the schema matches drift_schemas/local/drift_schema_v1.json', () async {
    // If this fails, the tables changed: bump schemaVersion, add the
    // migration step, and dump the new schema with
    // `dart run drift_dev schema dump lib/core/db/local_db.dart drift_schemas/local/drift_schema_v<N>.json`.
    final dump = jsonDecode(await File('drift_schemas/local/drift_schema_v${db.schemaVersion}.json').readAsString());
    final expected = <String, Set<String>>{
      for (final entity in (dump as Map<String, dynamic>)['entities'] as List<dynamic>)
        if ((entity as Map<String, dynamic>)['type'] == 'table')
          (entity['data'] as Map<String, dynamic>)['name'] as String: {
            for (final column in (entity['data'] as Map<String, dynamic>)['columns'] as List<dynamic>)
              (column as Map<String, dynamic>)['name'] as String,
          },
    };
    final actual = <String, Set<String>>{
      for (final table in db.allTables) table.actualTableName: {for (final c in table.$columns) c.name},
    };
    expect(actual, expected);
  });
}
