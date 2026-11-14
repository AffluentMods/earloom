// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../../core/util/natural_sort.dart';
import 'audio_formats.dart';
import 'import_source.dart';

/// One audio file of a [BookDraft].
final class DraftFile {
  const DraftFile(this.source, {this.partNumber});

  final ImportSourceFile source;

  /// The number of the "CD 2" / "Disc 2" / "Part 2" folder the file came
  /// from, used as the disc number when the tags have none.
  final int? partNumber;
}

/// A book as the folder structure describes it, before any tag is read.
final class BookDraft {
  const BookDraft({required this.files, this.folderName, this.coverImage});

  /// In natural path order. Tags may reorder them later.
  final List<DraftFile> files;

  /// The folder the book came from, the title fallback after the album tag.
  /// Null for loose picked files (the picker's temporary folders mean
  /// nothing to the user).
  final String? folderName;

  /// An image file next to the audio, used when the tags carry no cover.
  final ImportSourceFile? coverImage;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.source.size);

  /// What to call the book before its tags are read.
  String get displayName => folderName ?? AudioFormats.stemOf(files.first.source.name);
}

/// The books found in a selection, plus the files that were left out.
final class ImportDraft {
  const ImportDraft({required this.books, required this.skippedFiles});

  final List<BookDraft> books;

  /// Names of files that are neither audio the app can play nor images.
  final List<String> skippedFiles;
}

/// "CD1", "CD 02", "Disc 2", "Disk 2 of 3", "Part 1", "Part 1 - The Start",
/// "Vol. 3": a folder that holds one part of a book. Pure numbers do not
/// count: "1", "2" is just as often a series of books.
final _partFolder = RegExp(
  r'^(?:cd|disc|disk|part|pt|vol|volume|teil|parte|partie|tome)[\s._-]*0*(\d{1,3})(?!\d)',
  caseSensitive: false,
);

/// The part number of a folder named like a part of a book, or null.
int? partNumberOf(String folderName) {
  final match = _partFolder.firstMatch(folderName.trim());
  return match == null ? null : int.parse(match[1]!);
}

/// Groups picked files into books (docs/architecture.md section 8):
///
/// - picked files are one book;
/// - a picked folder is one book made of the audio directly inside it plus
///   any "CD 1" / "Disc 2" / "Part 3" sub-folders;
/// - any other sub-folder that holds audio is a book of its own, by the same
///   rules, all the way down.
///
/// Files that are not audio are skipped; an image next to the audio becomes
/// the cover candidate.
ImportDraft planImport(ImportSelection selection) {
  final skipped = <String>[];
  final usable = <ImportSourceFile>[];
  for (final file in selection.files) {
    if (file.segments.isEmpty || file.segments.any(AudioFormats.isJunk)) continue;
    if (AudioFormats.isAudio(file.name) || AudioFormats.isImage(file.name)) {
      usable.add(file);
    } else {
      skipped.add(file.name);
    }
  }
  skipped.sort(compareNatural);

  switch (selection) {
    case PickedFiles():
      final audio = usable.where((f) => AudioFormats.isAudio(f.name)).toList();
      if (audio.isEmpty) return ImportDraft(books: const [], skippedFiles: skipped);
      final images = usable.where((f) => AudioFormats.isImage(f.name)).toList();
      return ImportDraft(
        books: [
          BookDraft(files: _sorted([for (final f in audio) DraftFile(f)]), coverImage: pickCoverImage(images)),
        ],
        skippedFiles: skipped,
      );
    case PickedFolder(:final name):
      final root = _Folder(name);
      for (final file in usable) {
        var node = root;
        for (final segment in file.segments.take(file.segments.length - 1)) {
          node = node.children.putIfAbsent(segment, () => _Folder(segment));
        }
        (AudioFormats.isAudio(file.name) ? node.audio : node.images).add(file);
      }
      final books = <BookDraft>[];
      _collect(root, books);
      return ImportDraft(books: books, skippedFiles: skipped);
  }
}

/// The cover among the images of one folder: a conventional name first
/// (cover.jpg, folder.jpg, front.png...), else the only image, else none.
ImportSourceFile? pickCoverImage(List<ImportSourceFile> images) {
  if (images.isEmpty) return null;
  for (final preferred in AudioFormats.preferredCoverNames) {
    final matches = images.where((f) => AudioFormats.stemOf(f.name).toLowerCase() == preferred).toList()
      ..sort((a, b) => compareNatural(a.name, b.name));
    if (matches.isNotEmpty) return matches.first;
  }
  return images.length == 1 ? images.single : null;
}

class _Folder {
  _Folder(this.name);

  final String name;
  final audio = <ImportSourceFile>[];
  final images = <ImportSourceFile>[];
  final children = <String, _Folder>{};

  bool get hasAudio => audio.isNotEmpty || children.values.any((c) => c.hasAudio);

  Iterable<ImportSourceFile> get allAudio sync* {
    yield* audio;
    for (final child in children.values) {
      yield* child.allAudio;
    }
  }
}

void _collect(_Folder folder, List<BookDraft> books) {
  final withAudio = folder.children.values.where((c) => c.hasAudio).toList()
    ..sort((a, b) => compareNatural(a.name, b.name));
  final parts = withAudio.where((c) => partNumberOf(c.name) != null).toList();
  final others = withAudio.where((c) => partNumberOf(c.name) == null).toList();

  if (folder.audio.isNotEmpty || parts.isNotEmpty) {
    final files = <DraftFile>[
      for (final f in folder.audio) DraftFile(f),
      for (final part in parts)
        for (final f in part.allAudio) DraftFile(f, partNumber: partNumberOf(part.name)),
    ];
    final cover = pickCoverImage(folder.images) ?? pickCoverImage([for (final p in parts) ...p.images]);
    books.add(
      BookDraft(
        files: _sorted(files),
        folderName: folder.name.trim().isEmpty ? null : folder.name.trim(),
        coverImage: cover,
      ),
    );
  }
  for (final other in others) {
    _collect(other, books);
  }
}

List<DraftFile> _sorted(List<DraftFile> files) {
  return files..sort((a, b) => compareNatural(a.source.segments.join('/'), b.source.segments.join('/')));
}
