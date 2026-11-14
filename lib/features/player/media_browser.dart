// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/models.dart';
import '../../core/library/source_id.dart';
import '../../core/net/abs_client.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../app/providers.dart';
import '../accounts/data/account_session.dart';
import '../downloads/data/abs_download_manager.dart' show DownloadStatus;
import '../local_library/data/local_library_repository.dart';
import '../local_library/data/providers.dart';
import 'player_controller.dart';

/// A book as the car shows it.
final class BrowseEntry {
  const BrowseEntry({required this.ref, required this.title, this.author, this.art, this.progress});
  final ItemRef ref;
  final String title;
  final String? author;
  final Uri? art;

  /// 0 to 1, when started.
  final double? progress;
}

/// Where the car's lists come from. Never waits long on a server: the car
/// shows what it has.
abstract interface class BrowseCatalog {
  Future<List<BrowseEntry>> continueListening();
  Future<List<BrowseEntry>> recentlyAdded();
  Future<List<BrowseEntry>> onThisDevice();

  /// Server books downloaded to this phone: playable with no network.
  Future<List<BrowseEntry>> downloaded();

  /// The newest podcast episodes of the current server, newest first.
  Future<List<BrowseEntry>> latestEpisodes();
  Future<List<BrowseEntry>> search(String query);
}

/// The browse tree for Android Auto and other media browsers
/// (docs/plan/07-phase6-system-integration.md 6.2).
class MediaBrowser {
  MediaBrowser(this._catalog, this._l10n);
  final BrowseCatalog _catalog;
  final AppLocalizations _l10n;

  static const continueId = 'continue',
      recentId = 'added',
      deviceId = 'device',
      downloadedId = 'downloaded',
      podcastsId = 'podcasts';
  static const _itemPrefix = 'item:';

  // Content style hints Android Auto reads from the root extras.
  static const _browsableHint = 'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const _playableHint = 'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const _grid = 2;
  static const _listStyle = 1;
  static const _singleItemHint = 'android.media.browse.CONTENT_STYLE_SINGLE_ITEM_HINT';
  static const _progressKey = 'android.media.extra.PLAYBACK_STATUS';
  static const _completion = 'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE';

  static Map<String, dynamic> get rootExtras => {_browsableHint: _grid, _playableHint: _grid};

  static String mediaIdOf(ItemRef ref) => '$_itemPrefix${ref.key}';

  static ItemRef? refOf(String mediaId) =>
      mediaId.startsWith(_itemPrefix) ? ItemRef.tryParseKey(mediaId.substring(_itemPrefix.length)) : null;

  Future<List<MediaItem>> children(String parentId) async {
    switch (parentId) {
      case AudioService.browsableRootId:
        return [
          _folder(continueId, _l10n.autoContinueListening),
          _folder(recentId, _l10n.autoRecentlyAdded),
          _folder(podcastsId, _l10n.autoPodcasts),
          _folder(downloadedId, _l10n.autoDownloaded),
          _folder(deviceId, _l10n.autoOnThisDevice),
        ];
      case AudioService.recentRootId:
      case continueId:
        return _items(await _safe(_catalog.continueListening));
      case recentId:
        return _items(await _safe(_catalog.recentlyAdded));
      case deviceId:
        return _items(await _safe(_catalog.onThisDevice));
      case downloadedId:
        return _items(await _safe(_catalog.downloaded));
      case podcastsId:
        return _items(await _safe(_catalog.latestEpisodes), list: true);
    }
    return const [];
  }

  Future<List<MediaItem>> search(String query) async => _items(await _safe(() => _catalog.search(query)));

  static Future<List<BrowseEntry>> _safe(Future<List<BrowseEntry>> Function() load) async {
    try {
      return await load().timeout(const Duration(seconds: 6));
    } on Object {
      return const [];
    }
  }

  MediaItem _folder(String id, String title) =>
      MediaItem(id: id, title: title, playable: false, extras: {_browsableHint: _grid, _playableHint: _grid});

