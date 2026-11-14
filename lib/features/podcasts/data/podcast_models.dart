// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';

/// One podcast episode, as lists, shelves and the episode sheet show it.
final class EpisodeSummary {
  const EpisodeSummary({
    required this.ref,
    required this.title,
    required this.showTitle,
    required this.sortDate,
    this.showAuthor,
    this.subtitle,
    this.descriptionHtml,
    this.publishedAt,
    this.duration = Duration.zero,
    this.season,
    this.episodeNumber,
    this.episodeType,
    this.sizeBytes = 0,
    this.coverKey,
    this.progress,
    this.chapters = const [],
  });

  /// The podcast item plus this episode's id.
  final ItemRef ref;
  final String title;
  final String showTitle;
  final String? showAuthor;
  final String? subtitle;

  /// Raw show notes. Always render through the sanitizer.
  final String? descriptionHtml;
  final DateTime? publishedAt;

  /// [publishedAt], else when the server added the episode.
  final DateTime sortDate;
  final Duration duration;
  final String? season;
  final String? episodeNumber;

  /// `full`, `trailer`, `bonus` or null.
  final String? episodeType;
  final int sizeBytes;

  /// The show's cover key (episodes use the show's cover).
  final String? coverKey;
  final ListeningProgress? progress;
  final List<Chapter> chapters;

  String get episodeId => ref.episodeId!;

  /// The show itself, without the episode.
  ItemRef get showRef => ItemRef(ref.source, ref.itemId);

  bool get isPlayed => progress?.isFinished ?? false;
  bool get isInProgress => !isPlayed && (progress?.isStarted ?? false);

  /// The episode as a "book", for the shared cover, hero and queue widgets:
  /// the episode title, the show as the author line.
  BookSummary get asBook => BookSummary(
    ref: ref,
    title: title,
    authors: [showTitle],
    duration: duration,
    coverKey: coverKey,
    progress: progress,
    isPodcast: true,
  );
}

/// A show in a podcast library list.
final class ShowSummary {
  const ShowSummary({required this.show, this.episodeCount = 0, this.unplayed = 0, this.latestEpisodeAt});

  final BookSummary show;
  final int episodeCount;

  /// Episodes not finished, like the badge on the server's web app.
  final int unplayed;
  final DateTime? latestEpisodeAt;
}

/// Everything the show screen header shows.
final class ShowDetail {
  const ShowDetail({
    required this.summary,
    this.author,
    this.descriptionHtml,
    this.genres = const [],
    this.language,
    this.feedUrl,
    this.isSerial = false,
    this.serverAutoDownload = false,
    this.serverAutoDownloadSchedule,
    this.libraryId,
  });

  final ShowSummary summary;
  final String? author;
  final String? descriptionHtml;
  final List<String> genres;
  final String? language;
  final String? feedUrl;

  /// A serial show is meant to be heard in order, oldest first.
  final bool isSerial;

  /// The server downloads new episodes from the feed by itself.
  final bool serverAutoDownload;

  /// A cron expression, as the server keeps it.
  final String? serverAutoDownloadSchedule;
  final String? libraryId;

  BookSummary get show => summary.show;
}

/// This phone's settings for one show (docs/plan/06-phase5-podcasts.md 5.4).
final class ShowPrefs {
  const ShowPrefs({
    this.autoDownload = false,
    this.keepLatest = 3,
    this.deletePlayed = true,
    this.notifyNew = false,
    this.speed,
  });

  static const keepChoices = [1, 3, 5, 10, 0];

  final bool autoDownload;

  /// 0 keeps all.
  final int keepLatest;
  final bool deletePlayed;
  final bool notifyNew;

  /// Null follows the podcast default speed.
  final double? speed;

  ShowPrefs copyWith({
    bool? autoDownload,
    int? keepLatest,
    bool? deletePlayed,
    bool? notifyNew,
    double? speed,
    bool clearSpeed = false,
  }) => ShowPrefs(
    autoDownload: autoDownload ?? this.autoDownload,
    keepLatest: keepLatest ?? this.keepLatest,
    deletePlayed: deletePlayed ?? this.deletePlayed,
    notifyNew: notifyNew ?? this.notifyNew,
    speed: clearSpeed ? null : speed ?? this.speed,
  );
}

enum ShowSort { title, recentlyUpdated, addedAt }

enum EpisodeSort { newest, oldest }

enum EpisodeFilter { all, unplayed, inProgress, downloaded }

