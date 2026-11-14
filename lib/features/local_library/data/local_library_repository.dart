// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/db/local_db.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../player/playable.dart';
import 'audio_formats.dart';
import 'local_search_text.dart';
import 'local_storage.dart';

/// Orders for [LocalLibraryRepository.watchBooks].
enum LocalBookSort { title, author, recentlyAdded, recentlyPlayed }

/// Words the repository needs in the user's language. It has no
/// BuildContext, so the provider passes them in.
final class LocalLibraryStrings {
  const LocalLibraryStrings({required this.untitledChapter, required this.seriesLine});

  /// "Chapter 3", for chapters whose tags had no title. [number] counts
  /// from 1.
  final String Function(int number) untitledChapter;

  /// "Book 2 of The Example Saga", or just the series name without a number.
  final String Function(String series, String? sequence) seriesLine;
}

/// A metadata edit from the edit sheet. Every field replaces the stored one.
final class LocalBookEdit {
  const LocalBookEdit({
    required this.title,
    this.authors = const [],
    this.narrators = const [],
    this.seriesName,
    this.seriesSequence,
    this.description,
    this.coverImagePath,
  });

  final String title;
  final List<String> authors;
  final List<String> narrators;
  final String? seriesName;
  final String? seriesSequence;
  final String? description;

  /// A picked image to use as the new cover, or null to keep the cover.
  final String? coverImagePath;
}

/// The picked cover is not an image the app can show.
final class UnsupportedCoverImage implements Exception {
  const UnsupportedCoverImage(this.path);

  final String path;

  @override
  String toString() => 'UnsupportedCoverImage: $path is not a JPEG, PNG or WebP image';
}

/// The book's files are gone from the app's storage (the system cleared it,
/// or a restore brought back the database without the files).
final class LocalBookUnavailable implements Exception {
  const LocalBookUnavailable(this.bookId, this.missingFile);

  final String bookId;
  final String missingFile;

  @override
  String toString() => 'LocalBookUnavailable: book $bookId is missing $missingFile';
}

/// The book does not exist (any more).
final class LocalBookNotFound implements Exception {
  const LocalBookNotFound(this.bookId);

  final String bookId;

  @override
  String toString() => 'LocalBookNotFound: $bookId';
}

/// The On this device library: everything the UI and the player need from
/// books imported onto the phone. Reads stream from [LocalDb], so screens
/// update by themselves after an import, an edit or playback.
final class LocalLibraryRepository {
  LocalLibraryRepository({
    required this.db,
    required this.storage,
    required this.strings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDb db;
  final LocalStorage storage;
  final LocalLibraryStrings strings;
  final DateTime Function() _clock;

  /// A finished book stays finished while the position is this close to the
  /// end (the player reports the final position after `finished`).
  static const finishedTolerance = Duration(seconds: 5);

  static ItemRef refOf(String bookId) => ItemRef(const LocalSource(), bookId);

  // Reading.

  Stream<List<BookSummary>> watchBooks({LocalBookSort sort = LocalBookSort.recentlyAdded, String? query}) {
    final b = db.localBooks;
    final p = db.localProgress;
    final select = db.select(b).join([leftOuterJoin(p, p.bookId.equalsExp(b.id))]);
    final pattern = LocalSearchText.likePattern(query);
    if (pattern != null) select.where(b.searchText.like(pattern, escapeChar: r'\'));
    select.orderBy(switch (sort) {
      LocalBookSort.title => [OrderingTerm.asc(b.sortTitle), OrderingTerm.desc(b.addedAtMs)],
      LocalBookSort.author => [
        // Books without an author go last.
        OrderingTerm.asc(b.sortAuthor.equals('')),
        OrderingTerm.asc(b.sortAuthor),
        OrderingTerm.asc(b.sortTitle),
      ],
      LocalBookSort.recentlyAdded => [OrderingTerm.desc(b.addedAtMs), OrderingTerm.asc(b.sortTitle)],
      LocalBookSort.recentlyPlayed => [
        OrderingTerm(expression: p.lastPlayedAtMs, mode: OrderingMode.desc, nulls: NullsOrder.last),
        OrderingTerm.desc(b.addedAtMs),
      ],
    });
    return select.watch().map(
      (rows) => [for (final row in rows) _summary(row.readTable(b), row.readTableOrNull(p))],
    );
  }

  Stream<BookDetail?> watchBook(String id) {
    final b = db.localBooks;
    final p = db.localProgress;
    final select = db.select(b).join([leftOuterJoin(p, p.bookId.equalsExp(b.id))])..where(b.id.equals(id));
    return select.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final book = row.readTable(b);
      final chapters = await _chapters(id);
      return BookDetail(
        summary: _summary(book, row.readTableOrNull(p)),
        descriptionHtml: book.description,
        genres: book.genres,
        publisher: book.publisher,
        publishedYear: book.publishedYear,
        language: book.language,
        chapters: chapters,
        series: [
          if (book.seriesName != null)
            SeriesMembership(id: book.seriesName!, name: book.seriesName!, sequence: book.seriesSequence),
        ],
        sizeBytes: book.sizeBytes,
        fileFormat: book.sourceFormat,
      );
    });
  }

  Stream<ListeningProgress?> watchProgress(String id) {
    return (db.select(db.localProgress)..where((t) => t.bookId.equals(id))).watchSingleOrNull().map(
      (row) => row == null ? null : _progress(row),
    );
  }

  Stream<List<Bookmark>> watchBookmarks(String id) {
    return (db.select(db.localBookmarks)
          ..where((t) => t.bookId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.positionMs)]))
        .watch()
        .map((rows) => [for (final row in rows) _bookmark(row)]);
  }

