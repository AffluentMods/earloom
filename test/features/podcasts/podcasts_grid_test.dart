// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/browse_models.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/library/data/library_providers.dart';
import 'package:earloom/features/podcasts/data/podcast_models.dart';
import 'package:earloom/features/podcasts/data/podcast_providers.dart';
import 'package:flutter_test/flutter_test.dart';

const account = AbsSource('acct-affluent');

ShowSummary show(String title, {required DateTime added, DateTime? latest}) => ShowSummary(
  show: BookSummary(ref: ItemRef(account, title), title: title, addedAt: added),
  latestEpisodeAt: latest,
);

/// The Night Tales Hour moved to Podcasts: newest episode first.
PodcastsGroup nightTales({required DateTime newest}) => PodcastsGroup(
  GroupEntry(
    group: const BookGroup(
      source: account,
      libraryId: 'lib-audiobooks',
      kind: BookGroupKind.author,
      id: 'author-night-tales',
      name: 'The Night Tales Hour',
      place: BookGroupPlace.podcasts,
    ),
    books: [
      BookSummary(ref: const ItemRef(account, 'ep-729'), title: 'Episode 729', addedAt: newest),
      BookSummary(ref: const ItemRef(account, 'ep-1'), title: 'Episode 1', addedAt: DateTime(2019)),
    ],
    count: 729,
  ),
  unplayed: 700,
);

/// Titles of the grid; a moved group shows as "[name]".
List<String> titles(List<PodcastsCard> cards) => [
  for (final c in cards)
    switch (c) {
      PodcastsShowCard(:final show) => show.show.title,
      PodcastsGroupCard(:final group) => '[${group.entry.group.name}]',
    },
];

void main() {
  final shows = [
    show('Shelf Talk', added: DateTime(2026, 3, 1), latest: DateTime(2026, 11, 1)),
    show('Margins', added: DateTime(2026, 9, 1), latest: DateTime(2026, 9, 2)),
  ];

  test('by title a moved author sits among the shows by its name', () {
    expect(titles(podcastsGrid(shows, [nightTales(newest: DateTime(2026, 10, 1))], ShowSort.title)), [
      'Margins',
      'Shelf Talk',
      '[The Night Tales Hour]',
    ]);
  });

  test('by recent episodes and by added it counts its newest book as its newest episode', () {
    final group = nightTales(newest: DateTime(2026, 10, 1));
    expect(titles(podcastsGrid(shows, [group], ShowSort.recentlyUpdated)), [
      'Shelf Talk',
      '[The Night Tales Hour]',
      'Margins',
    ]);
    expect(titles(podcastsGrid(shows, [group], ShowSort.addedAt)), ['[The Night Tales Hour]', 'Margins', 'Shelf Talk']);
  });

  test('without a podcast library only the moved groups show', () {
    final grid = podcastsGrid(const [], [nightTales(newest: DateTime(2026, 10, 1))], ShowSort.title);
    expect(titles(grid), ['[The Night Tales Hour]']);
    expect((grid.single as PodcastsGroupCard).group.unplayed, 700);
  });
}
