// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart' show RequestOptions;
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/podcasts/data/podcast_repository.dart';

import '../library/abs_support.dart';

/// The dev server's podcast library and its one show (fixtures).
const podcastLibraryId = '739e95d2-1d1b-440b-86e2-22424fc2950b';
const showId = 'b3300253-3357-47bf-a078-334445ec4e79';
const pilotId = '826b4698-8c67-4baa-8c70-320f7ad05d5b';
const dogEarsId = '83ec0a82-b7bd-408a-a451-1cb30e69fa0c';
const longShelfId = '91ea913f-c028-45bc-ab73-0f27e4b8ab6d';
const showRef = ItemRef(testSource, showId);

ItemRef episodeRef(String episodeId) => ItemRef(testSource, showId, episodeId: episodeId);

/// Show notes for the pilot, with times to tap.
const pilotNotes = '<p>Cold open, then the interview at <b>0:45</b>. Listener mail at 2:30.</p>';

/// The expanded show, with show notes on the pilot. [extraEpisodes] are
/// added to the end (a new episode on the server).
Map<String, Object?> expandedShow({List<Map<String, Object?>> extraEpisodes = const []}) {
  final item = Map<String, Object?>.from(fixture('item_podcast_expanded')! as Map);
  final media = Map<String, Object?>.from(item['media']! as Map);
  final episodes = [
    for (final e in media['episodes']! as List)
      if ((e as Map)['id'] == pilotId) {...e.cast<String, Object?>(), 'description': pilotNotes} else e,
    ...extraEpisodes,
  ];
  media['episodes'] = episodes;
  item['media'] = media;
  return item;
}

/// A new episode in the shape the server sends.
Map<String, Object?> newEpisode(String id, String title, {int addedAt = 1794500000000}) => {
  'libraryItemId': showId,
  'id': id,
  'title': title,
  'episode': '4',
  'season': null,
  'publishedAt': addedAt,
  'addedAt': addedAt,
  'updatedAt': addedAt,
  'duration': 600,
  'size': 1000,
  'audioFile': {'mimeType': 'audio/mpeg'},
  'chapters': <Object?>[],
};

/// The user as `/api/me` answers, as an admin.
Map<String, Object?> adminUser() => {...(fixture('me_user')! as Map).cast<String, Object?>(), 'type': 'admin'};

/// Routes of the podcast library on the fake server.
Map<String, Object? Function(RequestOptions r)> podcastRoutes() => {
  '/api/libraries/$podcastLibraryId/items': (_) => fixture('library_items_page_podcast'),
  '/api/libraries/$podcastLibraryId/personalized': (_) => fixture('library_personalized_podcast'),
  '/api/libraries/$podcastLibraryId/recent-episodes': (_) => fixture('library_recent_episodes'),
  '/api/libraries/$podcastLibraryId/search': (_) => fixture('library_search_podcast'),
  '/api/libraries/$podcastLibraryId/filterdata': (_) => fixture('library_filterdata_podcast'),
  '/api/items/$showId': (_) => expandedShow(),
  '/api/podcasts/$showId/episode/$pilotId': (_) => fixture('podcast_episode'),
  for (final e in [pilotId, dogEarsId, longShelfId]) '/api/me/progress/$showId/$e': (_) => 'OK',
};

Future<AbsPodcastRepository> fakePodcastRepository(
  FakeAbsServer server,
  AccountDb db, {
  DateTime Function()? clock,
}) async => AbsPodcastRepository(db: db, client: await fakeAbsClient(server), source: testSource, clock: clock);
