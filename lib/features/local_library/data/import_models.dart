// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'import_planner.dart';
import 'import_source.dart';

/// An existing book with the same files as a [PlannedBook].
final class DuplicateMatch {
  const DuplicateMatch({required this.bookId, required this.title});

  final String bookId;
  final String title;
}

/// One book the importer is ready to add.
final class PlannedBook {
  const PlannedBook({required this.draft, required this.fingerprint, this.duplicateOf});

  final BookDraft draft;

  /// See `LocalBooks.fingerprint`.
  final String fingerprint;

  /// Set when the same files were imported before. The UI asks the user
  /// whether to add another copy.
  final DuplicateMatch? duplicateOf;

  String get displayName => draft.displayName;
  int get totalBytes => draft.totalBytes;
  int get fileCount => draft.files.length;
}

/// What a selection turns into, before anything is copied.
final class ImportPlan {
  const ImportPlan({required this.selection, required this.books, this.skippedFiles = const []});

  final ImportSelection selection;
  final List<PlannedBook> books;

  /// Names of picked files that are not audio the app can play.
  final List<String> skippedFiles;

  bool get isEmpty => books.isEmpty;
  List<PlannedBook> get duplicates => [
    for (final b in books)
      if (b.duplicateOf != null) b,
  ];
}

enum ImportStage {
  /// Copying the files into the app's storage.
  copying,

  /// Reading tags, chapters and the cover.
  reading,

  /// Writing the book into the library.
  saving,
}

/// Where a running import is.
final class ImportProgress {
  const ImportProgress({
    required this.bookIndex,
    required this.bookCount,
    required this.bookName,
    required this.stage,
    required this.bookBytesDone,
    required this.bookBytesTotal,
    required this.allBytesDone,
    required this.allBytesTotal,
    this.failedBooks = const {},
  });

  /// From 0.
  final int bookIndex;
  final int bookCount;

  /// The folder or file name: the tags are read only after copying.
  final String bookName;
  final ImportStage stage;
  final int bookBytesDone;
  final int bookBytesTotal;
  final int allBytesDone;
  final int allBytesTotal;

  /// Indexes of the books before [bookIndex] that could not be imported.
  final Set<int> failedBooks;

  /// 0 to 1, for the whole import.
  double get fraction => allBytesTotal <= 0 ? 0 : (allBytesDone / allBytesTotal).clamp(0.0, 1.0);

  /// 0 to 1, for the current book.
  double get bookFraction => bookBytesTotal <= 0 ? 0 : (bookBytesDone / bookBytesTotal).clamp(0.0, 1.0);
}

/// A book that made it into the library.
final class ImportedBook {
  const ImportedBook({required this.bookId, required this.title});

  final String bookId;
  final String title;
}

/// Why a book could not be imported, in terms the UI can explain.
enum ImportErrorKind {
  /// The phone ran out of space.
  noSpace,

  /// A picked file could not be read (moved, deleted, permission gone).
  unreadable,

  /// The file is in iCloud or another cloud and not on the phone yet.
  notDownloaded,

  /// Anything else. The details say what.
  unknown,
}

final class ImportFailure {
  const ImportFailure({required this.bookName, required this.kind, required this.details});

  final String bookName;
  final ImportErrorKind kind;

  /// Technical details for "Copy details". Never holds file contents.
  final String details;
}

/// How an import ended.
final class ImportOutcome {
  const ImportOutcome({this.added = const [], this.failed = const [], this.cancelled = false});

  final List<ImportedBook> added;
  final List<ImportFailure> failed;

  /// The user stopped the import. Books finished before that are kept.
  final bool cancelled;
}

/// A running import.
abstract interface class ImportJob {
  /// Progress updates, a few per second at most.
  Stream<ImportProgress> get progress;

  /// Completes when the import is over, also after [cancel]. Never fails:
  /// errors are reported per book in [ImportOutcome.failed].
  Future<ImportOutcome> get done;

  /// Stops after the current chunk. The book being copied is removed again;
  /// books already finished stay.
  void cancel();
}

/// Thrown inside the importer when the user cancels.
final class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// Turns picked files into books. Implemented by `LocalImporter`; tests and
/// the UI use this interface so the screen can be driven by a fake.
abstract interface class BookImporter {
  /// Groups the selection into books and checks for duplicates. Copies
  /// nothing.
  Future<ImportPlan> plan(ImportSelection selection);

  /// Imports [books] (usually all of `plan.books`, minus the duplicates the
  /// user chose to skip).
  ImportJob start(List<PlannedBook> books);
}
