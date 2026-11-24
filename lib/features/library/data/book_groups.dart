// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/browse_models.dart';

// Authors and series the user keeps together as one card in Audiobooks
// ("Show as one card in Audiobooks" on their screens). Kept on this phone,
// in the global settings: Audiobookshelf has nothing like it.

/// The settings key of the grouped authors and series.
const bookGroupsSettingKey = 'library.groups';

/// Every grouped author and series, of every account, newest first.
final bookGroupsProvider = StreamProvider<List<BookGroup>>(
  (ref) => ref.watch(globalDbProvider).watchSetting(bookGroupsSettingKey).map(decodeBookGroups),
);

/// Whether [group]'s books show as one card.
final isGroupedProvider = Provider.family<bool, BookGroup>(
  (ref, group) => ref.watch(bookGroupsProvider.select((v) => v.value?.contains(group) ?? false)),
);

/// Shows [group]'s books as one card in Audiobooks, or one by one again.
Future<void> setGrouped(GlobalDb db, BookGroup group, {required bool grouped}) async {
  final groups = decodeBookGroups(await db.readSetting(bookGroupsSettingKey));
  groups.remove(group);
  if (grouped) groups.insert(0, group);
  await db.writeSetting(bookGroupsSettingKey, jsonEncode([for (final g in groups) g.toJson()]));
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
