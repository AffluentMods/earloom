// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';

// Authors and series the user keeps together as one card, in Audiobooks or
// in Podcasts ("Where its books show" on their screens). Kept on this
// phone, in the global settings: Audiobookshelf has nothing like it.

/// The settings key of the grouped authors and series.
const bookGroupsSettingKey = 'library.groups';

/// Every grouped author and series, of every account, newest first.
final bookGroupsProvider = StreamProvider<List<BookGroup>>(
  (ref) => ref.watch(globalDbProvider).watchSetting(bookGroupsSettingKey).map(decodeBookGroups),
);

/// Where [group]'s one card shows, or null when its books show one by one.
final groupPlaceProvider = Provider.family<BookGroupPlace?, BookGroup>((ref, group) {
  final saved = ref.watch(bookGroupsProvider.select((v) => v.value ?? const <BookGroup>[]));
  for (final g in saved) {
    if (g == group) return g.place;
  }
  return null;
});

/// Shows [group]'s books as one card in [place], or one by one again in
/// Audiobooks when [place] is null.
Future<void> setGroupPlace(GlobalDb db, BookGroup group, BookGroupPlace? place) async {
  final groups = decodeBookGroups(await db.readSetting(bookGroupsSettingKey));
  groups.remove(group);
  if (place != null) groups.insert(0, group.copyWith(place: place));
  await db.writeSetting(bookGroupsSettingKey, jsonEncode([for (final g in groups) g.toJson()]));
}

/// The groups of [source] that show in Podcasts, leaving out those of a
/// book library the account no longer has.
List<BookGroup> podcastGroupsOf(List<BookGroup> groups, SourceId source, List<LibraryInfo> bookLibraries) {
  final libraries = {for (final l in bookLibraries) l.id};
  return [
    for (final g in groups)
      if (g.place == BookGroupPlace.podcasts && g.source == source && libraries.contains(g.libraryId)) g,
  ];
}

List<BookGroup> decodeBookGroups(String? json) {
  if (json == null) return [];
  try {
    final list = jsonDecode(json);
    return [
      if (list is List)
        for (final item in list) ?BookGroup.fromJson(item),
    ];
  } on FormatException {
    return [];
  }
}
