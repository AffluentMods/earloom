// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../../core/util/natural_sort.dart';
import 'audio_formats.dart';
import 'import_planner.dart';
import 'tags/file_tags.dart';

/// An audio file with what its tags say. Pure data: everything here is
/// decided from it without touching the disk.
final class TaggedFile {
  const TaggedFile(this.draft, this.tags);

  final DraftFile draft;
  final FileTags tags;

  String get path => draft.source.segments.join('/');
  String get name => draft.source.name;

  /// Whole milliseconds, as stored, so sums of files and chapter offsets
  /// always agree with the database.
  Duration get duration => Duration(milliseconds: (tags.duration ?? Duration.zero).inMilliseconds);

  /// The disc from the tags, else from the "CD 2" folder.
  int? get disc => tags.discNumber ?? draft.partNumber;
}

/// Playback order: disc, then track number, then natural path order ("2"
/// before "10"). A missing disc counts as the first; files without a track
/// number come after the numbered ones of the same disc.
int compareTrackOrder(TaggedFile a, TaggedFile b) {
  final byDisc = (a.disc ?? 0).compareTo(b.disc ?? 0);
  if (byDisc != 0) return byDisc;
  final ta = a.tags.trackNumber, tb = b.tags.trackNumber;
  if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
  if (ta != null && tb == null) return -1;
  if (ta == null && tb != null) return 1;
  return compareNatural(a.path, b.path);
}

List<TaggedFile> orderFiles(Iterable<TaggedFile> files) => files.toList()..sort(compareTrackOrder);

/// Book level metadata decided from the tags of all its files.
final class BookMetadata {
  const BookMetadata({
    required this.title,
    this.subtitle,
    this.authors = const [],
    this.narrators = const [],
    this.seriesName,
    this.seriesSequence,
    this.description,
    this.genres = const [],
    this.publishedYear,
    this.publisher,
    this.language,
  });

  final String title;
  final String? subtitle;
  final List<String> authors;
  final List<String> narrators;
  final String? seriesName;
  final String? seriesSequence;
  final String? description;
  final List<String> genres;
  final String? publishedYear;
  final String? publisher;
  final String? language;
}

/// Decides the book's metadata. [files] are in playback order. [folderName]
/// is the folder the book came from, null for loose picked files.
///
/// - Title: the album tag, then (for a single file) its title tag, then the
///   folder name, then the first file name.
/// - Authors: the album artist, then the artist.
/// - Narrators: an explicit narrator tag, then the composer (the audiobook
///   convention).
///
/// Values that differ between files take the most common one.
BookMetadata assembleMetadata(List<TaggedFile> files, {String? folderName}) {
  final tags = [for (final f in files) f.tags];
  String? common(String? Function(FileTags t) pick) => mostCommon(tags.map(pick));

  final title =
      common((t) => t.album) ??
      (files.length == 1 ? files.single.tags.title : null) ??
      cleanTag(folderName) ??
      AudioFormats.stemOf(files.first.name);
  final authors = splitNames(common((t) => t.albumArtist) ?? common((t) => t.artist));
  final narrators = splitNames(common((t) => t.narrator) ?? common((t) => t.composer));
  final description = common((t) => t.description);
  final seenGenres = <String>{};
  return BookMetadata(
    title: title,
    subtitle: common((t) => t.subtitle),
    authors: authors,
    narrators: narrators,
    seriesName: common((t) => t.series),
    seriesSequence: common((t) => t.seriesPart),
    // Some taggers copy the title into the comment: that is no description.
    description: description == title ? null : description,
    genres: [
      for (final t in tags)
        for (final g in t.genres)
          if (seenGenres.add(g.toLowerCase())) g,
    ].take(10).toList(),
    publishedYear: common((t) => t.year),
    publisher: common((t) => t.publisher),
    language: common((t) => t.language),
  );
}

/// The most frequent non-empty value, the earliest one on a tie.
String? mostCommon(Iterable<String?> values) {
  final counts = <String, int>{};
  for (final value in values) {
    final v = cleanTag(value);
    if (v != null) counts[v] = (counts[v] ?? 0) + 1;
  }
  String? best;
  var bestCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      best = entry.key;
      bestCount = entry.value;
    }
  }
  return best;
}