/// New episodes of a show, found by a refresh.
final class NewEpisodes {
  const NewEpisodes({required this.show, required this.episodes});

  final ItemRef show;
  final List<EpisodeSummary> episodes;
}

/// Sorts shows for the podcast library grid.
List<ShowSummary> sortShows(List<ShowSummary> shows, ShowSort sort) {
  final sorted = [...shows];
  int byTitle(ShowSummary a, ShowSummary b) => a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase());
  DateTime updated(ShowSummary s) => s.latestEpisodeAt ?? s.show.addedAt ?? DateTime(0);
  sorted.sort(
    (a, b) => switch (sort) {
      ShowSort.title => byTitle(a, b),
      ShowSort.recentlyUpdated => _then(updated(b).compareTo(updated(a)), byTitle(a, b)),
      ShowSort.addedAt => _then(
        (b.show.addedAt ?? DateTime(0)).compareTo(a.show.addedAt ?? DateTime(0)),
        byTitle(a, b),
      ),
    },
  );
  return sorted;
}

int _then(int first, int second) => first != 0 ? first : second;

/// Orders and filters a show's episodes. [downloaded] holds the episode
/// ids on this phone.
List<EpisodeSummary> arrangeEpisodes(
  List<EpisodeSummary> episodes, {
  EpisodeSort sort = EpisodeSort.newest,
  EpisodeFilter filter = EpisodeFilter.all,
  Set<String> downloaded = const {},
}) {
  final kept = episodes.where(
    (e) => switch (filter) {
      EpisodeFilter.all => true,
      EpisodeFilter.unplayed => !e.isPlayed,
      EpisodeFilter.inProgress => e.isInProgress,
      EpisodeFilter.downloaded => downloaded.contains(e.episodeId),
    },
  );
  final sorted = kept.toList()..sort(_oldestFirst);
  return sort == EpisodeSort.newest ? sorted.reversed.toList() : sorted;
}

int _oldestFirst(EpisodeSummary a, EpisodeSummary b) {
  final byDate = a.sortDate.compareTo(b.sortDate);
  if (byDate != 0) return byDate;
  final byNumber = (num.tryParse(a.episodeNumber ?? '') ?? 0).compareTo(num.tryParse(b.episodeNumber ?? '') ?? 0);
  return byNumber != 0 ? byNumber : a.episodeId.compareTo(b.episodeId);
}

/// Episodes grouped by season, in the order they come. Null when no
/// episode has a season, so the list stays flat.
List<(String season, List<EpisodeSummary> episodes)>? groupBySeason(List<EpisodeSummary> episodes) {
  if (!episodes.any((e) => e.season != null && e.season!.trim().isNotEmpty)) return null;
  final order = <String>[];
  final groups = <String, List<EpisodeSummary>>{};
  for (final e in episodes) {
    final key = e.season?.trim() ?? '';
    if (!groups.containsKey(key)) order.add(key);
    (groups[key] ??= []).add(e);
  }
  return [for (final k in order) (k, groups[k]!)];
}

/// What plays after [finishedId] when the queue is empty: the next
/// unplayed episode after it (oldest first), else the newest unplayed one
/// before it. Null when everything is played.
EpisodeSummary? nextUnplayedEpisode(List<EpisodeSummary> episodes, String finishedId) {
  final ordered = [...episodes]..sort(_oldestFirst);
  bool candidate(EpisodeSummary e) => e.episodeId != finishedId && !e.isPlayed;
  final at = ordered.indexWhere((e) => e.episodeId == finishedId);
  if (at < 0) return ordered.reversed.where(candidate).firstOrNull;
  return ordered.skip(at + 1).where(candidate).firstOrNull ??
      ordered.take(at).toList().reversed.where(candidate).firstOrNull;
}

/// The newest episodes downloaded automatically that "keep latest N" and
/// "delete played" remove. In-progress episodes are never removed.
List<String> episodesToPrune(
  List<EpisodeSummary> autoDownloaded, {
  required int keepLatest,
  required bool deletePlayed,
}) {
  final newestFirst = [...autoDownloaded]..sort((a, b) => _oldestFirst(b, a));
  final remove = <String>[];
  var kept = 0;
  for (final e in newestFirst) {
    if (e.isInProgress) continue;
    if (deletePlayed && e.isPlayed) {
      remove.add(e.episodeId);
      continue;
    }
    if (keepLatest > 0 && kept >= keepLatest) {
      remove.add(e.episodeId);
      continue;
    }
    kept++;
  }
  return remove;
}
