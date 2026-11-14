// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../../core/db/account_db.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../library/data/abs_json.dart';
import 'podcast_models.dart';

/// Turns Audiobookshelf podcast JSON (docs/abs-api.md sections 7, 8 and 13)
/// into cache rows and view models. Lenient like [AbsJson].
abstract final class PodcastJson {
  /// An episode object from the expanded show, recent episodes, a shelf's
  /// `recentEpisode` or `/api/podcasts/:id/episode/:episodeId`.
  static EpisodesCompanion? episode(Map<String, Object?> json, {String? itemId}) {
    final id = AbsJson.str(json['id']);
    final item = AbsJson.str(json['libraryItemId']) ?? itemId;
    if (id == null || item == null) return null;
    final file = AbsJson.map(json['audioFile']);
    final track = AbsJson.map(json['audioTrack']);
    final published = json['publishedAt'] is num ? AbsJson.integer(json['publishedAt']) : null;
    final added = AbsJson.integer(json['addedAt']);
    final duration = AbsJson.number(json['duration'] ?? track['duration'] ?? file['duration']);
    final size = AbsJson.integer(json['size'] ?? AbsJson.map(file['metadata'])['size']);
    return EpisodesCompanion.insert(
      id: id,
      itemId: item,
      title: AbsJson.str(json['title']) ?? '',
      subtitle: Value(AbsJson.str(json['subtitle'])),
      descriptionHtml: Value(AbsJson.str(json['description'])),
      publishedAt: Value(published == 0 ? null : published),
      addedAt: Value(added),
      sortDate: Value(published != null && published > 0 ? published : added),
      durationSec: Value(duration),
      season: Value(_text(json['season'])),
      episodeNumber: Value(_text(json['episode'])),
      episodeType: Value(AbsJson.str(json['episodeType'])),
      audioMime: Value(AbsJson.str(file['mimeType']) ?? AbsJson.str(track['mimeType'])),
      sizeBytes: Value(size),
      chaptersJson: Value(
        jsonEncode([
          for (final c in AbsJson.maps(json['chapters']))
            {'start': AbsJson.number(c['start']), 'end': AbsJson.number(c['end']), 'title': AbsJson.str(c['title'])},
        ]),
      ),
      updatedAt: Value(AbsJson.integer(json['updatedAt'])),
    );
  }

