// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/socket/abs_socket.dart';
import 'package:earloom/features/library/data/abs_json.dart';
import 'package:earloom/features/podcasts/data/podcast_json.dart';
import 'package:earloom/features/podcasts/data/podcast_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../library/abs_support.dart';
import 'podcast_support.dart';

void main() {
  late FakeAbsServer server;
  late AccountDb db;

  setUp(() {
    server = FakeAbsServer(routes: podcastRoutes());
    db = memoryAccountDb();
  });

  test('a show: header, all episodes with show notes, the episode count, progress per episode', () async {
    final library = await fakeRepository(server, db);
    final podcasts = await fakePodcastRepository(server, db);
    await library.refreshProgress();
    await podcasts.refreshShow(showId);

    final show = await podcasts.watchShow(showId).first;
    expect(show!.show.title, 'Shelf Talk');
    expect(show.author, 'Affluent Demo Network');
    expect(show.descriptionHtml, contains('0:45'));
    expect(show.summary.episodeCount, 3);
    // Nothing finished yet: every episode is unplayed.
    expect(show.summary.unplayed, 3);

    final episodes = arrangeEpisodes(await podcasts.watchEpisodes(showId).first);
    expect(episodes.map((e) => e.title), ['Episode 3 - The Long Shelf', 'Episode 2 - Dog Ears', 'Episode 1 - Pilot']);
    final pilot = episodes.last;
    expect(pilot.ref, episodeRef(pilotId));
    expect(pilot.showTitle, 'Shelf Talk');
    expect(pilot.descriptionHtml, pilotNotes);
    expect(pilot.duration, const Duration(minutes: 5));
    expect(pilot.episodeNumber, '1');
    // Progress is the pilot's own, not the show's.
    expect(pilot.progress?.position, const Duration(seconds: 45));
    expect(pilot.isInProgress, isTrue);
    expect(episodes.first.progress, isNull);
    // The detail cache keeps the show without its episodes.
    final detail = await db.catalogDao.detail(showId);
    expect(detail!.json, isNot(contains('Dog Ears')));
  });

  test('unplayed counts: from the server count before the episodes are cached, then per episode', () async {
    final library = await fakeRepository(server, db);
    final podcasts = await fakePodcastRepository(server, db);
    await library.syncLibrary(podcastLibraryId);
    await db.catalogDao.upsertProgress(
      ProgressCompanion.insert(
        itemId: showId,
        episodeId: const Value(dogEarsId),
        isFinished: const Value(true),
        lastUpdate: 1,
      ),
    );
    var shows = await podcasts.watchShows(podcastLibraryId).first;
    expect(shows.single.episodeCount, 3, reason: 'numEpisodes from the library list');
    expect(shows.single.unplayed, 2);

    await podcasts.refreshShow(showId);
    shows = await podcasts.watchShows(podcastLibraryId).first;
    expect(shows.single.unplayed, 2);

    await podcasts.setPlayed(episodeRef(pilotId), played: true);
    shows = await podcasts.watchShows(podcastLibraryId).first;
    expect(shows.single.unplayed, 1);
    expect(server.requestsTo('/api/me/progress/$showId/$pilotId').single.data, {'isFinished': true});

    await podcasts.setPlayed(episodeRef(pilotId), played: false);
    expect((await podcasts.watchShows(podcastLibraryId).first).single.unplayed, 2);
  });

  test('marking played goes back when the server says no', () async {
    server.routes.remove('/api/me/progress/$showId/$longShelfId');
    final podcasts = await fakePodcastRepository(server, db);
    await podcasts.refreshShow(showId);
    await expectLater(podcasts.setPlayed(episodeRef(longShelfId), played: true), throwsA(anything));
    final e = await podcasts.watchEpisode(episodeRef(longShelfId)).first;
    expect(e!.isPlayed, isFalse);
  });

  test('a new episode from the socket is cached and announced; the first look at a show announces nothing', () async {
    final podcasts = await fakePodcastRepository(server, db);
    final announced = <NewEpisodes>[];
    final sub = podcasts.newEpisodes.listen(announced.add);
    addTearDown(sub.cancel);

    await podcasts.refreshShow(showId);
    await pumpEventQueue();
    expect(announced, isEmpty);

    await podcasts.apply(
      ItemsChanged([
        expandedShow(extraEpisodes: [newEpisode('ep-new', 'Episode 4 - Margins')]),
      ], added: false),
    );
    await pumpEventQueue();
    expect(announced.single.show, showRef);
    expect(announced.single.episodes.single.title, 'Episode 4 - Margins');
    expect((await podcasts.watchEpisodes(showId).first).length, 4);
    // No request needed: the socket sent the whole show.
    expect(server.requestsTo('/api/items/$showId'), hasLength(1));

    // The same update again is nothing new.
    await podcasts.apply(
      ItemsChanged([
        expandedShow(extraEpisodes: [newEpisode('ep-new', 'Episode 4 - Margins')]),
      ], added: false),
    );
    await pumpEventQueue();
    expect(announced, hasLength(1));
  });

  test('an episode removed on the server goes from the cache', () async {
    final podcasts = await fakePodcastRepository(server, db);
    await podcasts.refreshShow(showId);
    final fewer = expandedShow();
    final media = Map<String, Object?>.from(fewer['media']! as Map);
    media['episodes'] = [(media['episodes']! as List).first];
    fewer['media'] = media;
    server.routes['/api/items/$showId'] = (_) => fewer;
    await podcasts.refreshShow(showId, force: true);
    expect((await podcasts.watchEpisodes(showId).first).map((e) => e.episodeId), [pilotId]);
  });

  test('podcast Home: shelves with episodes, the latest episodes, the episode in progress', () async {
    final library = await fakeRepository(server, db);
    final podcasts = await fakePodcastRepository(server, db);
    await library.refreshProgress();
    await podcasts.refreshHome(podcastLibraryId);

    final shelves = await podcasts.watchShelves(podcastLibraryId).first;
    expect(shelves.map((s) => s.id), ['continue-listening', 'newest-episodes', 'recently-added']);
    expect(shelves.first.episodes.map((e) => e.episodeId), [longShelfId, dogEarsId]);
    expect(shelves.first.episodes.first.showTitle, 'Shelf Talk');
    expect(shelves.last.shows.single.title, 'Shelf Talk');

    final latest = await podcasts.watchRecentEpisodes(podcastLibraryId).first;
    expect(latest.map((e) => e.episodeId), [pilotId, dogEarsId]);

    final inProgress = await podcasts.watchInProgress(podcastLibraryId).first;
    expect(inProgress.single.episodeId, pilotId);
    expect(inProgress.single.progress?.position, const Duration(seconds: 45));
  });

  test('search a podcast library: shows and episodes in their own groups', () async {
    final library = await fakeRepository(server, db);
    final results = await library.search(podcastLibraryId, 'shelf');
    expect(results.books, isEmpty);
    expect(results.podcasts.single.title, 'Shelf Talk');
    expect(results.episodes.single.title, 'Episode 3 - The Long Shelf');
    expect(results.episodes.single.ref, episodeRef(longShelfId));
    expect(results.episodes.single.authors, ['Shelf Talk']);
    // Offline, the cache answers the same groups.
    server.offline = true;
    final offline = await library.searchOffline('long shelf', libraryId: podcastLibraryId);
    expect(offline.episodes.single.ref, episodeRef(longShelfId));
  });

  test('the user type and permissions from /api/me are kept', () async {
    server.routes['/api/me'] = (_) => adminUser();
    final library = await fakeRepository(server, db);
    await library.refreshProgress();
    final json = await library.watchAccessJson().first;
    final access = UserAccess.fromUser(AbsJson.map(jsonDecode(json!)));
    expect(access.isAdmin, isTrue);
  });

  test('the next unplayed episode after one finishes', () async {
    final podcasts = await fakePodcastRepository(server, db);
    await podcasts.refreshShow(showId);
    final next = await podcasts.nextUnplayed(episodeRef(pilotId));
    expect(next?.episodeId, dogEarsId);
  });

  test('2,000 episodes load from the cache in well under 300 ms', () async {
    final rows = [
      for (var i = 0; i < 2000; i++)
        PodcastJson.episode({
          'id': 'ep-$i',
          'libraryItemId': showId,
          'title': 'Episode $i',
          'description': '<p>Notes for episode $i, with a time at 12:34.</p>',
          'publishedAt': 1700000000000 + i * 86400000,
          'duration': 1800,
          'episode': '$i',
        })!,
    ];
    await db.podcastDao.replaceEpisodes(showId, rows);
    final podcasts = await fakePodcastRepository(server, db);
    final watch = Stopwatch()..start();
    final episodes = await podcasts.watchEpisodes(showId).first;
    final arranged = arrangeEpisodes(episodes, filter: EpisodeFilter.unplayed);
    watch.stop();
    expect(arranged, hasLength(2000));
    expect(arranged.first.episodeId, 'ep-1999');
    expect(watch.elapsedMilliseconds, lessThan(300));
  });
}
