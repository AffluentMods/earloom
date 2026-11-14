// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:path/path.dart' as p;

/// Where imported books live: `<application support>/local/<bookId>/`, one
/// folder per book, holding `track_000.<ext>`... and `cover_<time>.<ext>`.
///
/// Every name on disk is made here from a book id (a UUID) and a fixed
/// pattern, never from tags or the names of the picked files, and every path
/// is checked to stay inside [root]. Nothing a file says can make the app
/// write outside its own folder.
final class LocalStorage {
  LocalStorage(this.root);

  /// `<application support>/local`.
  final Directory root;

  static final _bookId = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final _fileName = RegExp(r'^[a-z]+_[0-9]{3,13}\.[a-z0-9]{2,5}$');
  static const _stagingPrefix = '.import-';

  static bool isBookId(String value) => _bookId.hasMatch(value);

  /// True for the names this class hands out (`track_000.mp3`,
  /// `cover_1731571200000.jpg`).
  static bool isOwnFileName(String value) => _fileName.hasMatch(value);

  /// `track_000.mp3`: the name of the file at [index] in playback order.
  static String trackFileName(int index, String extension) =>
      'track_${index.toString().padLeft(3, '0')}.${_checkedExtension(extension)}';

  /// `cover_<millis>.jpg`. A new cover always gets a new name, which is what
  /// makes image caches let go of the old one.
  static String coverFileName(DateTime time, String extension) =>
      'cover_${time.millisecondsSinceEpoch}.${_checkedExtension(extension)}';

  /// Temporary names used while a book is being copied.
  static String incomingFileName(int index, String extension) =>
      'incoming_${index.toString().padLeft(3, '0')}.${_checkedExtension(extension)}';

  Directory bookDir(String bookId) => Directory(_inside(_checkedBookId(bookId)));

  /// The folder a book is copied into before it is complete. It only becomes
  /// [bookDir] once every file is in place.
  Directory stagingDir(String bookId) => Directory(_inside('$_stagingPrefix${_checkedBookId(bookId)}'));

  File bookFile(String bookId, String fileName) {
    if (!isOwnFileName(fileName)) throw ArgumentError.value(fileName, 'fileName', 'not a library file name');
    return File(p.join(bookDir(bookId).path, fileName));
  }

  File stagedFile(String bookId, String fileName) {
    if (!isOwnFileName(fileName)) throw ArgumentError.value(fileName, 'fileName', 'not a library file name');
    return File(p.join(stagingDir(bookId).path, fileName));
  }

  /// Book folders that exist on disk, by id, and leftover staging folders of
  /// imports that never finished.
  Future<({List<String> bookIds, List<Directory> staging})> scan() async {
    if (!await root.exists()) return (bookIds: const <String>[], staging: const <Directory>[]);
    final ids = <String>[];
    final staging = <Directory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(_stagingPrefix)) {
        staging.add(entity);
      } else if (isBookId(name)) {
        ids.add(name);
      }
    }
    return (bookIds: ids, staging: staging);
  }

  /// Total size of the files in a directory, recursively. 0 if it is gone.
  static Future<int> sizeOf(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  String _inside(String name) {
    final path = p.normalize(p.join(root.path, name));
    if (!p.isWithin(root.path, path)) throw ArgumentError.value(name, 'name', 'escapes the library folder');
    return path;
  }

  static String _checkedBookId(String bookId) {
    if (!isBookId(bookId)) throw ArgumentError.value(bookId, 'bookId', 'not a book id');
    return bookId;
  }

  static String _checkedExtension(String extension) {
    if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(extension)) {
      throw ArgumentError.value(extension, 'extension', 'not a file extension');
    }
    return extension;
  }
}