  /// Season and episode numbers arrive as strings, numbers or null.
  static String? _text(Object? v) {
    if (v is num) return '$v';
    final s = AbsJson.str(v)?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  /// The episodes of an expanded show.
  static List<EpisodesCompanion> episodesOf(Map<String, Object?> item) {
    final itemId = AbsJson.str(item['id']);
    return [
      for (final e in AbsJson.maps(AbsJson.map(item['media'])['episodes'])) ?episode(e, itemId: itemId),
    ];
  }

  static EpisodeSummary summary(
    SourceId source,
    EpisodeRow row, {
    required String showTitle,
    String? showAuthor,
    String? coverKey,
    ProgressRow? progress,
  }) {
    return EpisodeSummary(
      ref: ItemRef(source, row.itemId, episodeId: row.id),
      title: row.title,
      showTitle: showTitle,
      showAuthor: showAuthor,
      subtitle: row.subtitle,
      descriptionHtml: row.descriptionHtml,
      publishedAt: row.publishedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(row.publishedAt!),
      sortDate: DateTime.fromMillisecondsSinceEpoch(row.sortDate),
      duration: Duration(milliseconds: (row.durationSec * 1000).round()),
      season: row.season,
      episodeNumber: row.episodeNumber,
      episodeType: row.episodeType,
      sizeBytes: row.sizeBytes,
      coverKey: coverKey,
      progress: progress == null ? null : AbsJson.listening(progress, fallbackDuration: row.durationSec),
      chapters: chapters(row.chaptersJson),
    );
  }

  static List<Chapter> chapters(String json) {
    try {
      return [
        for (final (i, c) in AbsJson.maps(jsonDecode(json)).indexed)
          Chapter(
            index: i,
            title: AbsJson.str(c['title']) ?? '',
            start: Duration(milliseconds: (AbsJson.number(c['start']) * 1000).round()),
            end: Duration(milliseconds: (AbsJson.number(c['end']) * 1000).round()),
          ),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// The show header from the cached expanded item (episodes left out).
  static ShowDetail detail(ShowSummary summary, Map<String, Object?> json) {
    final media = AbsJson.map(json['media']);
    final meta = AbsJson.map(media['metadata']);
    return ShowDetail(
      summary: summary,
      author: AbsJson.str(meta['author']),
      descriptionHtml: AbsJson.str(meta['description']),
      genres: AbsJson.strings(meta['genres']),
      language: AbsJson.str(meta['language']),
      feedUrl: AbsJson.str(meta['feedUrl']),
      isSerial: meta['type'] == 'serial',
      serverAutoDownload: AbsJson.boolean(media['autoDownloadEpisodes']),
      serverAutoDownloadSchedule: AbsJson.str(media['autoDownloadSchedule']),
      libraryId: AbsJson.str(json['libraryId']),
    );
  }

  static ShowPrefs prefs(PodcastPrefsRow? row) => row == null
      ? const ShowPrefs()
      : ShowPrefs(
          autoDownload: row.autoDownload,
          keepLatest: row.keepLatest,
          deletePlayed: row.deletePlayed,
          notifyNew: row.notifyNew,
          speed: row.speed,
        );

  static PodcastPrefsCompanion prefsRow(String itemId, ShowPrefs p) => PodcastPrefsCompanion.insert(
    itemId: itemId,
    autoDownload: Value(p.autoDownload),
    keepLatest: Value(p.keepLatest),
    deletePlayed: Value(p.deletePlayed),
    notifyNew: Value(p.notifyNew),
    speed: Value(p.speed),
  );
}

/// A podcast found by the server's podcast search (iTunes), for adding.
final class PodcastSearchResult {
  const PodcastSearchResult({
    required this.title,
    required this.feedUrl,
    this.author,
    this.description,
    this.coverUrl,
    this.episodeCount = 0,
    this.genres = const [],
    this.explicit = false,
    this.raw = const {},
  });

  final String title;
  final String feedUrl;
  final String? author;
  final String? description;
  final Uri? coverUrl;
  final int episodeCount;
  final List<String> genres;
  final bool explicit;
  final Map<String, Object?> raw;

  static PodcastSearchResult? fromJson(Map<String, Object?> json) {
    final feed = AbsJson.str(json['feedUrl']);
    final title = AbsJson.str(json['title']);
    if (feed == null || title == null) return null;
    final cover = Uri.tryParse(AbsJson.str(json['cover']) ?? '');
    return PodcastSearchResult(
      title: title,
      feedUrl: feed,
      author: AbsJson.str(json['artistName']),
      description: AbsJson.str(json['descriptionPlain']) ?? AbsJson.str(json['description']),
      coverUrl: cover != null && (cover.scheme == 'https' || cover.scheme == 'http') ? cover : null,
      episodeCount: AbsJson.integer(json['trackCount']),
      genres: AbsJson.strings(json['genres']),
      explicit: AbsJson.boolean(json['explicit']),
      raw: json,
    );
  }
}

/// A feed as the server read it (`POST /api/podcasts/feed`): the show's
/// metadata and the episodes in the feed.
final class FeedPreview {
  const FeedPreview({required this.feedUrl, required this.title, required this.metadata, this.episodes = const []});

  final String feedUrl;
  final String title;

  /// The metadata to send back when adding the podcast.
  final Map<String, Object?> metadata;

  /// Feed episodes, as the server sends them (to download to the server).
  final List<Map<String, Object?>> episodes;

  String? get author => AbsJson.str(metadata['author']);
  String? get description => AbsJson.str(metadata['description']);

  static FeedPreview fromJson(Map<String, Object?> json, {required String feedUrl}) {
    final podcast = AbsJson.map(json['podcast']);
    final meta = {...AbsJson.map(podcast['metadata'])};
    meta['feedUrl'] ??= feedUrl;
    return FeedPreview(
      feedUrl: AbsJson.str(meta['feedUrl']) ?? feedUrl,
      title: AbsJson.str(meta['title']) ?? '',
      metadata: meta,
      episodes: AbsJson.maps(podcast['episodes']),
    );
  }
}

/// A folder of a podcast library on the server, for adding a show.
final class LibraryFolder {
  const LibraryFolder({required this.id, required this.fullPath});
  final String id;
  final String fullPath;
}

/// What the current user may do on the server (docs/abs-api.md section 6).
final class UserAccess {
  const UserAccess({required this.type, this.canUpdate = false, this.canDelete = false, this.canDownload = true});

  static const unknown = UserAccess(type: 'user');

  /// root, admin, user or guest.
  final String type;
  final bool canUpdate;
  final bool canDelete;
  final bool canDownload;

  /// Podcast admin actions (add, check new, download to the server) are
  /// gated on the user type, not a permission flag.
  bool get isAdmin => type == 'admin' || type == 'root';

  Map<String, Object?> toJson() => {
    'type': type,
    'permissions': {'update': canUpdate, 'delete': canDelete, 'download': canDownload},
  };

  static UserAccess fromUser(Map<String, Object?> user, {String fallbackType = 'user'}) {
    final permissions = AbsJson.map(user['permissions']);
    return UserAccess(
      type: AbsJson.str(user['type']) ?? fallbackType,
      canUpdate: AbsJson.boolean(permissions['update']),
      canDelete: AbsJson.boolean(permissions['delete']),
      canDownload: permissions['download'] != false,
    );
  }
}