  Future<List<Bookmark>> bookmarks(String id) => watchBookmarks(id).first;

  /// The cover file for a book, from its [BookSummary.coverKey] (for local
  /// books the key is the cover's file name). Null when there is no cover.
  File? coverFile(String bookId, String? coverKey) {
    if (coverKey == null || !LocalStorage.isOwnFileName(coverKey)) return null;
    return storage.bookFile(bookId, coverKey);
  }

  /// Bytes the book takes on disk: what deleting it frees.
  Future<int> storageBytes(String id) => LocalStorage.sizeOf(storage.bookDir(id));

  // Editing.

  Future<void> updateMetadata(String id, LocalBookEdit edit) async {
    final title = edit.title.trim();
    if (title.isEmpty) throw ArgumentError.value(edit.title, 'title', 'must not be empty');
    final book = await _book(id);
    final authors = _cleanList(edit.authors);
    final narrators = _cleanList(edit.narrators);
    final seriesName = _cleanText(edit.seriesName);
    final subtitle = book.subtitle;

    String? newCover;
    if (edit.coverImagePath != null) newCover = await _writeCover(id, edit.coverImagePath!);
    try {
      await (db.update(db.localBooks)..where((t) => t.id.equals(id))).write(
        LocalBooksCompanion(
          title: Value(title),
          authors: Value(authors),
          narrators: Value(narrators),
          seriesName: Value(seriesName),
          seriesSequence: Value(seriesName == null ? null : _cleanText(edit.seriesSequence)),
          description: Value(_cleanText(edit.description)),
          coverFile: newCover == null ? const Value.absent() : Value(newCover),
          sortTitle: Value(LocalSearchText.sortTitle(title)),
          sortAuthor: Value(LocalSearchText.sortAuthor(authors)),
          searchText: Value(
            LocalSearchText.searchText(
              title: title,
              subtitle: subtitle,
              authors: authors,
              narrators: narrators,
              seriesName: seriesName,
            ),
          ),
          updatedAtMs: Value(_now()),
        ),
      );
    } on Object {
      if (newCover != null) await _deleteQuietly(storage.bookFile(id, newCover));
      rethrow;
    }
    final oldCover = book.coverFile;
    if (newCover != null && oldCover != null && oldCover != newCover) {
      await _deleteQuietly(storage.bookFile(id, oldCover));
    }
  }

