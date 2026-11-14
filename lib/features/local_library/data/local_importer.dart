// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_db.dart';
import 'audio_formats.dart';
import 'book_assembly.dart';
import 'import_models.dart';
import 'import_planner.dart';
import 'import_source.dart';
import 'local_search_text.dart';
import 'local_storage.dart';
import 'tags/file_tags.dart';
import 'tags/tag_reader.dart';

/// Reads the tags of the files at the given paths. The default runs
/// [readFileTags] in a background isolate; tests can pass their own.
typedef TagBatchReader = Future<List<FileTags>> Function(List<String> paths);

/// Imports picked files into the On this device library
/// (docs/architecture.md section 8).
///
/// For each book: copy every file into a staging folder (with progress and
/// cancellation), read the tags, put the files in playback order under our
/// own names, save the cover, then move the folder into place and write the
/// rows in one transaction. A failure or cancel at any point removes the
/// staging folder, so the library never holds half a book.
final class LocalImporter implements BookImporter {
  LocalImporter({
    required this.db,
    required this.storage,
    TagBatchReader? readTags,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _readTags = readTags ?? _readTagsInBackground,
       _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final LocalDb db;
  final LocalStorage storage;
  final TagBatchReader _readTags;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Removes what interrupted imports left behind, once per app run, before
  /// the first import. Running it here (and not at app start) keeps it from
  /// ever racing an import.
  Future<void>? _cleanup;

  static const fingerprintBytes = 64 * 1024;

  @override
  Future<ImportPlan> plan(ImportSelection selection) async {
    await (_cleanup ??= cleanUpInterrupted());
    final draft = planImport(selection);
    final books = <PlannedBook>[];
    for (final book in draft.books) {
      final fingerprint = await fingerprintOf(book);
      final existing =
          await (db.select(db.localBooks)
                ..where((t) => t.fingerprint.equals(fingerprint))
                ..limit(1))
              .getSingleOrNull();
      books.add(
        PlannedBook(
          draft: book,
          fingerprint: fingerprint,
          duplicateOf: existing == null ? null : DuplicateMatch(bookId: existing.id, title: existing.title),
        ),
      );
    }
    return ImportPlan(selection: selection, books: books, skippedFiles: draft.skippedFiles);
  }

  /// `<total bytes>:<sha256 of the first 64 KB of the first file>`. The first
  /// file is the first in natural path order, which needs no tags, so the
  /// same files give the same fingerprint before and after import.
  static Future<String> fingerprintOf(BookDraft book) async {
    final first = book.files.first.source;
    final head = BytesBuilder(copy: false);
    await for (final chunk in first.openRead(0, fingerprintBytes)) {
      head.add(chunk);
    }
    return '${book.totalBytes}:${sha256.convert(head.takeBytes())}';
  }

  @override
  ImportJob start(List<PlannedBook> books) {
    final job = _LocalImportJob();
    unawaited(_run(books, job));
    return job;
  }

  /// Deletes staging folders and book folders that have no row: what an
  /// import interrupted by a crash or a killed app leaves behind.
  Future<void> cleanUpInterrupted() async {
    try {
      final found = await storage.scan();
      for (final dir in found.staging) {
        await dir.delete(recursive: true);
      }
      if (found.bookIds.isEmpty) return;
      final known = (await (db.selectOnly(
        db.localBooks,
      )..addColumns([db.localBooks.id])).get()).map((row) => row.read(db.localBooks.id)).toSet();
      for (final id in found.bookIds) {
        if (!known.contains(id)) await storage.bookDir(id).delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort: it is tried again on the next run.
    }
  }

  Future<void> _run(List<PlannedBook> books, _LocalImportJob job) async {
    final added = <ImportedBook>[];
    final failed = <ImportFailure>[];
    final failedIndexes = <int>{};
    final allTotal = books.fold(0, (sum, b) => sum + b.totalBytes);
    var allDoneBefore = 0;
    try {
      await (_cleanup ??= cleanUpInterrupted());
      for (var i = 0; i < books.length; i++) {
        if (job.isCancelled) break;
        final book = books[i];
        void report(ImportStage stage, int bookDone) => job.emit(
          ImportProgress(
            bookIndex: i,
            bookCount: books.length,
            bookName: book.displayName,
            stage: stage,
            bookBytesDone: bookDone,
            bookBytesTotal: book.totalBytes,
            allBytesDone: allDoneBefore + bookDone,
            allBytesTotal: allTotal,
            failedBooks: {...failedIndexes},
          ),
        );
        try {
          added.add(await _importOne(book, job, report));
        } on ImportCancelled {
          break;
        } on Object catch (error, stack) {
          failedIndexes.add(i);
          failed.add(
            ImportFailure(bookName: book.displayName, kind: classifyImportError(error), details: '$error\n$stack'),
          );
        }
        allDoneBefore += book.totalBytes;
      }
    } finally {
      job.finish(ImportOutcome(added: added, failed: failed, cancelled: job.isCancelled));
    }
  }

  Future<ImportedBook> _importOne(
    PlannedBook book,
    _LocalImportJob job,
    void Function(ImportStage stage, int bookDone) report,
  ) async {
    final bookId = _newId();
    final staging = storage.stagingDir(bookId);
    var movedIntoPlace = false;
    try {
      await staging.create(recursive: true);
      final draft = book.draft;

      // 1. Copy, under temporary names.
      report(ImportStage.copying, 0);
      var done = 0;
      final incoming = <String>[];
      for (var j = 0; j < draft.files.length; j++) {
        final source = draft.files[j].source;
        final name = LocalStorage.incomingFileName(j, AudioFormats.extensionOf(source.name));
        final target = storage.stagedFile(bookId, name);
        await _copy(source, target, job, (bytes) {
          done += bytes;
          job.emitThrottled(() => report(ImportStage.copying, done));
        });
        incoming.add(target.path);
      }
      report(ImportStage.reading, book.totalBytes);
      job.throwIfCancelled();

      // 2. Tags, then playback order and book metadata.
      final tags = await _readTags(incoming);
      job.throwIfCancelled();
      final tagged = [for (var j = 0; j < draft.files.length; j++) _Staged(TaggedFile(draft.files[j], tags[j]), j)];
      final orderedFiles = orderFiles(tagged.map((s) => s.file));
      final ordered = [for (final file in orderedFiles) tagged.firstWhere((s) => identical(s.file, file))];
      final meta = assembleMetadata(orderedFiles, folderName: draft.folderName);
      final chapters = buildChapters(orderedFiles, bookTitle: meta.title);

      // 3. Final names: track_000, track_001... in playback order.
      final fileRows = <LocalFilesCompanion>[];
      for (var k = 0; k < ordered.length; k++) {
        final staged = ordered[k];
        final ext = AudioFormats.extensionOf(staged.file.name);
        final finalName = LocalStorage.trackFileName(k, ext);
        await File(incoming[staged.incomingIndex]).rename(storage.stagedFile(bookId, finalName).path);
        fileRows.add(
          LocalFilesCompanion.insert(
            bookId: bookId,
            idx: k,
            fileName: finalName,
            originalName: staged.file.name,
            durationMs: Value(staged.file.duration.inMilliseconds),
            sizeBytes: staged.file.draft.source.size,
            mimeType: AudioFormats.mimeTypes[ext] ?? 'application/octet-stream',
            trackNumber: Value(staged.file.tags.trackNumber),
            discNumber: Value(staged.file.disc),
          ),
        );
      }

      // 4. Cover: the embedded one, else the image from the folder.
      final now = _clock();
      final coverFile = await _saveCover(bookId, orderedFiles, draft.coverImage, now, job);
      job.throwIfCancelled();

      // 5. Into place, then the rows in one go.
      report(ImportStage.saving, book.totalBytes);
      final duration = orderedFiles.fold(Duration.zero, (sum, f) => sum + f.duration);
      await staging.rename(storage.bookDir(bookId).path);
      movedIntoPlace = true;
      await db.transaction(() async {
        await db
            .into(db.localBooks)
            .insert(
              LocalBooksCompanion.insert(
                id: bookId,
                title: meta.title,
                subtitle: Value(meta.subtitle),
                authors: meta.authors,
                narrators: meta.narrators,
                seriesName: Value(meta.seriesName),
                seriesSequence: Value(meta.seriesSequence),
                description: Value(meta.description),
                genres: meta.genres,
                publishedYear: Value(meta.publishedYear),
                publisher: Value(meta.publisher),
                language: Value(meta.language),
                coverFile: Value(coverFile),
                sourceFormat: sourceFormatOf(orderedFiles.map((f) => f.name)),
                durationMs: Value(duration.inMilliseconds),
                sizeBytes: Value(book.totalBytes),
                fingerprint: book.fingerprint,
                chaptersFromFiles: Value(chapters.fromFiles),
                sortTitle: LocalSearchText.sortTitle(meta.title),
                sortAuthor: LocalSearchText.sortAuthor(meta.authors),
                searchText: LocalSearchText.searchText(
                  title: meta.title,
                  subtitle: meta.subtitle,
                  authors: meta.authors,
                  narrators: meta.narrators,
                  seriesName: meta.seriesName,
                ),
                addedAtMs: now.millisecondsSinceEpoch,
                updatedAtMs: now.millisecondsSinceEpoch,
              ),
            );
        await db.batch((b) {
          b.insertAll(db.localFiles, fileRows);
          b.insertAll(db.localChapters, [
            for (var c = 0; c < chapters.chapters.length; c++)
              LocalChaptersCompanion.insert(
                bookId: bookId,
                idx: c,
                title: Value(chapters.chapters[c].title),
                startMs: chapters.chapters[c].start.inMilliseconds,
                endMs: chapters.chapters[c].end.inMilliseconds,
              ),
          ]);
        });
      });
      return ImportedBook(bookId: bookId, title: meta.title);
    } on Object {
      await _deleteQuietly(movedIntoPlace ? storage.bookDir(bookId) : staging);
      rethrow;
    }
  }

  /// Copies (or, for the picker's temporary copies, moves) one file.
  Future<void> _copy(
    ImportSourceFile source,
    File target,
    _LocalImportJob job,
    void Function(int bytes) onBytes,
  ) async {
    job.throwIfCancelled();
    if (await source.tryMoveTo(target.path)) {
      onBytes(source.size);
      return;
    }
    final out = await target.open(mode: FileMode.writeOnly);
    var written = 0;
    try {
      // `await for` pauses the read while each write is in flight, so memory
      // stays flat however large the file is.
      await for (final chunk in source.openRead()) {
        job.throwIfCancelled();
        await out.writeFrom(chunk);
        written += chunk.length;
        onBytes(chunk.length);
      }
    } finally {
      await out.close();
    }
    if (source.size > 0 && written != source.size) {
      throw FileSystemException('Copied $written of ${source.size} bytes', source.toString());
    }
  }

  Future<String?> _saveCover(
    String bookId,
    List<TaggedFile> files,
    ImportSourceFile? folderImage,
    DateTime now,
    _LocalImportJob job,
  ) async {
    for (final file in files) {
      final cover = file.tags.cover;
      if (cover == null) continue;
      final ext = AudioFormats.sniffImageExtension(cover.bytes) ?? AudioFormats.imageExtensionForMime(cover.mimeType);
      if (ext == null) continue;
      final name = LocalStorage.coverFileName(now, ext);
      await storage.stagedFile(bookId, name).writeAsBytes(cover.bytes, flush: true);
      return name;
    }
    if (folderImage == null || folderImage.size > 20 * 1024 * 1024) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in folderImage.openRead()) {
      job.throwIfCancelled();
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    final ext = AudioFormats.sniffImageExtension(data);
    if (ext == null) return null;
    final name = LocalStorage.coverFileName(now, ext);
    await storage.stagedFile(bookId, name).writeAsBytes(data, flush: true);
    return name;
  }
}

final class _Staged {
  const _Staged(this.file, this.incomingIndex);

  final TaggedFile file;
  final int incomingIndex;
}

/// Reads tags in a background isolate. Only the first cover found is kept,
/// so a 60 file book does not carry 60 copies of the same picture.
Future<List<FileTags>> _readTagsInBackground(List<String> paths) {
  return Isolate.run(() {
    var coverFound = false;
    return [
      for (final path in paths)
        () {
          final tags = readFileTags(path, withCover: !coverFound);
          if (tags.cover != null) coverFound = true;
          return tags;
        }(),
    ];
  });
}

/// Maps an error to what the UI can explain.
ImportErrorKind classifyImportError(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    final message = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    // ENOSPC is 28 on Linux, Android, iOS and macOS.
    if (code == 28 || message.contains('no space')) return ImportErrorKind.noSpace;
    // A dataless iCloud file read without coordination fails with EDEADLK
    // (11 on iOS).
    if (Platform.isIOS && code == 11) return ImportErrorKind.notDownloaded;
    if (message.contains('deadlock')) return ImportErrorKind.notDownloaded;
    if (error is PathNotFoundException || error is PathAccessException) return ImportErrorKind.unreadable;
    if (message.contains('copied')) return ImportErrorKind.unreadable;
  }
  if (error is PlatformException) {
    return error.code == 'not_downloaded' ? ImportErrorKind.notDownloaded : ImportErrorKind.unreadable;
  }
  return ImportErrorKind.unknown;
}

Future<void> _deleteQuietly(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } on FileSystemException {
    // Left for cleanUpInterrupted on the next import.
  }
}

final class _LocalImportJob implements ImportJob {
  final _progress = StreamController<ImportProgress>.broadcast();
  final _done = Completer<ImportOutcome>();
  final _throttle = Stopwatch()..start();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  @override
  Stream<ImportProgress> get progress => _progress.stream;

  @override
  Future<ImportOutcome> get done => _done.future;

  @override
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ImportCancelled();
  }

  void emit(ImportProgress progress) {
    _throttle.reset();
    if (!_progress.isClosed) _progress.add(progress);
  }

  /// At most ten updates a second while bytes flow.
  void emitThrottled(void Function() emitNow) {
    if (_throttle.elapsedMilliseconds >= 100) emitNow();
  }

  void finish(ImportOutcome outcome) {
    unawaited(_progress.close());
    if (!_done.isCompleted) _done.complete(outcome);
  }
}
