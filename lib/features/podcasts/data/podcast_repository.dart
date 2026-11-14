// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show InsertMode, Value;

import '../../../core/db/account_db.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_client.dart';
import '../../../core/net/abs_errors.dart';
import '../../../core/socket/abs_socket.dart';
import '../../../core/util/streams.dart';
import '../../library/data/abs_json.dart';
import '../../library/data/library_repository.dart' show Freshness;
import 'podcast_json.dart';
import 'podcast_models.dart';

/// One shelf of the podcast Home: episodes, or shows.
final class PodcastShelf {
  const PodcastShelf({required this.id, required this.serverLabel, this.episodes = const [], this.shows = const []});

  /// The server's shelf id (`continue-listening`, `newest-episodes`).
  final String id;
  final String serverLabel;
  final List<EpisodeSummary> episodes;
  final List<BookSummary> shows;

  bool get isEmpty => episodes.isEmpty && shows.isEmpty;
}

/// Podcasts of one Audiobookshelf account (docs/plan/06-phase5-podcasts.md):
/// shows, episodes, the podcast Home and the admin actions. Like the
/// library repository, everything is written to the cache and read back
/// from it; refreshes throw [AbsFailure] for the screen to show next to
/// the cached content.
class AbsPodcastRepository {
  AbsPodcastRepository({required this.db, required this.client, required this.source, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AccountDb db;
  final AbsClient client;
  final AbsSource source;
  final DateTime Function() _clock;

  PodcastDao get _dao => db.podcastDao;
  CatalogDao get _catalog => db.catalogDao;
  int get _now => _clock().millisecondsSinceEpoch;

  final _newEpisodes = StreamController<NewEpisodes>.broadcast();
  final _showSyncs = <String, Future<void>>{};

  /// Episodes that appeared on the server for a show the app already knew
  /// (from a refresh, the socket or a shelf). The first look at a show
  /// announces nothing.
  Stream<NewEpisodes> get newEpisodes => _newEpisodes.stream;

  void dispose() => unawaited(_newEpisodes.close());

  static String _showKey(String itemId) => 'show:$itemId';
  static String _recentKey(String libraryId) => 'recent-episodes:$libraryId';

  // --- Shows ---

  ShowSummary _showSummary(ShowRow r) => ShowSummary(
    show: AbsJson.summary(source, r.item, null),
    episodeCount: r.episodeCount,
    unplayed: r.unplayed,
    latestEpisodeAt: r.latestEpisodeAt == null ? null : DateTime.fromMillisecondsSinceEpoch(r.latestEpisodeAt!),
  );

  Stream<List<ShowSummary>> watchShows(String libraryId, {ShowSort sort = ShowSort.title}) =>
      _dao.watchShows(libraryId).map((rows) => sortShows([for (final r in rows) _showSummary(r)], sort));

  /// The show header: the list row at once, the cached details when there.
  Stream<ShowDetail?> watchShow(String itemId) => combineLatest2(
    _dao.watchShow(itemId),
    _catalog.watchDetail(itemId),
    (ShowRow? row, ItemDetailRow? detail) {
      if (row == null) return null;
      final summary = _showSummary(row);
      if (detail == null) return ShowDetail(summary: summary, libraryId: row.item.libraryId);
      try {
        return PodcastJson.detail(summary, AbsJson.map(jsonDecode(detail.json)));
      } on FormatException {
        return ShowDetail(summary: summary, libraryId: row.item.libraryId);
      }
    },
  );

  /// The expanded show with all its episodes. A 404 removes it from the
  /// cache.
  Future<void> refreshShow(String itemId, {bool force = false}) async {
    if (!force) {
      final at = int.tryParse(await _catalog.meta(_showKey(itemId)) ?? '');
      if (at != null && _now - at < Freshness.item.inMilliseconds) return;
    }
    final Map<String, Object?> json;
    try {
      json = await client.get<Map<String, Object?>>('/api/items/$itemId', query: {'expanded': 1});
    } on AbsHttpError catch (e) {
      if (e.status == 404) {
        await _catalog.deleteItem(itemId);
        await _dao.deleteEpisodesOf(itemId);
      }
      rethrow;
    }
    await _writeShow(json);
  }

  Future<void> _writeShow(Map<String, Object?> json) async {
    final id = AbsJson.str(json['id']);
    if (id == null || json['mediaType'] != 'podcast') return;
    final episodes = PodcastJson.episodesOf(json);
    // The header keeps the show without its (possibly thousands of)
    // episodes: they live in their own table.
    final media = Map<String, Object?>.from(AbsJson.map(json['media']))..remove('episodes');
    final copy = Map<String, Object?>.from(json)
      ..remove('userMediaProgress')
      ..['media'] = media;
    await _catalog.upsertItems([AbsJson.item(json).copyWith(numEpisodes: Value(episodes.length))]);
    await _catalog.putDetail(id, jsonEncode(copy), _now);
    final known = await _catalog.meta(_showKey(id)) != null;
    final diff = await _dao.replaceEpisodes(id, episodes);
    await _catalog.setMeta(_showKey(id), '$_now');
    if (known && diff.added.isNotEmpty) await _announce(id, diff.added);
  }

  Future<void> _announce(String itemId, List<String> episodeIds) async {
    final show = await _catalog.watchItem(itemId).first;
    if (show == null) return;
    final ids = episodeIds.toSet();
    final episodes = [
      for (final e in await _dao.episodesOf(itemId))
        if (ids.contains(e.episode.id)) _episode(e, show.item),
    ];
    if (episodes.isNotEmpty && !_newEpisodes.isClosed) {
      _newEpisodes.add(NewEpisodes(show: ItemRef(source, itemId), episodes: episodes));
    }
  }

  /// Refreshes every show of a library that was not fetched in the last
  /// hours, one at a time, so offline browsing has every episode list and
  /// new episodes are found. Stops quietly when the server is unreachable.
  Future<void> syncShows(String libraryId) {
    final running = _showSyncs[libraryId];
    if (running != null) return running;
    final future = () async {
      final shows = (await _catalog.itemsOfLibrary(libraryId)).where((i) => i.mediaType == 'podcast');
      for (final show in shows) {
        final at = int.tryParse(await _catalog.meta(_showKey(show.id)) ?? '');
        if (at != null && _now - at < Freshness.fullSync.inMilliseconds) continue;
        try {
          await refreshShow(show.id, force: true);
        } on AbsUnreachable {
          return;
        } on AbsFailure {
          // That show alone; the next sync tries again.
        }
      }
    }().whenComplete(() => _showSyncs.remove(libraryId));
    _showSyncs[libraryId] = future;
    return future;
  }

  // --- Episodes ---

  EpisodeSummary _episode(EpisodeWithProgress e, ItemRow? show) => PodcastJson.summary(
    source,
    e.episode,
    showTitle: show?.title ?? '',
    showAuthor: show == null || show.authors.isEmpty ? null : show.authors.join(', '),
    coverKey: show != null && show.hasCover ? '${show.updatedAt}' : null,
    progress: e.progress,
  );

  /// A show's episodes, newest first, with live progress.
  Stream<List<EpisodeSummary>> watchEpisodes(String itemId) => combineLatest2(
    _catalog.watchItem(itemId),
    _dao.watchEpisodes(itemId),
    (ItemWithProgress? show, List<EpisodeWithProgress> episodes) => [
      for (final e in episodes) _episode(e, show?.item),
    ],
  );

  Stream<EpisodeSummary?> watchEpisode(ItemRef ref) => combineLatest2(
    _catalog.watchItem(ref.itemId),
    _dao.watchEpisode(ref.episodeId ?? ''),
    (ItemWithProgress? show, EpisodeWithProgress? e) => e == null ? null : _episode(e, show?.item),
  );

  /// One episode from the server, for an episode that is not cached yet.
  Future<void> refreshEpisode(ItemRef ref) async {
    final json = await client.get<Map<String, Object?>>('/api/podcasts/${ref.itemId}/episode/${ref.episodeId}');
    final row = PodcastJson.episode(json, itemId: ref.itemId);
    if (row != null) await _dao.mergeEpisodes([row]);
  }

  /// Marks an episode played or not. The cache changes at once; it goes
  /// back if the server says no.
  Future<void> setPlayed(ItemRef ref, {required bool played}) async {
    final episodeId = ref.episodeId!;
    final before = await _catalog.progressOf(ref.itemId, episodeId: episodeId);
    final episode = await _dao.episode(episodeId);
    await _catalog.upsertProgress(
      ProgressCompanion.insert(
        itemId: ref.itemId,
        episodeId: Value(episodeId),
        progressId: Value(before?.progressId),
        currentTime: Value(played ? (before?.currentTime ?? 0) : 0),
        duration: Value(before?.duration ?? episode?.durationSec ?? 0),
        progress: Value(played ? 1 : 0),
        isFinished: Value(played),
        finishedAt: Value(played ? _now : null),
        lastUpdate: _now,
      ),
    );
    try {
      await client.patch<Object?>('/api/me/progress/${ref.itemId}/$episodeId', body: {'isFinished': played});
    } on Object {
      if (before == null) {
        await _catalog.deleteProgress(ref.itemId, episodeId: episodeId);
      } else {
        await _catalog.upsertProgress(before.toCompanion(true));
      }
      rethrow;
    }
  }

  /// What plays after [finished] when nothing is queued: see
  /// [nextUnplayedEpisode].
  Future<EpisodeSummary?> nextUnplayed(ItemRef finished) async {
    final show = await _catalog.watchItem(finished.itemId).first;
    final episodes = [for (final e in await _dao.episodesOf(finished.itemId)) _episode(e, show?.item)];
    return nextUnplayedEpisode(episodes, finished.episodeId ?? '');
  }

  // --- Home ---

  /// Episodes in progress in a library, most recent first.
  Stream<List<EpisodeSummary>> watchInProgress(String libraryId, {int limit = 20}) => _dao
      .watchEpisodesInProgress(libraryId: libraryId, limit: limit)
      .map(
        (rows) => [
          for (final r in rows)
            if (r.episode != null) _episode((episode: r.episode!, progress: r.progress), r.show),
        ],
      );

  /// The personalized shelves and the latest episodes of a podcast
  /// library. Shelves at most every 2 minutes unless forced.
  Future<void> refreshHome(String libraryId, {bool force = false}) async {
    final cached = await _catalog.shelvesOf(libraryId);
    if (force || cached == null || _now - cached.fetchedAt >= Freshness.shelves.inMilliseconds) {
      final json = await client.get<List<Object?>>('/api/libraries/$libraryId/personalized', query: {'limit': 12});
      final shows = <ItemsCompanion>[];
      final episodes = <EpisodesCompanion>[];
      for (final shelf in AbsJson.maps(json)) {
        for (final e in AbsJson.maps(shelf['entities'])) {
          if (AbsJson.str(e['id']) == null || e['mediaType'] != 'podcast') continue;
          shows.add(AbsJson.item(e));
          final recent = AbsJson.map(e['recentEpisode']);
          final row = recent.isEmpty ? null : PodcastJson.episode(recent, itemId: e['id'] as String);
          if (row != null) episodes.add(row);
        }
      }
      await _catalog.upsertItems(shows);
      await _mergeAndAnnounce(episodes);
      await _catalog.putShelves(libraryId, jsonEncode(json), _now);
    }
    await refreshRecentEpisodes(libraryId, force: force);
  }

  Future<void> _mergeAndAnnounce(List<EpisodesCompanion> rows) async {
    final added = await _dao.mergeEpisodes(rows);
    if (added.isEmpty) return;
    final byShow = <String, List<String>>{};
    for (final r in rows) {
      if (added.contains(r.id.value)) (byShow[r.itemId.value] ??= []).add(r.id.value);
    }
    for (final MapEntry(key: itemId, value: ids) in byShow.entries) {
      // Only a show whose full list was seen can have "new" episodes.
      if (await _catalog.meta(_showKey(itemId)) != null) await _announce(itemId, ids);
    }
  }

  /// The newest episodes across the library (`recent-episodes`).
  Future<void> refreshRecentEpisodes(String libraryId, {bool force = false}) async {
    final key = _recentKey(libraryId);
    if (!force) {
      final at = int.tryParse(await _catalog.meta('$key:at') ?? '');
      if (at != null && _now - at < Freshness.shelves.inMilliseconds) return;
    }
    final json = await client.get<Map<String, Object?>>(
      '/api/libraries/$libraryId/recent-episodes',
      query: {'limit': 25, 'page': 0},
    );
    final rows = <EpisodesCompanion>[];
    final pairs = <List<String>>[];
    for (final e in AbsJson.maps(json['episodes'])) {
      final row = PodcastJson.episode(e);
      if (row == null) continue;
      rows.add(row);
      pairs.add([row.itemId.value, row.id.value]);
      // A show not cached yet still gets a title and cover.
      final podcast = AbsJson.map(e['podcast']);
      if (podcast.isNotEmpty) {
        await db
            .into(db.items)
            .insert(
              AbsJson.item({
                'id': row.itemId.value,
                'libraryId': AbsJson.str(e['libraryId']) ?? libraryId,
                'mediaType': 'podcast',
                'media': podcast,
              }),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
    await _mergeAndAnnounce(rows);
    await _catalog.setMeta(key, jsonEncode(pairs));
    await _catalog.setMeta('$key:at', '$_now');
  }

  Stream<List<EpisodeSummary>> watchRecentEpisodes(String libraryId) =>
      _catalog.watchMeta(_recentKey(libraryId)).switchMap((json) {
        final pairs = _pairs(json);
        return _watchEpisodeList(pairs);
      });

  static List<(String, String)> _pairs(String? json) {
    if (json == null) return const [];
    try {
      final list = jsonDecode(json);
      return [
        if (list is List)
          for (final p in list)
            if (p is List && p.length == 2 && p[0] is String && p[1] is String) (p[0] as String, p[1] as String),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Episodes by (show, episode) id, in that order, with live progress.
  Stream<List<EpisodeSummary>> _watchEpisodeList(List<(String, String)> pairs) {
    if (pairs.isEmpty) return Stream.value(const []);
    final showIds = {for (final p in pairs) p.$1}.toList();
    return combineLatest2(
      _dao.watchEpisodesByIds([for (final p in pairs) p.$2]),
      _catalog.watchItemsByIds(showIds),
      (List<EpisodeWithProgress> episodes, List<ItemWithProgress> shows) {
        final byId = {for (final s in shows) s.item.id: s.item};
        return [for (final e in episodes) _episode(e, byId[e.episode.itemId])];
      },
    );
  }

  /// The cached personalized shelves of a podcast library, with live
  /// progress. Continue listening is left in: the screen decides.
  Stream<List<PodcastShelf>> watchShelves(String libraryId) =>
      _catalog.watchShelves(libraryId).map((r) => r?.json).switchMap((json) {
        final raw = _decodeList(json);
        final pairs = <(String, String)>[];
        final showIds = <String>[];
        for (final shelf in raw) {
          for (final e in AbsJson.maps(shelf['entities'])) {
            final id = AbsJson.str(e['id']);
            if (id == null) continue;
            final episodeId = AbsJson.str(AbsJson.map(e['recentEpisode'])['id']);
            if (shelf['type'] == 'episode' && episodeId != null) pairs.add((id, episodeId));
            if (shelf['type'] == 'podcast') showIds.add(id);
          }
        }
        return combineLatest2(_watchEpisodeList(pairs), _catalog.watchItemsByIds(showIds), (
          List<EpisodeSummary> episodes,
          List<ItemWithProgress> shows,
        ) {
          final episodeById = {for (final e in episodes) e.episodeId: e};
          final showById = {for (final s in shows) s.item.id: AbsJson.summary(source, s.item, null)};
          return [
            for (final shelf in raw)
              if (AbsJson.str(shelf['id']) case final id?)
                PodcastShelf(
                  id: id,
                  serverLabel: AbsJson.str(shelf['label']) ?? id,
                  episodes: shelf['type'] == 'episode'
                      ? [
                          for (final e in AbsJson.maps(shelf['entities']))
                            ?episodeById[AbsJson.str(AbsJson.map(e['recentEpisode'])['id'])],
                        ]
                      : const [],
                  shows: shelf['type'] == 'podcast'
                      ? [
                          for (final e in AbsJson.maps(shelf['entities'])) ?showById[AbsJson.str(e['id'])],
                        ]
                      : const [],
                ),
          ].where((s) => !s.isEmpty).toList();
        });
      });

  static List<Map<String, Object?>> _decodeList(String? json) {
    if (json == null) return const [];
    try {
      return AbsJson.maps(jsonDecode(json));
    } on FormatException {
      return const [];
    }
  }

  // --- This phone's per-show settings ---

  Stream<ShowPrefs> watchPrefs(String itemId) => _dao.watchPrefs(itemId).map(PodcastJson.prefs);

  Future<ShowPrefs> prefs(String itemId) async => PodcastJson.prefs(await _dao.prefsOf(itemId));

  Future<void> savePrefs(String itemId, ShowPrefs prefs) => _dao.putPrefs(PodcastJson.prefsRow(itemId, prefs));

  /// Shows with automatic downloads or notifications on.
  Future<Map<String, ShowPrefs>> automatedShows() async => {
    for (final r in await _dao.allPrefs())
      if (r.autoDownload || r.notifyNew) r.itemId: PodcastJson.prefs(r),
  };

  // --- Socket ---

  /// A podcast changed on the server: the socket sends the whole expanded
  /// show, episodes included; without them the show is fetched again.
  Future<void> apply(AbsSocketEvent event) async {
    if (event is! ItemsChanged) return;
    for (final item in event.items) {
      if (item['mediaType'] != 'podcast') continue;
      final id = AbsJson.str(item['id']);
      if (id == null) continue;
      if (AbsJson.map(item['media'])['episodes'] is List) {
        await _writeShow(item);
      } else {
        await refreshShow(id, force: true);
      }
    }
  }

  // --- Admin actions (docs/abs-api.md section 13) ---

  /// The server's podcast search (iTunes). Any user may search.
  Future<List<PodcastSearchResult>> searchPodcasts(String term, {String country = 'us'}) async {
    final json = await client.get<Object?>('/api/search/podcast', query: {'term': term, 'country': country});
    return [for (final r in AbsJson.maps(json)) ?PodcastSearchResult.fromJson(r)];
  }

  /// Reads a feed through the server (admin).
  Future<FeedPreview> previewFeed(String feedUrl) async {
    final json = await client.post<Map<String, Object?>>('/api/podcasts/feed', body: {'rssFeed': feedUrl});
    return FeedPreview.fromJson(json, feedUrl: feedUrl);
  }

  /// The folders of a library, where a new show can go.
  Future<List<LibraryFolder>> libraryFolders(String libraryId) async {
    final json = await client.get<Map<String, Object?>>('/api/libraries');
    for (final l in AbsJson.maps(json['libraries'])) {
      if (l['id'] != libraryId) continue;
      return [
        for (final f in AbsJson.maps(l['folders']))
          if (AbsJson.str(f['id']) != null && AbsJson.str(f['fullPath']) != null)
            LibraryFolder(id: f['id'] as String, fullPath: f['fullPath'] as String),
      ];
    }
    return const [];
  }

  /// The library's podcast search region (`settings.podcastSearchRegion`).
  Future<String> searchRegion(String libraryId) async {
    try {
      final json = await client.get<Map<String, Object?>>('/api/libraries');
      for (final l in AbsJson.maps(json['libraries'])) {
        if (l['id'] == libraryId) return AbsJson.str(AbsJson.map(l['settings'])['podcastSearchRegion']) ?? 'us';
      }
    } on AbsFailure {
      // The default region is fine for a search.
    }
    return 'us';
  }

  /// A folder name the server accepts for [title].
  static String folderName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|%\x00-\x1f]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final noDots = cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
    return noDots.isEmpty ? 'Podcast' : noDots;
  }

  /// Adds the show to the library (admin). Returns its item id.
  Future<String?> addPodcast({
    required String libraryId,
    required LibraryFolder folder,
    required FeedPreview feed,
    bool serverAutoDownload = false,
  }) async {
    final base = folder.fullPath.endsWith('/')
        ? folder.fullPath.substring(0, folder.fullPath.length - 1)
        : folder.fullPath;
    final json = await client.post<Map<String, Object?>>(
      '/api/podcasts',
      body: {
        'libraryId': libraryId,
        'folderId': folder.id,
        'path': '$base/${folderName(feed.title)}',
        'media': {'metadata': feed.metadata, 'autoDownloadEpisodes': serverAutoDownload},
      },
    );
    final id = AbsJson.str(json['id']);
    if (id != null && json['mediaType'] == 'podcast') await _writeShow(json);
    return id;
  }

  /// Asks the server to look for new episodes in the feed and download up
  /// to [limit] of them (admin). Returns the episodes it found.
  Future<List<Map<String, Object?>>> checkNewEpisodes(String itemId, {int limit = 3}) async {
    final json = await client.get<Map<String, Object?>>('/api/podcasts/$itemId/checknew', query: {'limit': limit});
    return AbsJson.maps(json['episodes']);
  }

  /// Feed episodes the server does not have yet, newest first. Matched by
  /// title, the only feed field the cache keeps.
  Future<List<Map<String, Object?>>> feedEpisodesNotOnServer(String itemId, String feedUrl) async {
    final feed = await previewFeed(feedUrl);
    final have = {for (final e in await _dao.episodesOf(itemId)) e.episode.title.trim().toLowerCase()};
    return [
      for (final e in feed.episodes)
        if (!have.contains((AbsJson.str(e['title']) ?? '').trim().toLowerCase())) e,
    ];
  }

  /// Queues feed episodes for download on the server (admin).
  Future<void> downloadToServer(String itemId, List<Map<String, Object?>> episodes) =>
      client.post<Object?>('/api/podcasts/$itemId/download-episodes', body: episodes);

  /// Changes the feed address and the server's own download schedule
  /// (`permissions.update`).
  Future<void> editFeed(String itemId, {required String feedUrl, required bool autoDownload, String? schedule}) async {
    final json = await client.patch<Map<String, Object?>>(
      '/api/items/$itemId/media',
      body: {
        'metadata': {'feedUrl': feedUrl},
        'autoDownloadEpisodes': autoDownload,
        'autoDownloadSchedule': ?schedule,
      },
    );
    final item = AbsJson.map(json['libraryItem']);
    if (item.isNotEmpty) await _writeShow(item);
  }
}

/// The server's own words from a failure ("Podcast already exists"), or
/// null when it sent none.
String? serverMessage(Object error) {
  if (error is! AbsHttpError && error is! AbsForbidden) return null;
  final details = (error as AbsFailure).details;
  final text = details.replaceFirst(RegExp(r'^HTTP \d+\s*'), '').trim();
  if (text.isEmpty || text.startsWith('{') || text.startsWith('<')) return null;
  return text;
}
