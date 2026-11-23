// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/browse_models.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/library/data/library_providers.dart';
import 'package:flutter_test/flutter_test.dart';

BookSummary server(String title) => BookSummary(ref: ItemRef(const AbsSource('acct-affluent'), title), title: title);

BookSummary phone(String title, {bool started = false, bool finished = false}) => BookSummary(
  ref: ItemRef(const LocalSource(), title),
  title: title,
  isDownloaded: true,
  progress: started || finished
      ? ListeningProgress(
          position: const Duration(minutes: 5),
          duration: const Duration(hours: 1),
          isFinished: finished,
          updatedAt: DateTime(2026),
        )
      : null,
);

List<String> titles(List<BookSummary> books) => [for (final b in books) b.title];

void main() {
  group('mixing server books with books on this phone', () {
    test('phone books fall in among server books by title, leading "The" ignored', () {
      final merged = mergeBooks(
        [server('Ash Harbor'), server("The Clockmaker's Tide"), server('Lanterns Under the Ice')],
        [phone('Book 2'), phone('The Moon Road')],
        const LibraryQuery(),
        50,
      );
      expect(titles(merged), [
        'Ash Harbor',
        'Book 2',
        "The Clockmaker's Tide",
        'Lanterns Under the Ice',
        'The Moon Road',
      ]);
    });

    test('a page holds at most the limit; later phone books wait for the next page', () {
      final merged = mergeBooks(
        [server('Ash Harbor'), server('Cinder Interlude')],
        [phone('Zebra Crossing'), phone('Book 2')]..sort(bookComparator(const LibraryQuery())),
        const LibraryQuery(),
        3,
      );
      expect(titles(merged), ['Ash Harbor', 'Book 2', 'Cinder Interlude']);
    });

    test('descending order mixes the same way', () {
      const query = LibraryQuery(descending: true);
      final merged = mergeBooks([server('Cinder Interlude'), server('Ash Harbor')], [phone('Book 2')], query, 50);
      expect(titles(merged), ['Cinder Interlude', 'Book 2', 'Ash Harbor']);
    });
  });

  group('filters on books from this phone', () {
    final books = [phone('Started', started: true), phone('Done', finished: true), phone('Fresh')];

    List<String> filtered(LibraryFilter filter) => titles(applyLocalQuery(books, LibraryQuery(filters: [filter])));

    test('they are always downloaded', () {
      expect(filtered(const LibraryFilter(FilterKind.downloaded, DownloadFilterValue.downloaded)), hasLength(3));
      expect(filtered(const LibraryFilter(FilterKind.downloaded, DownloadFilterValue.notDownloaded)), isEmpty);
    });

    test('progress chips match them like server books', () {
      expect(filtered(const LibraryFilter(FilterKind.progress, ProgressFilterValue.inProgress)), ['Started']);
      expect(filtered(const LibraryFilter(FilterKind.progress, ProgressFilterValue.finished)), ['Done']);
      expect(filtered(const LibraryFilter(FilterKind.progress, ProgressFilterValue.notStarted)), ['Fresh']);
    });

    test('genres, tags and languages come from server libraries, so they match no phone book', () {
      expect(filtered(const LibraryFilter(FilterKind.genre, 'Fantasy')), isEmpty);
      expect(filtered(const LibraryFilter(FilterKind.language, 'English')), isEmpty);
    });

    test('offline, the downloaded filter is added to whatever else is on', () {
      final query = offlineQuery(
        const LibraryQuery(filters: [LibraryFilter(FilterKind.downloaded, DownloadFilterValue.notDownloaded)]),
      );
      expect(query.filterOf(FilterKind.downloaded)?.value, DownloadFilterValue.downloaded);
      expect(query.filters, hasLength(1));
    });
  });
}