/// Splits a tag holding several names: "A; B", "A/B" (the ID3v2.3 way),
/// "A & B", or the NUL separated values of ID3v2.4. A comma does not split, because "Last,
/// First" is a single name.
List<String> splitNames(String? value) {
  if (value == null) return const [];
  final seen = <String>{};
  return [
    for (final part in value.split(RegExp(r'\s*(?:;|\u0000|/|\s&\s)\s*')))
      if (cleanTag(part) case final name? when seen.add(name.toLowerCase())) name,
  ];
}

/// A chapter on the whole-book timeline, before it is stored.
final class ChapterDraft {
  const ChapterDraft({required this.start, required this.end, this.title});

  final Duration start;
  final Duration end;

  /// Null means "Chapter N" in the user's language.
  final String? title;

  @override
  String toString() => 'ChapterDraft($start, $end, $title)';
}

/// Builds the chapters of a book whose [files] are in playback order.
///
/// When any file has embedded chapters, each file contributes its own
/// (shifted to where the file starts in the book), and files without any
/// contribute one chapter. Otherwise every file is one chapter titled from
/// its title tag. Titles that say nothing (empty, the book title, or the
/// same on every file) are left null.
({List<ChapterDraft> chapters, bool fromFiles}) buildChapters(List<TaggedFile> files, {required String bookTitle}) {
  final titles = [for (final f in files) cleanTag(f.tags.title)];
  final distinct = titles.nonNulls.map((t) => t.toLowerCase()).toSet();
  String? fileTitle(int i) {
    final title = titles[i];
    if (title == null) return null;
    if (title.toLowerCase() == bookTitle.toLowerCase()) return null;
    if (files.length > 1 && distinct.length == 1 && titles.every((t) => t != null)) return null;
    return title;
  }

  final hasEmbedded = files.any((f) => f.tags.chapters.isNotEmpty);
  final chapters = <ChapterDraft>[];
  var offset = Duration.zero;
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final length = file.duration;
    final fileEnd = offset + length;
    final embedded = hasEmbedded ? _usableChapters(file.tags.chapters, length) : const <TagChapter>[];
    if (embedded.isEmpty) {
      chapters.add(ChapterDraft(start: offset, end: fileEnd, title: fileTitle(i)));
    } else {
      for (var c = 0; c < embedded.length; c++) {
        final start = offset + embedded[c].start;
        var end = c + 1 < embedded.length ? offset + embedded[c + 1].start : (offset + (embedded[c].end ?? length));
        if (length > Duration.zero && end > fileEnd) end = fileEnd;
        if (c + 1 == embedded.length && length > Duration.zero) end = fileEnd;
        if (end < start) end = start;
        chapters.add(ChapterDraft(start: start, end: end, title: embedded[c].title));
      }
    }
    offset = fileEnd;
  }
  return (chapters: chapters, fromFiles: !hasEmbedded);
}

/// Sorted chapters that start inside the file. The first is pulled to 0 so
/// the start of the file is never outside a chapter.
List<TagChapter> _usableChapters(List<TagChapter> chapters, Duration length) {
  final sorted = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
  final usable = <TagChapter>[];
  for (final chapter in sorted) {
    if (length > Duration.zero && chapter.start >= length) break;
    if (usable.isNotEmpty && chapter.start == usable.last.start) continue;
    usable.add(chapter);
  }
  if (usable.isNotEmpty && usable.first.start > Duration.zero) {
    final first = usable.first;
    usable[0] = TagChapter(start: Duration.zero, end: first.end, title: first.title);
  }
  return usable;
}

/// The container shared by all files (`m4b`, `mp3`...), or `mixed`.
String sourceFormatOf(Iterable<String> fileNames) {
  final formats = fileNames.map(AudioFormats.extensionOf).toSet();
  return formats.length == 1 ? formats.single : 'mixed';
}
