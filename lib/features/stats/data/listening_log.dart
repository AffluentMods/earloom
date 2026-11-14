// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import '../../../core/db/global_db.dart';
import '../../../core/ui/cover_image.dart';
import '../../player/player_engine.dart';

/// Writes what the player reports into the listening log (GlobalDb).
class ListeningLog {
  ListeningLog(this._db);
  final GlobalDb _db;

  static String dayKey(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

  /// Splits [span] at local hour boundaries (and so at midnight) and adds
  /// each piece to its bucket.
  static List<({String day, int hour, double seconds, double bookSeconds})> split(ListeningSpan span) {
    final pieces = <({String day, int hour, double seconds, double bookSeconds})>[];
    final total = span.listened.inMicroseconds;
    if (total <= 0) return pieces;
    var from = span.start.toLocal();
    final end = span.end.toLocal();
    while (from.isBefore(end)) {
      final nextHour = DateTime(from.year, from.month, from.day, from.hour + 1);
      final to = nextHour.isBefore(end) ? nextHour : end;
      final part = to.difference(from).inMicroseconds / total;
      pieces.add((
        day: dayKey(from),
        hour: from.hour,
        seconds: span.listened.inMicroseconds * part / 1e6,
        bookSeconds: span.bookTime.inMicroseconds * part / 1e6,
      ));
      from = to;
    }
    return pieces;
  }

  Future<void> record(ListeningSpan span) => _db.transaction(() async {
    final key = span.book.ref.key;
    for (final p in split(span)) {
      await _db.customStatement(
        'INSERT INTO listening_buckets (day, hour, ref_key, seconds, book_seconds) VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(day, hour, ref_key) DO UPDATE SET seconds = seconds + excluded.seconds, '
        'book_seconds = book_seconds + excluded.book_seconds',
        [p.day, p.hour, key, p.seconds, p.bookSeconds],
      );
    }
    final start = span.start.millisecondsSinceEpoch;
    final end = span.end.millisecondsSinceEpoch;
    final seconds = span.listened.inMicroseconds / 1e6;
    final bookSeconds = span.bookTime.inMicroseconds / 1e6;
    await _db.customStatement(
      'INSERT INTO listening_sessions (id, ref_key, started_at, updated_at, seconds, book_seconds) '
      'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, '
      'seconds = seconds + excluded.seconds, book_seconds = book_seconds + excluded.book_seconds',
      [span.sessionId, key, start, end, seconds, bookSeconds],
    );
    final cover = span.book.cover;
    await _db
        .into(_db.listenedBooks)
        .insert(
          ListenedBooksCompanion.insert(
            refKey: key,
            title: span.book.title,
            author: Value(span.book.author),
            narrator: Value(span.book.narrator),
            coverPath: Value(cover is FileCover ? cover.path : null),
            coverUrl: Value(cover is NetworkCover ? cover.itemCoverUrl.toString() : null),
            coverKey: Value(cover is NetworkCover ? cover.cacheKey : span.book.coverKey),
            firstAt: start,
            lastAt: end,
          ),
          onConflict: DoUpdate(
            (old) => ListenedBooksCompanion(
              title: Value(span.book.title),
              author: Value(span.book.author),
              narrator: Value(span.book.narrator),
              coverPath: Value(cover is FileCover ? cover.path : null),
              coverUrl: Value(cover is NetworkCover ? cover.itemCoverUrl.toString() : null),
              coverKey: Value(cover is NetworkCover ? cover.cacheKey : span.book.coverKey),
              lastAt: Value(end),
            ),
          ),
        );
  });

  Future<void> finished(NowPlaying book, DateTime at) async {
    await (_db.update(_db.listenedBooks)..where((t) => t.refKey.equals(book.ref.key))).write(
      ListenedBooksCompanion(finishedAt: Value(at.millisecondsSinceEpoch)),
    );
  }

  Future<List<ListeningBucket>> buckets() => _db.select(_db.listeningBuckets).get();
  Future<List<ListeningSessionRow>> sessions() => _db.select(_db.listeningSessions).get();
  Future<List<ListenedBook>> books() => _db.select(_db.listenedBooks).get();

  /// Changes whenever something is logged.
  Stream<void> get changes => _db.tableUpdates(
    TableUpdateQuery.onAllTables([_db.listeningBuckets, _db.listeningSessions, _db.listenedBooks]),
  );
}