  List<MediaItem> _items(List<BrowseEntry> entries, {bool list = false}) => [
    for (final e in entries)
      MediaItem(
        id: mediaIdOf(e.ref),
        title: e.title,
        artist: e.author,
        artUri: e.art,
        playable: true,
        extras: {
          // Episodes read better as a list than as a grid of one cover.
          if (list) _singleItemHint: _listStyle,
          if (e.progress != null) ...{
            // 1 = partly played, 2 = fully played.
            _progressKey: e.progress! >= 0.999 ? 2 : 1,
            _completion: e.progress!.clamp(0.0, 1.0),
          },
        },
      ),
  ];
}

/// The catalog from what the app has now: books on this phone and the
/// current server account (in-progress and recently added).
class AppBrowseCatalog implements BrowseCatalog {
  AppBrowseCatalog(this._ref);
  final Ref _ref;

  LocalLibraryRepository get _local => _ref.read(localLibraryRepositoryProvider);

  BrowseEntry _localEntry(BookSummary b, LocalLibraryRepository repo) => BrowseEntry(
    ref: b.ref,
    title: b.title,
    author: b.authors.isEmpty ? null : b.authorLine,
    art: repo.coverFile(b.ref.itemId, b.coverKey)?.uri,
    progress: b.progress?.fraction,
  );

  Future<List<BrowseEntry>> _localBooks(LocalBookSort sort) async {
    final repo = _local;
    final books = await repo.watchBooks(sort: sort).first;
    return [for (final b in books) _localEntry(b, repo)];
  }

  AbsClient? get _client => _ref.read(accountSessionProvider)?.client;

  BrowseEntry _serverEntry(AbsClient client, String accountId, Map<String, Object?> item) {
    final media = (item['media'] as Map?)?.cast<String, Object?>() ?? const {};
    final meta = (media['metadata'] as Map?)?.cast<String, Object?>() ?? const {};
    final id = item['id']! as String;
    final episode = (item['recentEpisode'] as Map?)?['id'] as String?;
    return BrowseEntry(
      ref: ItemRef(AbsSource(accountId), id, episodeId: episode),
      title: (meta['title'] as String?) ?? '',
      author: (meta['authorName'] as String?) ?? (meta['author'] as String?),
      art: client.url('/api/items/$id/cover', {'width': 400, 'format': 'jpeg'}),
    );
  }

  String? _libraryId() {
    final account = _ref.read(accountSessionProvider)?.account;
    return account?.selectedLibraryId ?? account?.defaultLibraryId;
  }

  @override
  Future<List<BrowseEntry>> continueListening() async {
    final entries = <BrowseEntry>[];
    final seen = <ItemRef>{};
    void add(BrowseEntry e) {
      if (seen.add(e.ref)) entries.add(e);
    }

    final last = await _ref.read(playerStoreProvider).loadLast();
    if (last != null) {
      add(
        BrowseEntry(ref: last.ref, title: last.title, author: last.author, art: _artOf(last.coverPath, last.coverUrl)),
      );
    }
    final client = _client;
    final session = _ref.read(accountSessionProvider);
    if (client != null && session != null) {
      try {
        final json = await client.get<Map<String, Object?>>('/api/me/items-in-progress', query: {'limit': 20});
        for (final item in ((json['libraryItems'] as List?) ?? const []).cast<Map<String, Object?>>()) {
          add(_serverEntry(client, session.accountId, item));
        }
      } on Object {
        // Offline: this phone's books and the last book still show.
      }
    }
    for (final e in await _localBooks(LocalBookSort.recentlyPlayed)) {
      final p = e.progress;
      if (p != null && p > 0 && p < 0.999) add(e);
    }
    return entries.take(20).toList();
  }

  static Uri? _artOf(String? path, String? url) => path != null
      ? Uri.file(path)
      : (url == null ? null : Uri.parse(url).replace(queryParameters: {'width': '400', 'format': 'jpeg'}));

