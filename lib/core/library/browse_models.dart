// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'source_id.dart';

/// How the Books list is ordered.
enum LibrarySort { title, author, addedAt, duration, progress, publishedYear }

/// What kind of value a filter matches.
enum FilterKind { progress, genre, tag, series, author, narrator, language, downloaded }

/// The values of a [FilterKind.progress] filter.
abstract final class ProgressFilterValue {
  static const notStarted = 'not-started';
  static const inProgress = 'in-progress';
  static const finished = 'finished';
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

/// A series in a list: its name, how many books, and the first covers.
final class SeriesSummary {
  const SeriesSummary({
    required this.source,
    required this.id,
    required this.name,
    this.books = const [],
    this.bookCount = 0,
    this.description,
  });

  final SourceId source;

  /// The server id, or the series name for On this device.
  final String id;
  final String name;
  final String? description;

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
    this.offline = false,
  });

  final String query;

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
      localBooks.isEmpty;
}
