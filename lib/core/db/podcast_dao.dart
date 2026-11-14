// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'account_db.dart';
import 'tables/library_cache.dart';
import 'tables/podcast_tables.dart';

part 'podcast_dao.g.dart';

/// An episode with the user's progress on it (null when never started).
typedef EpisodeWithProgress = ({EpisodeRow episode, ProgressRow? progress});

/// A show in a podcast library with its episode counts.
typedef ShowRow = ({ItemRow item, int episodeCount, int unplayed, int? latestEpisodeAt});

/// An episode in progress: the show, the progress, and the episode when it
/// is cached.
typedef EpisodeInProgress = ({ItemRow show, ProgressRow progress, EpisodeRow? episode});

/// What [PodcastDao.replaceEpisodes] found: the episodes that were not
/// cached before, and whether the show had any cached episodes at all.
typedef EpisodeDiff = ({List<String> added, bool hadAny});

/// Reads and writes podcast episodes and this phone's per-show settings.
@DriftAccessor(tables: [Items, Progress, Episodes, PodcastPrefs])
class PodcastDao extends DatabaseAccessor<AccountDb> with _$PodcastDaoMixin {
  PodcastDao(super.db);

  // --- Episodes ---

  /// Replaces the episodes of [itemId] with the server's complete list.
  Future<EpisodeDiff> replaceEpisodes(String itemId, List<EpisodesCompanion> rows) {
    return transaction(() async {
      final before =
          await (selectOnly(episodes)
                ..addColumns([episodes.id])
                ..where(episodes.itemId.equals(itemId)))
              .map((r) => r.read(episodes.id)!)
              .get();
      final known = before.toSet();
      final keep = {for (final r in rows) r.id.value};
      await (delete(episodes)..where((t) => t.itemId.equals(itemId) & t.id.isNotIn(keep))).go();
      await batch((b) => b.insertAllOnConflictUpdate(episodes, rows));
      return (
        added: [
          for (final r in rows)
            if (!known.contains(r.id.value)) r.id.value,
        ],
        hadAny: known.isNotEmpty,
      );
    });
  }

  /// Adds or updates single episodes (from shelves and recent episodes)
  /// without touching the others. Returns the ids that were new.
  Future<List<String>> mergeEpisodes(List<EpisodesCompanion> rows) {
    if (rows.isEmpty) return Future.value(const []);
    return transaction(() async {
      final ids = [for (final r in rows) r.id.value];
      final known =
          (await (selectOnly(episodes)
                    ..addColumns([episodes.id])
                    ..where(episodes.id.isIn(ids)))
                  .map((r) => r.read(episodes.id)!)
                  .get())
              .toSet();
      await batch((b) => b.insertAllOnConflictUpdate(episodes, rows));
      return [
        for (final id in ids)
          if (!known.contains(id)) id,
      ];
    });
  }

  JoinedSelectStatement<HasResultSet, dynamic> _withProgress() => select(episodes).join([
    leftOuterJoin(progress, progress.itemId.equalsExp(episodes.itemId) & progress.episodeId.equalsExp(episodes.id)),
  ]);

  EpisodeWithProgress _read(TypedResult r) => (episode: r.readTable(episodes), progress: r.readTableOrNull(progress));

  /// The episodes of a show, newest first.
  Stream<List<EpisodeWithProgress>> watchEpisodes(String itemId) {
    final statement = _withProgress()
      ..where(episodes.itemId.equals(itemId))
      ..orderBy([OrderingTerm.desc(episodes.sortDate), OrderingTerm.asc(episodes.id)]);
    return statement.watch().map((rows) => [for (final r in rows) _read(r)]);
  }

  Future<List<EpisodeWithProgress>> episodesOf(String itemId) {
    final statement = _withProgress()
      ..where(episodes.itemId.equals(itemId))
      ..orderBy([OrderingTerm.desc(episodes.sortDate), OrderingTerm.asc(episodes.id)]);
    return statement.get().then((rows) => [for (final r in rows) _read(r)]);
  }

  Stream<EpisodeWithProgress?> watchEpisode(String episodeId) {
    final statement = _withProgress()..where(episodes.id.equals(episodeId));
    return statement.watchSingleOrNull().map((r) => r == null ? null : _read(r));
  }

  Future<EpisodeRow?> episode(String episodeId) =>
      (select(episodes)..where((t) => t.id.equals(episodeId))).getSingleOrNull();

