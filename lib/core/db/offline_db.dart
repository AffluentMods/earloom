// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'db_location.dart';
import 'tables/offline_tables.dart';

part 'offline_db.g.dart';

/// Downloads, offline snapshots, local listening sessions and the outbox,
/// for every account (docs/architecture.md section 5).
///
/// One database for all accounts, not one per account: a book downloaded
/// in account A must keep playing (and recording its listening) while
/// account B is current, and the outbox of A must still flush. Every row
/// carries its `accountId`; removing an account removes its rows
/// ([deleteAccount]).
@DriftDatabase(tables: [Downloads, DownloadFiles, LocalSnapshots, LocalSessions, Outbox])
class OfflineDb extends _$OfflineDb {
  OfflineDb(super.executor);

  /// Opens the on-device database file.
  OfflineDb.open() : super(openAppDatabase('offline'));

  /// Bump on every schema change, add the step to [migration], dump the new
  /// schema to `drift_schemas/offline/` and extend the schema test.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Version 1 is the first schema. Each later version adds one block
      // here, guarded by `if (from < N)`.
    },
    beforeOpen: (details) async {
      // Deleting a download deletes its file rows.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // --- Downloads ---

  Stream<List<DownloadRow>> watchDownloads() =>
      (select(downloads)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  Future<List<DownloadRow>> allDownloads() =>
      (select(downloads)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Future<DownloadRow?> download(String key) => (select(downloads)..where((t) => t.key.equals(key))).getSingleOrNull();

  Stream<DownloadRow?> watchDownload(String key) =>
      (select(downloads)..where((t) => t.key.equals(key))).watchSingleOrNull();

  Future<void> putDownload(DownloadsCompanion row) => into(downloads).insertOnConflictUpdate(row);

  Future<void> updateDownload(String key, DownloadsCompanion change) =>
      (update(downloads)..where((t) => t.key.equals(key))).write(change);

  /// Removes the download and its file rows. Snapshots and listening are
  /// kept: deleting a download never deletes progress.
  Future<void> deleteDownload(String key) => (delete(downloads)..where((t) => t.key.equals(key))).go();

  Future<List<DownloadFileRow>> filesOf(String key) =>
      (select(downloadFiles)
            ..where((t) => t.downloadKey.equals(key))
            ..orderBy([(t) => OrderingTerm.asc(t.trackIndex)]))
          .get();

  Future<List<DownloadFileRow>> allFiles() => select(downloadFiles).get();

  Future<DownloadFileRow?> fileByTask(String taskId) =>
      (select(downloadFiles)..where((t) => t.taskId.equals(taskId))).getSingleOrNull();

  Future<void> replaceFiles(String key, List<DownloadFilesCompanion> rows) {
    return transaction(() async {
      await (delete(downloadFiles)..where((t) => t.downloadKey.equals(key))).go();
      await batch((b) => b.insertAll(downloadFiles, rows));
    });
  }

  Future<void> updateFile(String key, int trackIndex, DownloadFilesCompanion change) => (update(
    downloadFiles,
  )..where((t) => t.downloadKey.equals(key) & t.trackIndex.equals(trackIndex))).write(change);

  // --- Snapshots ---

  Future<LocalSnapshotRow?> snapshot(String key) =>
      (select(localSnapshots)..where((t) => t.key.equals(key))).getSingleOrNull();

  Future<void> putSnapshot(LocalSnapshotsCompanion row) => into(localSnapshots).insertOnConflictUpdate(row);

  Future<void> deleteSnapshot(String key) => (delete(localSnapshots)..where((t) => t.key.equals(key))).go();

  // --- Local sessions ---

  Future<void> insertSession(LocalSessionsCompanion row) => into(localSessions).insert(row);

  Future<void> updateSession(String id, LocalSessionsCompanion change) =>
      (update(localSessions)..where((t) => t.id.equals(id))).write(change);

  Future<LocalSessionRow?> session(String id) =>
      (select(localSessions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<LocalSessionRow>> sessionsByIds(Iterable<String> ids) =>
      (select(localSessions)..where((t) => t.id.isIn(ids))).get();

  /// Sessions still open, for closing after a crash or a kill (nothing is
  /// playing yet at start-up).
  Future<List<LocalSessionRow>> openSessions() => (select(localSessions)..where((t) => t.closedAt.isNull())).get();

  Future<void> markSessionsSynced(Iterable<String> ids, int at) =>
      (update(localSessions)..where((t) => t.id.isIn(ids))).write(LocalSessionsCompanion(syncedAt: Value(at)));

  // --- Accounts ---

  /// Removes everything of an account that was removed from the app. Its
  /// files on disk are deleted by the accounts screen.
  Future<void> deleteAccount(String accountId) {
    return transaction(() async {
      await (delete(downloads)..where((t) => t.accountId.equals(accountId))).go();
      await (delete(localSnapshots)..where((t) => t.accountId.equals(accountId))).go();
      await (delete(localSessions)..where((t) => t.accountId.equals(accountId))).go();
      await (delete(outbox)..where((t) => t.accountId.equals(accountId))).go();
    });
  }
}
