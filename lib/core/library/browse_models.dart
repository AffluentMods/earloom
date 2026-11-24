// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'source_id.dart';

/// How the Books list is ordered.
enum LibrarySort { title, author, addedAt, duration, progress, publishedYear }

/// What kind of value a filter matches.
enum FilterKind {
  progress,
  genre,
  tag,
  series,
  author,
  narrator,
  language,
  downloaded;

  /// Progress and downloads: one tap each, as chips above the books.
  bool get isQuick => this == progress || this == downloaded;
}

/// The values of a [FilterKind.progress] filter.
abstract final class ProgressFilterValue {
  static const notStarted = 'not-started';
  static const inProgress = 'in-progress';
  static const finished = 'finished';
}

/// The values of a [FilterKind.downloaded] filter. Books in the On this
/// device library are always downloaded.
abstract final class DownloadFilterValue {
  static const downloaded = 'true';
  static const notDownloaded = 'false';
}

/// One active filter. [value] is what is matched (an id for series, a name
/// otherwise); [label] is what the chip shows.
@immutable
final class LibraryFilter {
  const LibraryFilter(this.kind, this.value, {String? label}) : label = label ?? value;

  final FilterKind kind;
  final String value;
  final String label;

  @override
  bool operator ==(Object other) => other is LibraryFilter && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Sort plus filters for the Books list. Used as a provider key, so it has
/// value equality.
@immutable
final class LibraryQuery {
  const LibraryQuery({this.sort = LibrarySort.title, this.descending = false, this.filters = const []});

  final LibrarySort sort;
  final bool descending;
  final List<LibraryFilter> filters;

  LibraryQuery copyWith({LibrarySort? sort, bool? descending, List<LibraryFilter>? filters}) => LibraryQuery(
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
    filters: filters ?? this.filters,
  );

  /// Adds [filter], replacing another one of the same kind (one value per
  /// kind, like the server's own filter).
  LibraryQuery withFilter(LibraryFilter filter) =>
      copyWith(filters: [...filters.where((f) => f.kind != filter.kind), filter]);

  LibraryQuery without(LibraryFilter filter) => copyWith(filters: [...filters.where((f) => f != filter)]);

  /// The filters set in the More filters sheet: everything but progress and
  /// downloads, which have their own chips.
  List<LibraryFilter> get moreFilters => [...filters.where((f) => !f.kind.isQuick)];

  LibraryQuery withoutMoreFilters() => copyWith(filters: [...filters.where((f) => f.kind.isQuick)]);

  LibraryFilter? filterOf(FilterKind kind) {
    for (final f in filters) {
      if (f.kind == kind) return f;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.sort == sort &&
      other.descending == descending &&
      listEquals(other.filters, filters);

  @override
  int get hashCode => Object.hash(sort, descending, Object.hashAll(filters));
}

/// What a [BookGroup] gathers.
enum BookGroupKind { author, series }

/// An author or a series of a server library whose books the Audiobooks
/// list shows as one card instead of one card each. The user picks them;
/// the choice stays on this phone.
@immutable
final class BookGroup {
  const BookGroup({
    required this.source,
    required this.libraryId,
    required this.kind,
    required this.id,
    required this.name,
  });

  final SourceId source;
  final String libraryId;
  final BookGroupKind kind;

  /// The server id of the author or the series.
  final String id;

  /// The name when it was picked: what an author's books are matched on,
  /// and what the card shows.
  final String name;

  Map<String, Object?> toJson() => {
    'source': source.key,
    'library': libraryId,
    'kind': kind.name,
    'id': id,
    'name': name,
  };

  /// Null for anything that is not a group written by [toJson].
  static BookGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final source = SourceId.tryParse('${json['source']}');
    final kind = BookGroupKind.values.asNameMap()[json['kind']];
    final library = json['library'];
    final id = json['id'];
    final name = json['name'];
    if (source == null || kind == null || library is! String || id is! String || name is! String || id.isEmpty) {
      return null;
    }
    return BookGroup(source: source, libraryId: library, kind: kind, id: id, name: name);
  }

  /// The same author or series, whatever name it had when picked.
  @override
  bool operator ==(Object other) =>
      other is BookGroup &&
      other.source == source &&
      other.libraryId == libraryId &&
      other.kind == kind &&
      other.id == id;

  @override
  int get hashCode => Object.hash(source, libraryId, kind, id);
}

/// The books that belong to some groups: the members of these series and
/// the books by these authors.
typedef GroupMembers = ({Set<String> seriesIds, Set<String> authorNames});

GroupMembers groupMembers(Iterable<BookGroup> groups) => (
  seriesIds: {
    for (final g in groups)
      if (g.kind == BookGroupKind.series) g.id,
  },
  authorNames: {
    for (final g in groups)
      if (g.kind == BookGroupKind.author) g.name,
  },
);

/// A series in a list: its name, how many books, and the first covers.
final class SeriesSummary {
  const SeriesSummary({
    required this.source,
    required this.id,
    required this.name,
    this.books = const [],
    this.bookCount = 0,
    this.description,
    this.libraryId,
  });

