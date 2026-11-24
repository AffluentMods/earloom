// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/browse_models.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/library/data/book_groups.dart';
import 'package:earloom/features/library/data/library_providers.dart';
import 'package:flutter_test/flutter_test.dart';

const account = AbsSource('acct-affluent');

BookSummary server(String title, {DateTime? addedAt, List<String> authors = const []}) =>
    BookSummary(ref: ItemRef(account, title), title: title, addedAt: addedAt, authors: authors);

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

const nightTales = BookGroup(
  source: account,
  libraryId: 'lib-audiobooks',
  kind: BookGroupKind.author,
  id: 'author-night-tales',
  name: 'The Night Tales Hour',
);

GroupEntry card(List<BookSummary> books, int count) => GroupEntry(group: nightTales, books: books, count: count);

/// Titles of an Audiobooks list; a group card shows as "[name]".
List<String> titles(List<AudiobooksEntry> entries) => [
  for (final e in entries)
    switch (e) {
      BookEntry(:final book) => book.title,
      GroupEntry(:final group) => '[${group.name}]',
    },
];

List<BookEntry> onPhone(List<BookSummary> books) => [for (final b in books) BookEntry(b)];

void main() {
  group('mixing server books with books on this phone', () {
    test('phone books fall in among server books by title, leading "The" ignored', () {
      final merged = mergeEntries(
        [server('Ash Harbor'), server("The Clockmaker's Tide"), server('Lanterns Under the Ice')],
        onPhone([phone('Book 2'), phone('The Moon Road')]),
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
      final merged = mergeEntries(
        [server('Ash Harbor'), server('Cinder Interlude')],
        onPhone([phone('Zebra Crossing'), phone('Book 2')]),
        const LibraryQuery(),
        3,
      );
      expect(titles(merged), ['Ash Harbor', 'Book 2', 'Cinder Interlude']);
    });

    test('descending order mixes the same way', () {
      const query = LibraryQuery(descending: true);
      final merged = mergeEntries(
        [server('Cinder Interlude'), server('Ash Harbor')],
        onPhone([phone('Book 2')]),
        query,
        50,
      );
      expect(titles(merged), ['Cinder Interlude', 'Book 2', 'Ash Harbor']);
    });
  });

  group('an author or a series kept together as one card', () {
    final episodes = [
      server('Episode 12: The Lighthouse', addedAt: DateTime(2026, 11, 20), authors: ['The Night Tales Hour']),
      server('Episode 3: Static', addedAt: DateTime(2026, 2, 1), authors: ['The Night Tales Hour']),
    ];

    test('by title the card sorts by its name, not by its first book', () {
      final merged = mergeEntries(
        [server('Ash Harbor'), server('Lanterns Under the Ice'), server('Pale Orchard')],
        [card(episodes, 729)],
        const LibraryQuery(),
        50,
      );
      expect(titles(merged), ['Ash Harbor', 'Lanterns Under the Ice', '[The Night Tales Hour]', 'Pale Orchard']);
    });

    test('newest first, the card sits where its newest book would', () {
      const query = LibraryQuery(sort: LibrarySort.addedAt, descending: true);
      final merged = mergeEntries(
        [server('Fresh', addedAt: DateTime(2026, 11, 22)), server('Older', addedAt: DateTime(2026, 6, 1))],
        [card(episodes, 729)],
        query,
        50,
      );
      expect(titles(merged), ['Fresh', '[The Night Tales Hour]', 'Older']);
    });

    test('a card past a full page waits for the next one', () {
      final merged = mergeEntries(
        [server('Ash Harbor'), server('Cinder Interlude')],
        [card(episodes, 729)],
        const LibraryQuery(),
        2,
      );
      expect(titles(merged), ['Ash Harbor', 'Cinder Interlude']);
    });

    test('looking at one author or one series shows its books, not a card', () {
      expect(groupingApplies(const LibraryQuery()), isTrue);
      expect(
        groupingApplies(
          const LibraryQuery(filters: [LibraryFilter(FilterKind.progress, ProgressFilterValue.inProgress)]),
        ),
        isTrue,
      );
      expect(groupingApplies(const LibraryQuery(filters: [LibraryFilter(FilterKind.author, 'Theo Vance')])), isFalse);
      expect(groupingApplies(const LibraryQuery(filters: [LibraryFilter(FilterKind.series, 'series-1')])), isFalse);
    });

    test('the saved list reads back, skipping anything it does not know', () {
      const json =
          '[{"source":"abs:acct-affluent","library":"lib-audiobooks","kind":"author",'
          '"id":"author-night-tales","name":"The Night Tales Hour"},'
          '{"source":"nowhere","kind":"author","id":"x","name":"x"},'
          '{"source":"local","library":"local","kind":"shelf","id":"x","name":"x"},'
          '"junk"]';
      final groups = decodeBookGroups(json);
      expect(groups, [nightTales]);
      expect(groups.single.name, 'The Night Tales Hour');
      expect(decodeBookGroups('not json'), isEmpty);
      expect(decodeBookGroups(null), isEmpty);
    });
  });

  group('filters on books from this phone', () {
    final books = [phone('Started', started: true), phone('Done', finished: true), phone('Fresh')];

    List<String> filtered(LibraryFilter filter) => [
      for (final b in applyLocalQuery(books, LibraryQuery(filters: [filter]))) b.title,
    ];

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
