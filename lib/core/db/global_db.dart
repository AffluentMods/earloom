// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

import 'db_location.dart';
import 'tables/accounts.dart';
import 'tables/app_settings.dart';
import 'tables/listening.dart';

part 'global_db.g.dart';

/// The one database shared by every account: app settings, the accounts
/// list and the listening log behind the stats.
@DriftDatabase(tables: [AppSettings, Accounts, ListeningBuckets, ListeningSessions, ListenedBooks])
class GlobalDb extends _$GlobalDb {
  GlobalDb(super.executor);

  /// Opens the on-device database file.
  GlobalDb.open() : super(openAppDatabase('global'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(accounts);
      if (from < 3) {
        await m.createTable(listeningBuckets);
        await m.createTable(listeningSessions);
        await m.createTable(listenedBooks);
      }
    },
  );

  Future<String?> readSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeSetting(String key, String value) {
    return into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
  }

  Future<void> deleteSetting(String key) => (delete(appSettings)..where((t) => t.key.equals(key))).go();

  Stream<String?> watchSetting(String key) {
    return (select(appSettings)..where((t) => t.key.equals(key))).watchSingleOrNull().map((row) => row?.value);
  }

  // --- Accounts ---

  Stream<List<AccountRow>> watchAccounts() =>
      (select(accounts)..orderBy([(t) => OrderingTerm.desc(t.lastUsedAt)])).watch();

  Future<List<AccountRow>> allAccounts() => select(accounts).get();

  Stream<AccountRow?> watchCurrentAccount() =>
      (select(accounts)..where((t) => t.isCurrent.equals(true))).watchSingleOrNull();

  Future<AccountRow?> currentAccount() => (select(accounts)..where((t) => t.isCurrent.equals(true))).getSingleOrNull();

  Future<AccountRow?> accountById(String id) => (select(accounts)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The account with this user on this server, if it is already added.
  Future<AccountRow?> accountFor(String serverUrl, String userId) =>
      (select(accounts)..where((t) => t.serverUrl.equals(serverUrl) & t.userId.equals(userId))).getSingleOrNull();

  /// Inserts or replaces [row] and makes it the only current account.
  Future<void> putCurrentAccount(AccountsCompanion row) {
    return transaction(() async {
      await update(accounts).write(const AccountsCompanion(isCurrent: Value(false)));
      await into(accounts).insertOnConflictUpdate(row.copyWith(isCurrent: const Value(true)));
    });
  }

  /// Makes [id] the only current account.
  Future<void> setCurrentAccount(String id, {required int now}) {
    return transaction(() async {
      await update(accounts).write(const AccountsCompanion(isCurrent: Value(false)));
      await (update(accounts)..where((t) => t.id.equals(id))).write(
        AccountsCompanion(isCurrent: const Value(true), lastUsedAt: Value(now)),
      );
    });
  }

  Future<void> setAccountStatus(String id, String status) =>
      (update(accounts)..where((t) => t.id.equals(id))).write(AccountsCompanion(status: Value(status)));

  Future<void> setSelectedLibrary(String id, String? libraryId) => (update(
    accounts,
  )..where((t) => t.id.equals(id))).write(AccountsCompanion(selectedLibraryId: Value(libraryId)));

  Future<void> deleteAccount(String id) => (delete(accounts)..where((t) => t.id.equals(id))).go();
}

/// Keys used in [AppSettings].
abstract final class SettingKeys {
  static const themeMode = 'theme_mode';

  /// Set once the user finished onboarding (connected a server or chose to
  /// play files on this phone).
  static const onboarded = 'onboarded';

  /// A random id generated on first launch, sent to servers as deviceId.
  static const deviceId = 'device_id';
}
