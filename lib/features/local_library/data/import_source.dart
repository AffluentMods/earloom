// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

/// One file the user picked, wherever it lives: a plain file, a temporary
/// copy the system picker made, or an Android document reached through the
/// Storage Access Framework.
abstract class ImportSourceFile {
  /// Where the file sits relative to what the user picked: the folders below
  /// a picked folder plus the file name, or only the file name for picked
  /// files. Used to group and order files, never to build a path on disk.
  List<String> get segments;

  String get name => segments.last;

  /// Size in bytes.
  int get size;

  /// Reads the file, or the byte range from [start] (inclusive) to [end]
  /// (exclusive).
  Stream<List<int>> openRead([int? start, int? end]);

  /// Moves the file to [destination] instead of copying it, when it is a
  /// temporary copy the app owns (the system picker's cache). Returns false
  /// when that is not possible, and the caller copies instead.
  Future<bool> tryMoveTo(String destination) async => false;

  @override
  String toString() => segments.join('/');
}

/// A file the app can open with `dart:io`.
class IoImportFile extends ImportSourceFile {
  IoImportFile(this.file, {required this.segments, required this.size, this.isTemporaryCopy = false});

  /// Builds a source from a file on disk, reading its size.
  static Future<IoImportFile> fromFile(File file, {List<String>? segments, bool isTemporaryCopy = false}) async {
    return IoImportFile(
      file,
      segments: segments ?? [file.uri.pathSegments.last],
      size: await file.length(),
      isTemporaryCopy: isTemporaryCopy,
    );
  }

  final File file;
  @override
  final List<String> segments;
  @override
  final int size;

  /// True for copies the system picker made for us: those can be moved.
  final bool isTemporaryCopy;

  @override
  Stream<List<int>> openRead([int? start, int? end]) => file.openRead(start, end);

  @override
  Future<bool> tryMoveTo(String destination) async {
    if (!isTemporaryCopy) return false;
    try {
      await file.rename(destination);
      return true;
    } on FileSystemException {
      // Another volume: the caller copies.
      return false;
    }
  }
}

/// What the user picked.
sealed class ImportSelection {
  const ImportSelection(this.files);

  final List<ImportSourceFile> files;

  /// Called once the import is over, whatever the outcome: releases folder
  /// access and removes the picker's temporary copies.
  Future<void> Function()? get onDone;
}

/// Several files picked at once: one book.
final class PickedFiles extends ImportSelection {
  const PickedFiles(super.files, {this.onDone});

  @override
  final Future<void> Function()? onDone;
}

/// A folder: one book, or one book per sub-folder that holds audio.
final class PickedFolder extends ImportSelection {
  const PickedFolder(this.name, super.files, {this.onDone});

  /// The picked folder's own name, the title fallback for a book made of the
  /// files directly inside it.
  final String name;

  @override
  final Future<void> Function()? onDone;
}
