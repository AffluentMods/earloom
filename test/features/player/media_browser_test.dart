// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:audio_service/audio_service.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/media_browser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

class FakeCatalog implements BrowseCatalog {
  bool offline = false;

  @override
  Future<List<BrowseEntry>> continueListening() async => [
    const BrowseEntry(ref: ItemRef(AbsSource('a1'), 'li1'), title: "The Clockmaker's Tide", progress: 0.4),
  ];

  @override
  Future<List<BrowseEntry>> recentlyAdded() async {
    if (offline) throw Exception('offline');
    return [const BrowseEntry(ref: ItemRef(AbsSource('a1'), 'li2'), title: 'Kindling Sky')];
  }

  @override
  Future<List<BrowseEntry>> onThisDevice() async => [
    const BrowseEntry(ref: ItemRef(LocalSource(), 'b1'), title: 'Salt and Starlight'),
  ];

  @override
  Future<List<BrowseEntry>> latestEpisodes() async => [
    const BrowseEntry(
      ref: ItemRef(AbsSource('a1'), 'p1', episodeId: 'e1'),
      title: 'Episode 1 - Pilot',
      author: 'Shelf Talk',
    ),
  ];

  @override
  Future<List<BrowseEntry>> downloaded() async => [
    const BrowseEntry(ref: ItemRef(AbsSource('a1'), 'li3'), title: 'The Long Way to Morning'),
  ];

  @override
  Future<List<BrowseEntry>> search(String query) async => [
    if (query.contains('salt')) const BrowseEntry(ref: ItemRef(LocalSource(), 'b1'), title: 'Salt and Starlight'),
  ];
}

void main() {
  test('the car sees three folders, then playable books with progress', () async {
    final l10n = await loadL10n();
    final catalog = FakeCatalog();
    final browser = MediaBrowser(catalog, l10n);
    final root = await browser.children(AudioService.browsableRootId);
    expect(root.map((m) => m.title), [
      l10n.autoContinueListening,
      l10n.autoRecentlyAdded,
      l10n.autoPodcasts,
      l10n.autoDownloaded,
      l10n.autoOnThisDevice,
    ]);
    expect((await browser.children(MediaBrowser.downloadedId)).single.title, 'The Long Way to Morning');
    final episode = (await browser.children(MediaBrowser.podcastsId)).single;
    expect(MediaBrowser.refOf(episode.id), const ItemRef(AbsSource('a1'), 'p1', episodeId: 'e1'));
    expect(episode.artist, 'Shelf Talk');
    expect(root.every((m) => m.playable == false), isTrue);

    final cont = await browser.children(MediaBrowser.continueId);
    expect(cont.single.playable, isTrue);
    expect(MediaBrowser.refOf(cont.single.id), const ItemRef(AbsSource('a1'), 'li1'));
    expect(cont.single.extras?['androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE'], 0.4);

    // The system's "recent" root resumes the same list.
    expect((await browser.children(AudioService.recentRootId)).single.title, "The Clockmaker's Tide");

    catalog.offline = true;
    expect(await browser.children(MediaBrowser.recentId), isEmpty, reason: 'offline shows nothing, no error');
    expect((await browser.children(MediaBrowser.deviceId)).single.title, 'Salt and Starlight');
    expect(MediaBrowser.refOf((await browser.search('salt')).single.id), const ItemRef(LocalSource(), 'b1'));
  });
}
