// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/models.dart';
import '../../player/player_controller.dart';
import 'library_providers.dart';

// Books the user took out of Continue listening (hold a book there).
// Server books use the server's own flag (see
// AbsLibraryRepository.setHiddenFromContinueListening). Books on this phone
// have no such flag, so they are kept here, in the global settings.

/// The settings key of the books on this phone taken out of Continue
/// listening: a JSON map of book id to when, in milliseconds.
const hiddenLocalBooksSettingKey = 'continue.hiddenLocal';

/// Books on this phone taken out of Continue listening, with when.
final hiddenLocalBooksProvider = StreamProvider<Map<String, DateTime>>(
  (ref) => ref.watch(globalDbProvider).watchSetting(hiddenLocalBooksSettingKey).map(decodeHiddenLocalBooks),
);

/// Whether [book], a book on this phone, stays out of Continue listening:
/// it was taken out and has not been played since.
bool isHiddenLocally(BookSummary book, Map<String, DateTime> hidden) {
  final at = hidden[book.ref.itemId];
  if (at == null) return false;
  final played = book.progress?.updatedAt;
  return played == null || !played.isAfter(at);
}

/// Takes a book on this phone out of Continue listening (as of [at]), or
/// puts it back.
Future<void> setHiddenLocally(GlobalDb db, String bookId, {required bool hidden, DateTime? at}) async {
  final map = decodeHiddenLocalBooks(await db.readSetting(hiddenLocalBooksSettingKey));
  if (hidden) {
    map[bookId] = at ?? DateTime.now();
  } else {
    map.remove(bookId);
  }
  await db.writeSetting(
    hiddenLocalBooksSettingKey,
    jsonEncode({for (final MapEntry(:key, :value) in map.entries) key: value.millisecondsSinceEpoch}),
  );
}

Map<String, DateTime> decodeHiddenLocalBooks(String? json) {
  if (json == null) return {};
  try {
    final map = jsonDecode(json);
    return {
      if (map is Map)
        for (final MapEntry(:key, :value) in map.entries)
          if (key is String && value is int) key: DateTime.fromMillisecondsSinceEpoch(value),
    };
  } on FormatException {
    return {};
  }
}

/// Playing a server book the user took out of Continue listening puts it
/// back, like a book on this phone comes back once played. Kept alive by
/// the player side effects.
final continueListeningRevealProvider = Provider<void>((ref) {
  ref.listen(playerProvider.select((s) => s.playing ? s.now?.ref : null), (_, item) {
    if (item == null || item.episodeId != null) return;
    final repository = ref.read(absLibraryRepositoryProvider);
    if (repository == null || repository.source != item.source) return;
    unawaited(repository.setHiddenFromContinueListening(item.itemId, hidden: false).catchError((Object _) {}));
  });
});
