// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'source_id.dart';

/// What the UI needs to draw a book in a list, a grid or a shelf, whatever
/// its source. Built by each source's repository from its own tables.
final class BookSummary {
  const BookSummary({
    required this.ref,
    required this.title,
    this.subtitle,
    this.authors = const [],
    this.narrators = const [],
    this.seriesName,
    this.seriesSequence,
    this.duration = Duration.zero,
    this.coverKey,
    this.progress,
    this.isDownloaded = false,
    this.addedAt,
    this.isPodcast = false,
  });

  final ItemRef ref;
  final String title;
  final String? subtitle;
  final List<String> authors;
  final List<String> narrators;
  final String? seriesName;

  /// As the server writes it: "1", "2.5", "Book 2".
  final String? seriesSequence;
  final Duration duration;

  /// Changes whenever the cover changes, so caches and cover colors refresh.
  /// Null when the book has no cover.
  final String? coverKey;
  final ListeningProgress? progress;

  /// Playable without a network: always true for local books.
  final bool isDownloaded;
  final DateTime? addedAt;
  final bool isPodcast;

  String get authorLine => authors.join(', ');
}

/// How far the user is in a book (or episode).
final class ListeningProgress {
  const ListeningProgress({
    required this.position,
    required this.duration,
    this.isFinished = false,
    this.finishedAt,
    required this.updatedAt,
  });

  final Duration position;
  final Duration duration;
  final bool isFinished;
  final DateTime? finishedAt;
  final DateTime updatedAt;

  /// 0 to 1.
  double get fraction {
    if (isFinished) return 1;
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get remaining {
    final left = duration - position;
    return left.isNegative ? Duration.zero : left;
  }

  bool get isStarted => isFinished || position > const Duration(seconds: 5);
}

final class Chapter {
  const Chapter({required this.index, required this.title, required this.start, required this.end});

  final int index;
  final String title;
  final Duration start;
  final Duration end;

  Duration get duration => end - start;

  bool contains(Duration position) => position >= start && position < end;
}

final class Bookmark {
  const Bookmark({required this.ref, required this.position, required this.title, required this.createdAt});

  final ItemRef ref;
  final Duration position;
  final String title;
  final DateTime createdAt;
}

/// Everything the detail screen shows.
final class BookDetail {
  const BookDetail({
    required this.summary,
    this.descriptionHtml,
    this.genres = const [],
    this.tags = const [],
    this.publisher,
    this.publishedYear,
    this.language,
    this.isbn,
    this.asin,
    this.chapters = const [],
    this.series = const [],
    this.sizeBytes,
    this.fileFormat,
  });

  final BookSummary summary;

  /// Raw HTML from the server or the tags. Always render it through the
  /// sanitizer in lib/core/util/html_sanitize.dart.
  final String? descriptionHtml;
  final List<String> genres;
  final List<String> tags;
  final String? publisher;
  final String? publishedYear;
  final String? language;
  final String? isbn;
  final String? asin;
  final List<Chapter> chapters;
  final List<SeriesMembership> series;
  final int? sizeBytes;
  final String? fileFormat;
}

final class SeriesMembership {
  const SeriesMembership({required this.id, required this.name, this.sequence});

  final String id;
  final String name;
  final String? sequence;
}

/// A library inside a source. The On this device source has exactly one.
final class LibraryInfo {
  const LibraryInfo({required this.source, required this.id, required this.name, this.isPodcast = false});

  final SourceId source;
  final String id;
  final String name;
  final bool isPodcast;
}