  @override
  Future<List<BrowseEntry>> recentlyAdded() async {
    final client = _client;
    final session = _ref.read(accountSessionProvider);
    final library = _libraryId();
    if (client == null || session == null || library == null) return _localBooks(LocalBookSort.recentlyAdded);
    final json = await client.get<Map<String, Object?>>(
      '/api/libraries/$library/items',
      query: {'sort': 'addedAt', 'desc': 1, 'limit': 20, 'minified': 1},
    );
    return [
      for (final item in ((json['results'] as List?) ?? const []).cast<Map<String, Object?>>())
        _serverEntry(client, session.accountId, item),
    ];
  }

  @override
  Future<List<BrowseEntry>> onThisDevice() => _localBooks(LocalBookSort.title);

  @override
  Future<List<BrowseEntry>> latestEpisodes() async {
    final client = _client;
    final session = _ref.read(accountSessionProvider);
    if (client == null || session == null) return const [];
    final libraries = await client.get<Map<String, Object?>>('/api/libraries');
    final podcastLibraries = [
      for (final l in ((libraries['libraries'] as List?) ?? const []).cast<Map<String, Object?>>())
        if (l['mediaType'] == 'podcast') l['id']! as String,
    ];
    final entries = <({BrowseEntry entry, num at})>[];
    for (final id in podcastLibraries) {
      final json = await client.get<Map<String, Object?>>('/api/libraries/$id/recent-episodes', query: {'limit': 20});
      for (final e in ((json['episodes'] as List?) ?? const []).cast<Map<String, Object?>>()) {
        final itemId = e['libraryItemId'];
        final episodeId = e['id'];
        if (itemId is! String || episodeId is! String) continue;
        final show = (((e['podcast'] as Map?)?['metadata'] as Map?)?['title'] as String?) ?? '';
        entries.add((
          entry: BrowseEntry(
            ref: ItemRef(AbsSource(session.accountId), itemId, episodeId: episodeId),
            title: (e['title'] as String?) ?? '',
            author: show,
            art: client.url('/api/items/$itemId/cover', {'width': 400, 'format': 'jpeg'}),
          ),
          at: (e['publishedAt'] as num?) ?? 0,
        ));
      }
    }
    entries.sort((a, b) => b.at.compareTo(a.at));
    return [for (final e in entries.take(30)) e.entry];
  }

  @override
  Future<List<BrowseEntry>> downloaded() async {
    final rows = await _ref.read(offlineDbProvider).allDownloads();
    return [
      for (final d in rows)
        if (d.status == DownloadStatus.complete)
          BrowseEntry(
            ref: ItemRef(AbsSource(d.accountId), d.itemId, episodeId: d.episodeId),
            title: d.title,
            author: d.author,
            art: d.coverPath == null ? null : Uri.file(d.coverPath!),
          ),
    ];
  }

  @override
  Future<List<BrowseEntry>> search(String query) async {
    final repo = _local;
    final local = [for (final b in await repo.watchBooks(query: query).first) _localEntry(b, repo)];
    final client = _client;
    final session = _ref.read(accountSessionProvider);
    final library = _libraryId();
    if (client == null || session == null || library == null || query.trim().isEmpty) return local;
    try {
      final json = await client.get<Map<String, Object?>>(
        '/api/libraries/$library/search',
        query: {'q': query, 'limit': 10},
      );
      final books = ((json['book'] as List?) ?? (json['podcast'] as List?) ?? const []).cast<Map<String, Object?>>();
      return [
        for (final hit in books)
          if (hit['libraryItem'] is Map)
            _serverEntry(client, session.accountId, (hit['libraryItem']! as Map).cast<String, Object?>()),
        ...local,
      ];
    } on Object {
      return local;
    }
  }
}

final browseCatalogProvider = Provider<BrowseCatalog>(AppBrowseCatalog.new);

final mediaBrowserProvider = Provider<MediaBrowser>(
  (ref) => MediaBrowser(ref.watch(browseCatalogProvider), deviceL10n()),
);
