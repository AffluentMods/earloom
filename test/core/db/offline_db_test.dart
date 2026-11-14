// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:earloom/core/db/offline_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OfflineDb db;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = OfflineDb(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> download(String key, {String account = 'a1'}) => db.putDownload(
    DownloadsCompanion.insert(
      key: key,
      accountId: account,
      itemId: key.split('|').last,
      title: 'The Clockmaker\'s Tide',
      status: 'queued',
      createdAt: 1,
    ),
  );

  test('a fresh database opens at the current schema version', () async {
    expect(db.schemaVersion, 1);
    expect(await db.allDownloads(), isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 1);
  });

  test('deleting a download deletes its file rows, not its listening', () async {
    await download('abs:a1|i1');
    await db.replaceFiles('abs:a1|i1', [
      DownloadFilesCompanion.insert(
        downloadKey: 'abs:a1|i1',
        trackIndex: 0,
        ino: '1',
        remotePath: '/api/items/i1/file/1/download',
        localPath: 'accounts/a1/downloads/i1/track_000.mp3',
        sizeExpected: 10,
        status: 'pending',
      ),
    ]);
    await db.insertSession(
      LocalSessionsCompanion.insert(
        id: 's1',
        accountId: 'a1',
        itemId: 'i1',
        startedAt: 1,
        updatedAt: 2,
        startTime: 0,
        currentTime: 5,
        timeListened: 5,
        duration: 10,
        payloadJson: '{}',
      ),
    );
    await db.deleteDownload('abs:a1|i1');
    expect(await db.filesOf('abs:a1|i1'), isEmpty);
    expect(await db.session('s1'), isNotNull);
  });

  test('removing an account removes only its rows', () async {
    await download('abs:a1|i1');
    await download('abs:a2|i2', account: 'a2');
    await db.deleteAccount('a1');
    expect((await db.allDownloads()).map((d) => d.key), ['abs:a2|i2']);
  });

  test('the schema matches drift_schemas/offline/drift_schema_v1.json', () async {
    // If this fails, the tables changed: bump schemaVersion, add the
    // migration step, and dump the new schema with
    // `dart run drift_dev schema dump lib/core/db/offline_db.dart drift_schemas/offline/drift_schema_v<N>.json`.
    final dump = jsonDecode(await File('drift_schemas/offline/drift_schema_v${db.schemaVersion}.json').readAsString());
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