  final SourceId source;

  /// The server id, or the series name for On this device.
  final String id;
  final String name;
  final String? description;

  /// The server library the series is in, when known.
  final String? libraryId;

  /// The books in order, as far as they are known.
  final List<BookSummary> books;
  final int bookCount;

  Duration get totalDuration => books.fold(Duration.zero, (sum, b) => sum + b.duration);
}

final class AuthorSummary {
  const AuthorSummary({
    required this.source,
    required this.id,
    required this.name,
    this.bookCount = 0,
    this.imageUrl,
    this.imageKey,
    this.description,
    this.libraryId,
  });

  final SourceId source;

  /// The library the author is in, when known.
  final String? libraryId;

  /// The server id, or the author name for On this device.
  final String id;
  final String name;
  final int bookCount;

  /// The author photo, or null when the author has none.
  final Uri? imageUrl;
  final String? imageKey;
  final String? description;
}

/// A collection or a playlist.
final class BookListSummary {
  const BookListSummary({
    required this.source,
    required this.id,
    required this.name,
    this.description,
    this.books = const [],
  });

  final SourceId source;
  final String id;
  final String name;
  final String? description;
  final List<BookSummary> books;

  Duration get totalDuration => books.fold(Duration.zero, (sum, b) => sum + b.duration);
}

/// A name with a count, for narrators, genres and tags in search.
final class NamedCount {
  const NamedCount(this.name, this.count);
  final String name;
  final int count;
}

/// The choices the filter sheet offers for one library.
final class FilterChoices {
  const FilterChoices({
    this.genres = const [],
    this.tags = const [],
    this.series = const [],
    this.authors = const [],
    this.narrators = const [],
    this.languages = const [],
  });

  static const empty = FilterChoices();

  final List<String> genres;
  final List<String> tags;

  /// (id, name) pairs.
  final List<(String, String)> series;
  final List<String> authors;
  final List<String> narrators;
  final List<String> languages;
}

/// Search results, grouped the way the Search screen shows them.
final class SearchResults {
  const SearchResults({
    required this.query,
    this.books = const [],
    this.series = const [],
    this.authors = const [],
    this.narrators = const [],
    this.genres = const [],
    this.tags = const [],
    this.localBooks = const [],
    this.podcasts = const [],
    this.episodes = const [],
    this.offline = false,
  });

  final String query;

  /// Podcast shows (a podcast library was searched).
  final List<BookSummary> podcasts;

  /// Podcast episodes: each ref carries its episode id, the title is the
  /// episode's and the author line is the show.
  final List<BookSummary> episodes;

  /// Server books (or cached server books when [offline]).
  final List<BookSummary> books;
  final List<SeriesSummary> series;
  final List<AuthorSummary> authors;
  final List<NamedCount> narrators;
  final List<NamedCount> genres;
  final List<NamedCount> tags;

  /// Books on this phone.
  final List<BookSummary> localBooks;

  /// True when the server could not be asked and the results come from the
  /// cache.
  final bool offline;

  bool get isEmpty =>
      books.isEmpty &&
      series.isEmpty &&
      authors.isEmpty &&
      narrators.isEmpty &&
      genres.isEmpty &&
      tags.isEmpty &&
      podcasts.isEmpty &&
      episodes.isEmpty &&
      localBooks.isEmpty;
}
