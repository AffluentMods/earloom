// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/util/streams.dart';
import '../../library/data/abs_json.dart';
import '../../library/data/library_repository.dart';

/// What a Home shelf holds.
enum ShelfKind { books, series, authors }

/// One Home shelf from the server's personalized view, in server order.
final class HomeShelf {
  const HomeShelf({
    required this.id,
    required this.kind,
    required this.serverLabel,
    this.books = const [],
    this.series = const [],
    this.authors = const [],
  });

  /// The server's shelf id (`continue-series`, `recently-added`), mapped to
  /// our own words in the UI. Unknown ids fall back to [serverLabel].
  final String id;
  final ShelfKind kind;
  final String serverLabel;
  final List<BookSummary> books;
  final List<SeriesSummary> series;
  final List<AuthorSummary> authors;

  bool get isEmpty => books.isEmpty && series.isEmpty && authors.isEmpty;
}

/// Home shelves of one server library: the cached `/personalized` answer,
/// with the books read from the item cache so progress rings stay live.
class HomeRepository {
  HomeRepository(this._library);

  final AbsLibraryRepository _library;

  /// Shelves of [libraryId], from the cache. Emits an empty list when
  /// nothing is cached yet.
  Stream<List<HomeShelf>> watchShelves(String libraryId) {
    return _library.watchShelvesJson(libraryId).switchMap((json) {
      final raw = _decode(json);
      final ids = <String>{
        for (final shelf in raw)
          if (shelf['type'] == 'book' || shelf['type'] == 'podcast')
            for (final e in AbsJson.maps(shelf['entities'])) ?AbsJson.str(e['id']),
      }.toList();
      return _library.db.catalogDao.watchItemsByIds(ids).map((rows) {
        final byId = {for (final r in rows) r.item.id: AbsJson.summary(_library.source, r.item, r.progress)};
        return [
          for (final shelf in raw)
            if (_shelf(shelf, byId) case final parsed? when !parsed.isEmpty) parsed,
        ];
      });
    });
  }

  static List<Map<String, Object?>> _decode(String? json) {
    if (json == null) return const [];
    try {
      return AbsJson.maps(jsonDecode(json));
    } on FormatException {
      return const [];
    }
  }

  HomeShelf? _shelf(Map<String, Object?> json, Map<String, BookSummary> byId) {
    final id = AbsJson.str(json['id']);
    if (id == null) return null;
    final label = AbsJson.str(json['label']) ?? id;
    final entities = AbsJson.maps(json['entities']);
    final source = _library.source;
    switch (json['type']) {
      case 'book' || 'podcast':
        return HomeShelf(
          id: id,
          kind: ShelfKind.books,
          serverLabel: label,
          books: [
            for (final e in entities)
              if (byId[e['id']] case final book?) _withSeries(book, e),
          ],
        );
      case 'series':
        return HomeShelf(
          id: id,
          kind: ShelfKind.series,
          serverLabel: label,
          series: [
            for (final s in entities)
              if (AbsJson.str(s['id']) != null)
                SeriesSummary(
                  source: source,
                  id: s['id'] as String,
                  name: AbsJson.str(s['name']) ?? '',
                  books: [
                    for (final b in AbsJson.maps(s['books'])) byId[b['id']] ?? AbsJson.summaryFromJson(source, b, null),
                  ],
                  bookCount: AbsJson.maps(s['books']).length,
                ),
          ],
        );
      case 'authors':
        return HomeShelf(
          id: id,
          kind: ShelfKind.authors,
          serverLabel: label,
          authors: [
            for (final a in entities)
              if (AbsJson.str(a['id']) != null)
                AuthorSummary(
                  source: source,
                  id: a['id'] as String,
                  name: AbsJson.str(a['name']) ?? '',
                  bookCount: AbsJson.integer(a['numBooks']),
                  imageUrl: AbsJson.str(a['imagePath']) == null
                      ? null
                      : _library.client.url('/api/authors/${a['id']}/image'),
                  imageKey: 'author-${a['id']}-${AbsJson.integer(a['updatedAt'])}',
                ),
          ],
        );
      default:
        // Episode shelves arrive with podcasts in Phase 5.
        return null;
    }
  }

  /// Continue series entities carry the series in a structured form the
  /// cached row may lack: keep the sequence for the card.
  static BookSummary _withSeries(BookSummary book, Map<String, Object?> json) {
    final series = AbsJson.map(AbsJson.map(AbsJson.map(json['media'])['metadata'])['series']);
    final name = AbsJson.str(series['name']);
    if (name == null || book.seriesName != null) return book;
    return BookSummary(
      ref: book.ref,
      title: book.title,
      subtitle: book.subtitle,
      authors: book.authors,
      narrators: book.narrators,
      seriesName: name,
      seriesSequence: AbsJson.str(series['sequence']),
      duration: book.duration,
      coverKey: book.coverKey,
      progress: book.progress,
      isDownloaded: book.isDownloaded,
      addedAt: book.addedAt,
      isPodcast: book.isPodcast,
    );
  }
}
