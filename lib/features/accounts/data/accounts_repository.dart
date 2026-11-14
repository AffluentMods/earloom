// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/global_db.dart';
import '../../../core/net/abs_auth_api.dart';
import '../../../core/net/server_probe.dart';
import '../../../core/storage/secure_store.dart';

/// Account status values stored in [Accounts.status].
abstract final class AccountStatus {
  static const active = 'active';
  static const needsReauth = 'needsReauth';
}

extension AccountRowX on AccountRow {
  Uri get baseUrl => Uri.parse(serverUrl);
  bool get needsReauth => status == AccountStatus.needsReauth;
  bool get isAdmin => userType == 'root' || userType == 'admin';
  bool get usesOidc => authMethod == 'openid';
}

/// Adds, switches, signs out of and removes Audiobookshelf accounts.
/// Tokens go to the [SecureStore]; everything else to [GlobalDb].
class AccountsRepository {
  AccountsRepository({
    required this._db,
    required this._store,
    AbsAuthApi Function(Uri baseUrl, Map<String, String> headers)? authApi,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _authApi = authApi ?? ((url, headers) => AbsAuthApi(url, dio: Dio(), headers: headers)),
       _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => const Uuid().v4());

  final GlobalDb _db;
  final SecureStore _store;
  final AbsAuthApi Function(Uri baseUrl, Map<String, String> headers) _authApi;
  final DateTime Function() _clock;
  final String Function() _newId;

  Stream<List<AccountRow>> watchAccounts() => _db.watchAccounts();
  Stream<AccountRow?> watchCurrent() => _db.watchCurrentAccount();
  Future<AccountRow?> current() => _db.currentAccount();

  /// The auth API for an existing account, with its custom headers.
  Future<AbsAuthApi> authApiFor(AccountRow account) async =>
      _authApi(account.baseUrl, await _store.readCustomHeaders(account.id));

  /// Signs in with a username and password and makes the account current.
  /// Signing in again as the same user on the same server reuses the
  /// existing account (and its cache and downloads).
  Future<AccountRow> signInWithPassword(
    ProbeOk server, {
    required String username,
    required String password,
    Map<String, String> headers = const {},
  }) async {
    final result = await _authApi(server.baseUrl, headers).login(username.trim(), password);
    return _save(server, result, headers: headers, method: 'local');
  }

  /// Stores the result of a finished single sign-on.
  Future<AccountRow> completeOidc(ProbeOk server, AuthResult result, {Map<String, String> headers = const {}}) =>
      _save(server, result, headers: headers, method: 'openid');

  Future<AccountRow> _save(
    ProbeOk server,
    AuthResult result, {
    required Map<String, String> headers,
    required String method,
  }) async {
    final url = server.baseUrl.toString();
    final existing = await _db.accountFor(url, result.userId);
    final id = existing?.id ?? _newId();
    final now = _clock().millisecondsSinceEpoch;
    await _store.writeTokens(id, access: result.accessToken, refresh: result.refreshToken);
    await _store.writeCustomHeaders(id, headers);
    await _db.putCurrentAccount(
      AccountsCompanion.insert(
        id: id,
        serverUrl: url,
        displayName: existing?.displayName ?? server.baseUrl.host,
        serverVersion: server.version.toString(),
        userId: result.userId,
        username: result.username,
        userType: result.userType,
        authMethod: method,
        status: const Value(AccountStatus.active),
        defaultLibraryId: Value(result.defaultLibraryId),
        selectedLibraryId: Value(existing?.selectedLibraryId ?? result.defaultLibraryId),
        serverTimeZone: Value(result.serverTimeZone),
        createdAt: existing?.createdAt ?? now,
        lastUsedAt: now,
      ),
    );
    await _db.writeSetting(SettingKeys.onboarded, 'true');
    return (await _db.accountById(id))!;
  }

  Future<void> switchTo(String accountId) => _db.setCurrentAccount(accountId, now: _clock().millisecondsSinceEpoch);

  /// Marks the account as needing a new sign-in. Cache, downloads and local
  /// progress stay: losing a sign-in never loses data.
  Future<void> markNeedsReauth(String accountId) => _db.setAccountStatus(accountId, AccountStatus.needsReauth);

  /// Ends the server session and forgets the tokens. Keeps the account row,
  /// cache and downloads, so signing in again picks up where it left off.
  Future<void> signOut(String accountId) async {
    final account = await _db.accountById(accountId);
    final refresh = await _store.readRefresh(accountId);
    if (account != null && refresh != null) await (await authApiFor(account)).logout(refresh);
    await _store.deleteTokens(accountId);
    await markNeedsReauth(accountId);
  }

  /// Signs out and forgets the account entirely. The caller deletes the
  /// account's cache database and downloads (it owns those files). If it was
  /// current, the most recently used remaining account becomes current.
  Future<void> remove(String accountId) async {
    await signOut(accountId);
    await _store.deleteAccount(accountId);
    final wasCurrent = (await _db.accountById(accountId))?.isCurrent ?? false;
    await _db.deleteAccount(accountId);
    if (wasCurrent) {
      final rest = await _db.allAccounts();
      if (rest.isNotEmpty) {
        rest.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
        await switchTo(rest.first.id);
      }
    }
  }
}