  Future<String> _writeCover(String id, String path) async {
    final file = File(path);
    if (await file.length() > 20 * 1024 * 1024) throw UnsupportedCoverImage(path);
    final Uint8List bytes = await file.readAsBytes();
    final ext = AudioFormats.sniffImageExtension(bytes);
    if (ext == null) throw UnsupportedCoverImage(path);
    final name = LocalStorage.coverFileName(_clock(), ext);
    await storage.bookFile(id, name).writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Deletes the book: its rows (progress and bookmarks included) and its
  /// files. Returns the bytes freed.
  Future<int> deleteBook(String id) async {
    final dir = storage.bookDir(id);
    final bytes = await LocalStorage.sizeOf(dir);
    await (db.delete(db.localBooks)..where((t) => t.id.equals(id))).go();
    // Rows first: if deleting files fails half way, the leftover folder has
    // no row and the next import's cleanup removes it.
    await _deleteQuietly(dir);
    return bytes;
  }

  Future<void> markFinished(String id) async {
    final book = await _book(id);
    final now = _now();
    await db
        .into(db.localProgress)
        .insertOnConflictUpdate(
          LocalProgressCompanion.insert(
            bookId: id,
            positionMs: book.durationMs,
            durationMs: book.durationMs,
            isFinished: const Value(true),
            finishedAtMs: Value(now),
            updatedAtMs: now,
          ),
        );
  }

  /// Takes the finished mark off. A position left at the very end goes back
  /// to the start, so the next play does not end right away.
  Future<void> markUnfinished(String id) async {
    await db.transaction(() async {
      final book = await _book(id);
      final row = await (db.select(db.localProgress)..where((t) => t.bookId.equals(id))).getSingleOrNull();
      if (row == null) return;
      final atEnd = row.positionMs >= book.durationMs - finishedTolerance.inMilliseconds;
      await (db.update(db.localProgress)..where((t) => t.bookId.equals(id))).write(
        LocalProgressCompanion(
          isFinished: const Value(false),
          finishedAtMs: const Value(null),
          positionMs: atEnd ? const Value(0) : const Value.absent(),
          updatedAtMs: Value(_now()),
        ),
      );
    });
  }

  /// Adds a bookmark, or renames the one already at [position].
  Future<void> addBookmark(String id, Duration position, String title) {
    return db
        .into(db.localBookmarks)
        .insertOnConflictUpdate(
          LocalBookmarksCompanion.insert(
            bookId: id,
            positionMs: position.inMilliseconds,
            title: title.trim(),
            createdAtMs: _now(),
          ),
        );
  }

  Future<void> renameBookmark(String id, Duration position, String title) {
    return (db.update(db.localBookmarks)
          ..where((t) => t.bookId.equals(id) & t.positionMs.equals(position.inMilliseconds)))
        .write(LocalBookmarksCompanion(title: Value(title.trim())));
  }

  Future<void> deleteBookmark(String id, Duration position) {
    return (db.delete(
      db.localBookmarks,
    )..where((t) => t.bookId.equals(id) & t.positionMs.equals(position.inMilliseconds))).go();
  }

  /// Stores the durations the player measured, when the tags were wrong or
  /// silent. [durations] are per file, in playback order. Chapters that were
  /// made from the files follow; embedded chapters keep their times.
  Future<void> correctFileDurations(String id, List<Duration> durations) async {
    await db.transaction(() async {
      final book = await _book(id);
      final files =
          await (db.select(db.localFiles)
                ..where((t) => t.bookId.equals(id))
                ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
              .get();
      if (files.length != durations.length) return;
      var total = 0;
      for (var i = 0; i < files.length; i++) {
        final ms = durations[i].inMilliseconds;
        total += ms;
        if (ms != files[i].durationMs) {
          await (db.update(db.localFiles)..where((t) => t.bookId.equals(id) & t.idx.equals(i))).write(
            LocalFilesCompanion(durationMs: Value(ms)),
          );
        }
      }
      if (book.chaptersFromFiles) {
        var start = 0;
        for (var i = 0; i < durations.length; i++) {
          final end = start + durations[i].inMilliseconds;
          await (db.update(db.localChapters)..where((t) => t.bookId.equals(id) & t.idx.equals(i))).write(
            LocalChaptersCompanion(startMs: Value(start), endMs: Value(end)),
          );
          start = end;
        }
      }
      await (db.update(db.localBooks)..where((t) => t.id.equals(id))).write(
        LocalBooksCompanion(durationMs: Value(total), updatedAtMs: Value(_now())),
      );
    });
  }

  // Playback.

  /// Everything the player needs to play the book: `file://` tracks with
  /// their start in the book, chapters, where to resume (the start again for
  /// a finished book), the cover, and a [ProgressSink] that writes to
  /// [LocalDb].
  Future<PlayableBook> playable(String bookId) async {
    final book = await _book(bookId);
    final files =
        await (db.select(db.localFiles)
              ..where((t) => t.bookId.equals(bookId))
              ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
            .get();
    if (files.isEmpty) throw LocalBookUnavailable(bookId, '(no files)');
    final tracks = <PlayableTrack>[];
    var start = Duration.zero;
    for (final file in files) {
      final onDisk = storage.bookFile(bookId, file.fileName);
      if (!await onDisk.exists()) throw LocalBookUnavailable(bookId, file.fileName);
      final duration = Duration(milliseconds: file.durationMs);
      tracks.add(PlayableTrack(uri: onDisk.uri, start: start, duration: duration, mimeType: file.mimeType));
      start += duration;
    }
    final progress = await (db.select(db.localProgress)..where((t) => t.bookId.equals(bookId))).getSingleOrNull();
    var startPosition = Duration.zero;
    if (progress != null && !progress.isFinished) {
      final ms = progress.positionMs.clamp(0, start.inMilliseconds);
      startPosition = Duration(milliseconds: ms);
    }
    final cover = coverFile(bookId, book.coverFile);
    return PlayableBook(
      ref: refOf(bookId),
      title: book.title,
      author: book.authors.isEmpty ? null : book.authors.join(', '),
      narrator: book.narrators.isEmpty ? null : book.narrators.join(', '),
      seriesLine: book.seriesName == null ? null : strings.seriesLine(book.seriesName!, book.seriesSequence),
      tracks: tracks,
      chapters: await _chapters(bookId),
      startPosition: startPosition,
      artworkUri: cover != null && await cover.exists() ? cover.uri : null,
      coverKey: book.coverFile,
      sink: LocalProgressSink(this, bookId, start),
    );
  }

  /// Writes a playback position. Used by [LocalProgressSink].
  Future<void> writeProgress(
    String bookId, {
    required Duration position,
    required Duration duration,
    Duration listened = Duration.zero,
    bool finished = false,
  }) async {
    final now = _now();
    await db.transaction(() async {
      final row = await (db.select(db.localProgress)..where((t) => t.bookId.equals(bookId))).getSingleOrNull();
      final nearEnd = position >= duration - finishedTolerance;
      // Playing a finished book again from the start takes the mark off;
      // the final position reported right after finishing keeps it.
      final isFinished = finished || ((row?.isFinished ?? false) && nearEnd);
      final positionMs = finished ? duration.inMilliseconds : position.inMilliseconds;
      await db
          .into(db.localProgress)
          .insertOnConflictUpdate(
            LocalProgressCompanion.insert(
              bookId: bookId,
              positionMs: positionMs.clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : positionMs),
              durationMs: duration.inMilliseconds,
              isFinished: Value(isFinished),
              finishedAtMs: Value(isFinished ? (finished ? now : (row?.finishedAtMs ?? now)) : null),
              updatedAtMs: now,
              lastPlayedAtMs: Value(now),
              listenedMs: Value((row?.listenedMs ?? 0) + listened.inMilliseconds),
            ),
          );
    });
  }

  // Helpers.

  Future<LocalBook> _book(String id) async {
    final book = await (db.select(db.localBooks)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (book == null) throw LocalBookNotFound(id);
    return book;
  }

  Future<List<Chapter>> _chapters(String bookId) async {
    final rows =
        await (db.select(db.localChapters)
              ..where((t) => t.bookId.equals(bookId))
              ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
            .get();
    return [
      for (final row in rows)
        Chapter(
          index: row.idx,
          title: row.title ?? strings.untitledChapter(row.idx + 1),
          start: Duration(milliseconds: row.startMs),
          end: Duration(milliseconds: row.endMs),
        ),
    ];
  }

  BookSummary _summary(LocalBook book, LocalProgressData? progress) {
    return BookSummary(
      ref: refOf(book.id),
      title: book.title,
      subtitle: book.subtitle,
      authors: book.authors,
      narrators: book.narrators,
      seriesName: book.seriesName,
      seriesSequence: book.seriesSequence,
      duration: Duration(milliseconds: book.durationMs),
      coverKey: book.coverFile,
      progress: progress == null ? null : _progress(progress),
      isDownloaded: true,
      addedAt: DateTime.fromMillisecondsSinceEpoch(book.addedAtMs),
    );
  }

  ListeningProgress _progress(LocalProgressData row) {
    return ListeningProgress(
      position: Duration(milliseconds: row.positionMs),
      duration: Duration(milliseconds: row.durationMs),
      isFinished: row.isFinished,
      finishedAt: row.finishedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(row.finishedAtMs!),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs),
    );
  }

  Bookmark _bookmark(LocalBookmark row) {
    return Bookmark(
      ref: refOf(row.bookId),
      position: Duration(milliseconds: row.positionMs),
      title: row.title,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
    );
  }

  int _now() => _clock().millisecondsSinceEpoch;

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _cleanList(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (_cleanText(value) case final v? when seen.add(v.toLowerCase())) v,
    ];
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException {
      // The next import's cleanup removes what is left.
    }
  }
}

/// Progress of one local book, straight into [LocalDb].
final class LocalProgressSink implements ProgressSink {
  LocalProgressSink(this._repository, this.bookId, this.duration);

  final LocalLibraryRepository _repository;
  final String bookId;

  /// The whole book, so finishing stores a position at the very end.
  final Duration duration;

  @override
  Future<void> report({required Duration position, required Duration listened, required bool isPlaying}) {
    return _repository.writeProgress(bookId, position: position, duration: duration, listened: listened);
  }

  @override
  Future<void> finished({required Duration position}) {
    return _repository.writeProgress(bookId, position: position, duration: duration, finished: true);
  }

  @override
  Future<void> close({required Duration position}) {
    return _repository.writeProgress(bookId, position: position, duration: duration);
  }
}
