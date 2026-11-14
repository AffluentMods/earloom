// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

// Tables of OfflineDb: downloads, the item snapshots offline playback reads,
// listening recorded without a server, and the outbox of changes waiting to
// be sent. Every row carries the account it belongs to, because the
// database is shared by all accounts: a downloaded book of one account keeps
// playing while another account is current.
//
// Times are epoch milliseconds. Positions and durations are seconds (double),
// the unit Audiobookshelf uses.

/// One downloaded (or downloading) book or podcast episode.
@DataClassName('DownloadRow')
class Downloads extends Table {
  /// `ItemRef.key`: `abs:<accountId>|<itemId>` or `...|<episodeId>`.
  TextColumn get key => text()();
  TextColumn get accountId => text()();
  TextColumn get itemId => text()();
  TextColumn get episodeId => text().nullable()();
  TextColumn get libraryId => text().nullable()();

  /// For the Downloads screen, which must work without the account cache.
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();

  /// Relative to Application Support, once the cover is saved.
  TextColumn get coverPath => text().nullable()();

  /// `queued`, `downloading`, `paused`, `failed` or `complete`.
  TextColumn get status => text()();
  IntColumn get bytesTotal => integer().withDefault(const Constant(0))();
  IntColumn get bytesDone => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get completedAt => integer().nullable()();

  /// Technical details of the last failure, for "Copy details".
  TextColumn get lastError => text().nullable()();

  /// Why it failed, as a code the UI turns into words: `incomplete`,
  /// `network`, `forbidden`, `notFound`, `storage`, `auth`, `other`.
  TextColumn get errorCode => text().nullable()();

  /// Null when the user asked for it; `series` or `podcast` for automatic
  /// downloads.
  TextColumn get autoReason => text().nullable()();

  /// Whether this download may only use Wi-Fi.
  BoolColumn get wifiOnly => boolean().withDefault(const Constant(true))();

  /// When the user finished this book on this phone, for the auto-delete
  /// rules. Never cleared by deleting the files.
  IntColumn get finishedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// One audio file of a download.
@DataClassName('DownloadFileRow')
class DownloadFiles extends Table {
  TextColumn get downloadKey => text().references(Downloads, #key, onDelete: KeyAction.cascade)();

  /// Play order, from 0.
  IntColumn get trackIndex => integer()();
  TextColumn get ino => text()();

  /// Server path such as `/api/items/<id>/file/<ino>/download`. Never a
  /// full URL and never a token.
  TextColumn get remotePath => text()();

  /// Relative to Application Support, always our own name
  /// (`accounts/<a>/downloads/<i>/track_000.mp3`). Absolute paths change
  /// between launches on iOS.
  TextColumn get localPath => text()();
  IntColumn get sizeExpected => integer()();
  IntColumn get sizeActual => integer().nullable()();

  /// `pending`, `enqueued`, `running`, `paused`, `complete` or `failed`.
  TextColumn get status => text()();

  /// The background task id, while the file is with the downloader.
  TextColumn get taskId => text().nullable()();
  RealColumn get progress => real().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {downloadKey, trackIndex};
}

/// What offline playback reads: the expanded item as the server sent it,
/// saved before any file is downloaded.
@DataClassName('LocalSnapshotRow')
class LocalSnapshots extends Table {
  /// `ItemRef.key`.
  TextColumn get key => text()();
  TextColumn get accountId => text()();
  TextColumn get itemId => text()();
  TextColumn get episodeId => text().nullable()();
  TextColumn get itemJson => text()();
  TextColumn get chaptersJson => text()();
  TextColumn get tracksJson => text()();

  /// Relative to Application Support, or null when the item has no cover.
  TextColumn get coverPath => text().nullable()();
  IntColumn get savedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Listening recorded on this phone without a server session, sent later
/// through `/api/session/local-all` (docs/abs-api.md section 10).
@DataClassName('LocalSessionRow')
class LocalSessions extends Table {
  /// UUID made here. The server's idempotency key.
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get itemId => text()();
  TextColumn get episodeId => text().nullable()();
  IntColumn get startedAt => integer()();
  IntColumn get updatedAt => integer()();
  RealColumn get startTime => real()();
  RealColumn get currentTime => real()();

  /// Total real seconds listened in this session (not a delta).
  RealColumn get timeListened => real()();
  RealColumn get duration => real()();

  /// The parts of the payload that do not change: titles, library, media
  /// type, metadata snapshot, device info.
  TextColumn get payloadJson => text()();

  /// Set once the session ended. Only closed sessions are sent, once, with
  /// their final values (the server moves a re-sent session to a new day).
  IntColumn get closedAt => integer().nullable()();
  IntColumn get syncedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Server changes that could not be sent yet.
@DataClassName('OutboxRow')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text()();

  /// An `OutboxKind` name.
  TextColumn get kind => text()();
  TextColumn get itemId => text()();
  TextColumn get episodeId => text().nullable()();
  TextColumn get payloadJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// `pending` or `dead` (the server refused it for good).
  TextColumn get state => text().withDefault(const Constant('pending'))();
}
