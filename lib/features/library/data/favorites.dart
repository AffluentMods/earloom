// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/util/streams.dart';
import '../../local_library/data/local_library_repository.dart';
import '../../local_library/data/providers.dart';
import 'library_providers.dart';

// Favorites live on this phone only, as a list of item keys in the global
// settings, newest first. Audiobookshelf has no favorites of its own.

/// The settings key of the favorites list.
const favoritesSettingKey = 'library.favorites';

/// The keys (`ItemRef.key`) of the favorite books, newest first.
final favoriteKeysProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(globalDbProvider).watchSetting(favoritesSettingKey).map(decodeFavoriteKeys),
);

/// Whether [item] is a favorite.
final isFavoriteProvider = Provider.family<bool, ItemRef>(
  (ref, item) => ref.watch(favoriteKeysProvider.select((v) => v.value?.contains(item.key) ?? false)),
);

/// Adds [item] to the favorites (at the top) or removes it.
Future<void> setFavorite(GlobalDb db, ItemRef item, {required bool favorite}) async {
  final keys = decodeFavoriteKeys(await db.readSetting(favoritesSettingKey));
  keys.remove(item.key);
  if (favorite) keys.insert(0, item.key);
  await db.writeSetting(favoritesSettingKey, jsonEncode(keys));
}

List<String> decodeFavoriteKeys(String? json) {
  if (json == null) return [];
  try {
    final list = jsonDecode(json);
    return [
      if (list is List)
        for (final key in list)
          if (key is String) key,
    ];
  } on FormatException {
    return [];
  }
}

/// The favorite books that can be shown: those on this phone and those of
/// the current server account, newest favorite first. Books of an account
/// that is not current, and books no longer in any library, are left out.
final favoriteBooksProvider = StreamProvider.autoDispose<List<BookSummary>>((ref) {
  final keys = ref.watch(favoriteKeysProvider).value ?? const <String>[];
  final refs = [for (final k in keys) ?ItemRef.tryParseKey(k)];
  final repository = ref.watch(absLibraryRepositoryProvider);
  final serverIds = [
    for (final r in refs)
      if (repository != null && r.source == repository.source && r.episodeId == null) r.itemId,
  ];
  final localIds = {
    for (final r in refs)
      if (r.source is LocalSource) r.itemId,
  };
  final server = repository == null || serverIds.isEmpty
      ? Stream.value(const <BookSummary>[])
      : repository.watchBooksByIds(serverIds);
  final local = localIds.isEmpty
      ? Stream.value(const <BookSummary>[])
      : ref
            .watch(localLibraryRepositoryProvider)
            .watchBooks(sort: LocalBookSort.title)
            .map((books) => [...books.where((b) => localIds.contains(b.ref.itemId))]);
  return combineLatest2(server, local, (List<BookSummary> s, List<BookSummary> l) {
    final byKey = {
      for (final b in [...s, ...l]) b.ref.key: b,
    };
    return [for (final r in refs) ?byKey[r.key]];
  });
});