  /// Episodes in the order of [ids]; ids that are not cached are left out.
  Stream<List<EpisodeWithProgress>> watchEpisodesByIds(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const []);
    final statement = _withProgress()..where(episodes.id.isIn(ids));
    return statement.watch().map((rows) {
      final byId = {for (final r in rows) r.readTable(episodes).id: _read(r)};
      return [
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ];
    });
  }

  Future<int> countEpisodes(String itemId) async {
    final count = episodes.id.count();
    final query = selectOnly(episodes)
      ..addColumns([count])
      ..where(episodes.itemId.equals(itemId));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Episodes whose title matches [pattern] (a LIKE pattern over lower
  /// case text), newest first, for offline search.
  Future<List<EpisodeRow>> searchEpisodes(String pattern, {int limit = 20}) =>
      (select(episodes)
            ..where((t) => t.title.lower().like(pattern, escapeChar: r'\'))
            ..orderBy([(t) => OrderingTerm.desc(t.sortDate)])
            ..limit(limit))
          .get();

  Future<void> deleteEpisodesOf(String itemId) => (delete(episodes)..where((t) => t.itemId.equals(itemId))).go();

  // --- Shows ---

  /// The shows of a podcast library with how many episodes the user has
  /// not finished. With episodes cached that is counted episode by episode
  /// (what the server calls numEpisodesIncomplete); before that it is the
  /// server's episode count minus the finished ones.
  Stream<List<ShowRow>> watchShows(String libraryId) {
    final query = customSelect(
      'SELECT i.*, '
      '(SELECT COUNT(*) FROM episodes e WHERE e.item_id = i.id) AS ep_count, '
      '(SELECT COUNT(*) FROM episodes e LEFT JOIN progress p ON p.item_id = e.item_id AND p.episode_id = e.id '
      'WHERE e.item_id = i.id AND COALESCE(p.is_finished, 0) = 0) AS ep_unplayed, '
      "(SELECT COUNT(*) FROM progress p WHERE p.item_id = i.id AND p.episode_id <> '' AND p.is_finished = 1) "
      'AS ep_finished, '
      '(SELECT MAX(e.sort_date) FROM episodes e WHERE e.item_id = i.id) AS ep_latest '
      "FROM items i WHERE i.library_id = ? AND i.media_type = 'podcast'",
      variables: [Variable.withString(libraryId)],
      readsFrom: {items, episodes, progress},
    );
    return query.watch().map((rows) => [for (final r in rows) _show(r)]);
  }

  ShowRow _show(QueryRow r) {
    final item = items.map(r.data);
    final count = r.read<int>('ep_count');
    final unplayed = count > 0 ? r.read<int>('ep_unplayed') : (item.numEpisodes - r.read<int>('ep_finished'));
    return (
      item: item,
      episodeCount: count > 0 ? count : item.numEpisodes,
      unplayed: unplayed < 0 ? 0 : unplayed,
      latestEpisodeAt: r.readNullable<int>('ep_latest'),
    );
  }

  /// One show with its counts, live.
  Stream<ShowRow?> watchShow(String itemId) {
    final query = customSelect(
      'SELECT i.*, '
      '(SELECT COUNT(*) FROM episodes e WHERE e.item_id = i.id) AS ep_count, '
      '(SELECT COUNT(*) FROM episodes e LEFT JOIN progress p ON p.item_id = e.item_id AND p.episode_id = e.id '
      'WHERE e.item_id = i.id AND COALESCE(p.is_finished, 0) = 0) AS ep_unplayed, '
      "(SELECT COUNT(*) FROM progress p WHERE p.item_id = i.id AND p.episode_id <> '' AND p.is_finished = 1) "
      'AS ep_finished, '
      '(SELECT MAX(e.sort_date) FROM episodes e WHERE e.item_id = i.id) AS ep_latest '
      'FROM items i WHERE i.id = ?',
      variables: [Variable.withString(itemId)],
      readsFrom: {items, episodes, progress},
    );
    return query.watchSingleOrNull().map((r) => r == null ? null : _show(r));
  }

  /// Started, unfinished episodes of a library's shows the user did not
  /// hide, most recent first.
  Stream<List<EpisodeInProgress>> watchEpisodesInProgress({String? libraryId, int limit = 20}) {
    final statement =
        select(progress).join([
            innerJoin(items, items.id.equalsExp(progress.itemId)),
            leftOuterJoin(episodes, episodes.id.equalsExp(progress.episodeId)),
          ])
          ..where(
            progress.episodeId.equals('').not() &
                progress.isFinished.equals(false) &
                progress.hideFromContinueListening.equals(false) &
                progress.currentTime.isBiggerThanValue(0),
          )
          ..orderBy([OrderingTerm.desc(progress.lastUpdate)])
          ..limit(limit);
    if (libraryId != null) statement.where(items.libraryId.equals(libraryId));
    return statement.watch().map(
      (rows) => [
        for (final r in rows)
          (show: r.readTable(items), progress: r.readTable(progress), episode: r.readTableOrNull(episodes)),
      ],
    );
  }

  // --- Per-show settings ---

  Stream<PodcastPrefsRow?> watchPrefs(String itemId) =>
      (select(podcastPrefs)..where((t) => t.itemId.equals(itemId))).watchSingleOrNull();

  Future<PodcastPrefsRow?> prefsOf(String itemId) =>
      (select(podcastPrefs)..where((t) => t.itemId.equals(itemId))).getSingleOrNull();

  Future<List<PodcastPrefsRow>> allPrefs() => select(podcastPrefs).get();

  Future<void> putPrefs(PodcastPrefsCompanion row) => into(podcastPrefs).insertOnConflictUpdate(row);
}
