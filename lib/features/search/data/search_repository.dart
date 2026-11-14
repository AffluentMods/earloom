// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/net/abs_errors.dart';
import '../../local_library/data/local_library_repository.dart';
import '../../local_library/data/providers.dart';
import '../../library/data/library_providers.dart';
import '../../library/data/library_repository.dart';

/// Server search when the server answers, search over the cache when it
/// does not, and always the books on this phone.
class SearchRepository {
  SearchRepository({required this.local, required this.server, required this.db});

  final LocalLibraryRepository local;

  /// Null without a current server account.
  final AbsLibraryRepository? server;
  final GlobalDb db;

  /// Searches [libraryIds] of the server (merged) and the local library.
  /// [cancel] drops the server requests when a newer query starts.
  Future<SearchResults> search(String query, {required List<String> libraryIds, CancelToken? cancel}) async {
    final localBooks = await local.watchBooks(query: query).first;
    final repository = server;
    if (repository == null || libraryIds.isEmpty) return SearchResults(query: query, localBooks: localBooks);
    SearchResults merged;
    try {
      final parts = await Future.wait([for (final id in libraryIds) repository.search(id, query, cancel: cancel)]);
      merged = _merge(query, parts);
    } on AbsCancelled {
      rethrow;
    } on AbsFailure {
      // Offline, or the server failed: answer from the cache instead.
      merged = await repository.searchOffline(query, libraryId: libraryIds.length == 1 ? libraryIds.single : null);
    }
    return SearchResults(
      query: query,
      books: merged.books,
      podcasts: merged.podcasts,
      episodes: merged.episodes,
      series: merged.series,
      authors: merged.authors,
      narrators: merged.narrators,
      genres: merged.genres,
      tags: merged.tags,
      offline: merged.offline,
      localBooks: localBooks,
    );
  }

  static SearchResults _merge(String query, List<SearchResults> parts) {
    if (parts.length == 1) return parts.single;
    List<NamedCount> counts(Iterable<NamedCount> all) {
      final map = <String, int>{};
      for (final c in all) {
        map[c.name] = (map[c.name] ?? 0) + c.count;
      }
      return [for (final e in map.entries) NamedCount(e.key, e.value)];
    }

    return SearchResults(
      query: query,
      books: [for (final p in parts) ...p.books],
      podcasts: [for (final p in parts) ...p.podcasts],
      episodes: [for (final p in parts) ...p.episodes],
      series: [for (final p in parts) ...p.series],
      authors: [for (final p in parts) ...p.authors],
      narrators: counts(parts.expand((p) => p.narrators)),
      genres: counts(parts.expand((p) => p.genres)),
      tags: counts(parts.expand((p) => p.tags)),
    );
  }

  // --- Recent searches ---

  static const maxRecent = 8;

  Future<void> remember(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final current = decodeRecentSearches(await db.readSetting(LibrarySettingKeys.recentSearches));
    final next = [trimmed, ...current.where((q) => q.toLowerCase() != trimmed.toLowerCase())].take(maxRecent).toList();
    await db.writeSetting(LibrarySettingKeys.recentSearches, jsonEncode(next));
  }

  Future<void> clearRecent() => db.deleteSetting(LibrarySettingKeys.recentSearches);
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(
    local: ref.watch(localLibraryRepositoryProvider),
    server: ref.watch(absLibraryRepositoryProvider),
    db: ref.watch(globalDbProvider),
  ),
);
