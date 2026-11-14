// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart' show Value;
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/socket/abs_socket.dart';
import 'package:earloom/features/downloads/data/download_manager.dart';
import 'package:earloom/features/downloads/data/offline_providers.dart';
import 'package:earloom/features/podcasts/data/episode_notifier.dart';
import 'package:earloom/features/podcasts/data/podcast_models.dart';
import 'package:earloom/features/podcasts/data/podcast_providers.dart';
import 'package:earloom/features/podcasts/data/podcast_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_downloads.dart';
import '../library/abs_support.dart';
import 'podcast_support.dart';

EpisodeSummary _episode(
  String id, {
  int day = 1,
  Duration? position,
  bool finished = false,
  String? season,
  String? number,
}) => EpisodeSummary(
  ref: ItemRef(testSource, showId, episodeId: id),
  title: 'Episode $id',
  showTitle: 'Shelf Talk',
  sortDate: DateTime(2026, 1, day),
  duration: const Duration(minutes: 30),
  season: season,
  episodeNumber: number,
  progress: position == null && !finished
      ? null
      : ListeningProgress(
          position: position ?? Duration.zero,
          duration: const Duration(minutes: 30),
          isFinished: finished,
          updatedAt: DateTime(2026),
        ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('episode order and the automatic download rules', () {
    test('sort newest or oldest, filter unplayed, in progress, downloaded', () {
      final episodes = [
        _episode('a', day: 1, finished: true),
        _episode('b', day: 3, position: const Duration(minutes: 5)),
        _episode('c', day: 2),
      ];
      List<String> ids(List<EpisodeSummary> l) => [for (final e in l) e.episodeId];
      expect(ids(arrangeEpisodes(episodes)), ['b', 'c', 'a']);
      expect(ids(arrangeEpisodes(episodes, sort: EpisodeSort.oldest)), ['a', 'c', 'b']);
      expect(ids(arrangeEpisodes(episodes, filter: EpisodeFilter.unplayed)), ['b', 'c']);
      expect(ids(arrangeEpisodes(episodes, filter: EpisodeFilter.inProgress)), ['b']);
      expect(ids(arrangeEpisodes(episodes, filter: EpisodeFilter.downloaded, downloaded: {'a'})), ['a']);
    });

    test('seasons group only when there are seasons', () {
      expect(groupBySeason([_episode('a'), _episode('b')]), isNull);
      final grouped = groupBySeason([
        _episode('a', season: '2'),
        _episode('b', season: '2'),
        _episode('c', season: '1'),
        _episode('d'),
      ])!;
      expect(grouped.map((g) => g.$1), ['2', '1', '']);
      expect(grouped.first.$2.map((e) => e.episodeId), ['a', 'b']);
    });

    test('next unplayed: the next one after, else the newest unplayed before', () {
      final episodes = [
        _episode('a', day: 1),
        _episode('b', day: 2, finished: true),
        _episode('c', day: 3),
        _episode('d', day: 4),
      ];
      expect(nextUnplayedEpisode(episodes, 'a')?.episodeId, 'c');
      expect(nextUnplayedEpisode(episodes, 'd')?.episodeId, 'c');
      expect(nextUnplayedEpisode([_episode('a'), _episode('b', finished: true)], 'a'), isNull);
    });

    test('keep latest N never removes an episode in progress; played ones go when asked', () {
      final downloaded = [
        _episode('new', day: 5),
        _episode('newer-played', day: 4, finished: true),
        _episode('mid', day: 3),
        _episode('old-in-progress', day: 1, position: const Duration(minutes: 10)),
        _episode('older', day: 2),
      ];
      expect(
        episodesToPrune(downloaded, keepLatest: 1, deletePlayed: true),
        ['newer-played', 'mid', 'older'],
      );
      expect(episodesToPrune(downloaded, keepLatest: 0, deletePlayed: true), ['newer-played']);
      expect(episodesToPrune(downloaded, keepLatest: 3, deletePlayed: false), ['older']);
    });
  });

  group('new episodes on the server', () {
    late FakeAbsServer server;
    late AccountDb db;
    late AbsPodcastRepository repository;
    late FakeDownloadManager downloads;
    late MemoryEpisodeNotifier notifier;
    late PodcastAutomation automation;

    setUp(() async {
      server = FakeAbsServer(routes: podcastRoutes());
      db = memoryAccountDb();
      repository = await fakePodcastRepository(server, db);
      downloads = FakeDownloadManager();
      notifier = MemoryEpisodeNotifier();
      final container = ProviderContainer(
        overrides: [
          downloadManagerProvider.overrideWithValue(downloads),
          episodeNotifierProvider.overrideWithValue(notifier),
        ],
      );
      addTearDown(container.dispose);
      automation = container.read(Provider((ref) => PodcastAutomation(ref, repository)));
      await repository.refreshShow(showId);
    });

    Future<NewEpisodes> arrive(List<Map<String, Object?>> episodes) async {
      final next = repository.newEpisodes.first;
      await repository.apply(ItemsChanged([expandedShow(extraEpisodes: episodes)], added: false));
      return next;
    }

    test('download the newest ones for a show with auto-download on, and notify', () async {
      await repository.savePrefs(showId, const ShowPrefs(autoDownload: true, keepLatest: 1, notifyNew: true));
      final event = await arrive([
        newEpisode('ep-4', 'Episode 4 - Margins', addedAt: 1794500000000),
        newEpisode('ep-5', 'Episode 5 - Spines', addedAt: 1794600000000),
      ]);
      await automation.onNewEpisodes(event);
      expect(downloads.calls, ['enqueue ${episodeRef('ep-5').key}']);
      expect(notifier.shown.map((n) => n.body), ['Shelf Talk', 'Shelf Talk']);
      expect(notifier.shown.first.title, contains('Episode 5 - Spines'));
      expect(notifier.shown.first.payload, showId);
    });

    test('a show without automation does nothing', () async {
      final event = await arrive([newEpisode('ep-4', 'Episode 4 - Margins')]);
      await automation.onNewEpisodes(event);
      expect(downloads.calls, isEmpty);
      expect(notifier.shown, isEmpty);
    });

    test('pruning keeps the newest automatic downloads and the one in progress, never manual ones', () async {
      await repository.savePrefs(showId, const ShowPrefs(autoDownload: true, keepLatest: 1, deletePlayed: true));
      await db.catalogDao.upsertProgress(
        ProgressCompanion.insert(
          itemId: showId,
          episodeId: const Value(pilotId),
          currentTime: const Value(45),
          lastUpdate: 1,
        ),
      );
      for (final (id, reason) in [
        (pilotId, DownloadReason.podcast),
        (dogEarsId, DownloadReason.podcast),
        (longShelfId, DownloadReason.user),
      ]) {
        downloads.put(DownloadState(ref: episodeRef(id), phase: DownloadPhase.complete, reason: reason));
      }
      await automation.prune(showRef);
      // The pilot is in progress, Dog Ears is the newest automatic one: both
      // stay. The Long Shelf was downloaded by hand.
      expect(downloads.calls, isEmpty);

      await repository.savePrefs(showId, const ShowPrefs(autoDownload: true, keepLatest: 1));
      downloads.put(
        DownloadState(ref: episodeRef(longShelfId), phase: DownloadPhase.complete, reason: DownloadReason.podcast),
      );
      await automation.prune(showRef);
      expect(downloads.calls, ['delete ${episodeRef(dogEarsId).key}']);
    });
  });
}
