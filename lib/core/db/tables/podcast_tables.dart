// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

// Podcasts in the cache of one Audiobookshelf account (AccountDb, Phase 5).
// Episodes are a copy of what the server said; podcast prefs are this
// phone's own settings per show and never go to the server.

/// The episodes of every podcast the app has seen: from the expanded show,
/// the recent episodes list and episode shelves.
@DataClassName('EpisodeRow')
@TableIndex(name: 'episodes_item_date', columns: {#itemId, #sortDate})
class Episodes extends Table {
  /// The server's episode id.
  TextColumn get id => text()();

  /// The podcast's library item id.
  TextColumn get itemId => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();

  /// Raw show notes. Always render through lib/core/util/html_sanitize.dart.
  TextColumn get descriptionHtml => text().nullable()();

  /// When the feed says the episode came out (epoch ms), if it says.
  IntColumn get publishedAt => integer().nullable()();

  /// When the server added the episode (epoch ms).
  IntColumn get addedAt => integer().withDefault(const Constant(0))();

  /// [publishedAt], else [addedAt]: what "newest" sorts by.
  IntColumn get sortDate => integer().withDefault(const Constant(0))();
  RealColumn get durationSec => real().withDefault(const Constant(0))();

  /// As the feed writes them ("2", "S1"), or null.
  TextColumn get season => text().nullable()();
  TextColumn get episodeNumber => text().nullable()();

  /// `full`, `trailer`, `bonus` or null.
  TextColumn get episodeType => text().nullable()();
  TextColumn get audioMime => text().nullable()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();

  /// The episode chapters, `[{start, end, title}]`.
  TextColumn get chaptersJson => text().withDefault(const Constant('[]'))();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// This phone's settings for one show (docs/plan/06-phase5-podcasts.md 5.4).
@DataClassName('PodcastPrefsRow')
class PodcastPrefs extends Table {
  TextColumn get itemId => text()();

  /// Download new episodes on this phone by themselves.
  BoolColumn get autoDownload => boolean().withDefault(const Constant(false))();

  /// How many automatically downloaded episodes to keep; 0 keeps all.
  IntColumn get keepLatest => integer().withDefault(const Constant(3))();

  /// Remove automatically downloaded episodes once they are played.
  BoolColumn get deletePlayed => boolean().withDefault(const Constant(true))();

  /// A notification when a new episode arrives.
  BoolColumn get notifyNew => boolean().withDefault(const Constant(false))();

  /// Playback speed for this show; null follows the podcast default.
  RealColumn get speed => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}
