// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../core/library/models.dart';
import 'playable.dart';

/// The chapters the player uses: the book's own, else one per track, else
/// one for the whole book. Never empty for a book with audio.
///
/// [titleForTrack] and [wholeBookTitle] name the fallback chapters; they come
/// from l10n so this file holds no user-facing text.
List<Chapter> effectiveChapters(
  PlayableBook book, {
  required String Function(int number) titleForTrack,
  required String wholeBookTitle,
}) {
  final total = book.duration;
  final own = [
    for (final c in book.chapters)
      if (c.end > c.start) c,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (own.isNotEmpty) {
    return [
      for (var i = 0; i < own.length; i++)
        Chapter(
          index: i,
          title: own[i].title.trim().isEmpty ? titleForTrack(i + 1) : own[i].title,
          start: own[i].start,
          end: i == own.length - 1 && own[i].end < total ? total : own[i].end,
        ),
    ];
  }
  if (book.tracks.length > 1) {
    return [
      for (var i = 0; i < book.tracks.length; i++)
        Chapter(
          index: i,
          title: titleForTrack(i + 1),
          start: book.tracks[i].start,
          end: book.tracks[i].start + book.tracks[i].duration,
        ),
    ];
  }
  return [Chapter(index: 0, title: wholeBookTitle, start: Duration.zero, end: total)];
}

/// Index of the chapter playing at [position]: the last one that starts at
/// or before it.
int chapterIndexAt(List<Chapter> chapters, Duration position) {
  if (chapters.isEmpty) return 0;
  var lo = 0;
  var hi = chapters.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (chapters[mid].start <= position) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// How long into a chapter "previous" still means the chapter before.
const previousChapterGrace = Duration(seconds: 3);

/// Where "previous chapter" goes: within the first few seconds of a chapter,
/// the start of the one before; otherwise the start of the current one.
Duration previousChapterTarget(List<Chapter> chapters, Duration position) {
  if (chapters.isEmpty) return Duration.zero;
  final i = chapterIndexAt(chapters, position);
  final intoChapter = position - chapters[i].start;
  if (intoChapter < previousChapterGrace && i > 0) return chapters[i - 1].start;
  return chapters[i].start;
}

/// Where "next chapter" goes, or null in the last chapter.
Duration? nextChapterTarget(List<Chapter> chapters, Duration position) {
  if (chapters.isEmpty) return null;
  final i = chapterIndexAt(chapters, position);
  return i + 1 < chapters.length ? chapters[i + 1].start : null;
}
