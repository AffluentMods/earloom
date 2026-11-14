// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';

/// Audiobookshelf accounts on this device (GlobalDb). Tokens are not here:
/// they live in the secure store.
@DataClassName('AccountRow')
class Accounts extends Table {
  /// Local id (uuid v4). Also names the account's database file.
  TextColumn get id => text()();

  /// Normalized base URL, no trailing slash.
  TextColumn get serverUrl => text()();

  /// Shown in the accounts list. Defaults to the server's host name.
  TextColumn get displayName => text()();
  TextColumn get serverVersion => text()();
  TextColumn get userId => text()();
  TextColumn get username => text()();

  /// root, admin, user or guest.
  TextColumn get userType => text()();

  /// `local` or `openid`.
  TextColumn get authMethod => text()();

  /// `active` or `needsReauth`.
  TextColumn get status => text().withDefault(const Constant('active'))();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  TextColumn get defaultLibraryId => text().nullable()();

  /// The library the user last looked at in this account.
  TextColumn get selectedLibraryId => text().nullable()();

  /// IANA time zone of the server, for stats day buckets.
  TextColumn get serverTimeZone => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get lastUsedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
