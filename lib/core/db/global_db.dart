// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'db_location.dart';
import 'tables/app_settings.dart';

part 'global_db.g.dart';

/// The one database shared by every account: app settings now, the accounts
/// list from Phase 1.
@DriftDatabase(tables: [AppSettings])
class GlobalDb extends _$GlobalDb {
  GlobalDb(super.executor);

  /// Opens the on-device database file.
  GlobalDb.open() : super(openAppDatabase('global'));

  @override
  int get schemaVersion => 1;

  Future<String?> readSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeSetting(String key, String value) {
    return into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
  }

  Stream<String?> watchSetting(String key) {
    return (select(appSettings)..where((t) => t.key.equals(key))).watchSingleOrNull().map((row) => row?.value);
  }
}

/// Keys used in [AppSettings].
abstract final class SettingKeys {
  static const themeMode = 'theme_mode';
}
