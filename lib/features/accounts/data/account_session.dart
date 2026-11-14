// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/account_db.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_auth_api.dart';
import '../../../core/net/abs_client.dart';
import '../../../core/net/token_refresher.dart';
import '../../../core/socket/abs_socket.dart';
import '../../../core/storage/secure_store.dart';
import 'accounts_repository.dart';

/// Everything that exists while an account is the current one: its API
/// client, its cache database and its live socket. Replaced as a whole when
/// the user switches accounts, so nothing from one account can leak into
/// another.
class AccountSession {
  AccountSession({required this.account, required this.client, required this.db, required this.socket});

  final AccountRow account;
  final AbsClient client;
  final AccountDb db;
  final AbsSocket socket;

  String get accountId => account.id;
  SourceId get source => AbsSource(account.id);

  Future<void> dispose() async {
    socket.dispose();
    client.close();
    await db.close();
  }
}

// --- Providers ---

final secureStoreProvider = Provider<SecureStore>((ref) => PlatformSecureStore());

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => AccountsRepository(db: ref.watch(globalDbProvider), store: ref.watch(secureStoreProvider)),
);

final accountsProvider = StreamProvider<List<AccountRow>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAccounts(),
);

final currentAccountProvider = StreamProvider<AccountRow?>(
  (ref) => ref.watch(accountsRepositoryProvider).watchCurrent(),
);

/// Receives what token refreshes learn and acts on it.
class _AppTokenEvents implements TokenEvents {
  _AppTokenEvents(this._ref);
  final Ref _ref;

  @override
  void needsReauth(String accountId) {
    unawaited(_ref.read(accountsRepositoryProvider).markNeedsReauth(accountId));
  }

  @override
  void tokensRotated(String accountId) {
    final session = _ref.read(accountSessionProvider);
    if (session?.accountId == accountId) unawaited(session!.socket.reauthenticate());
  }
}

final tokenRefresherProvider = Provider<TokenRefresher>((ref) {
  final repository = ref.watch(accountsRepositoryProvider);
  final db = ref.watch(globalDbProvider);
  return TokenRefresher(
    store: ref.watch(secureStoreProvider),
    events: _AppTokenEvents(ref),
    apiFor: (accountId) async {
      final account = await db.accountById(accountId);
      if (account == null) throw StateError('Unknown account');
      return repository.authApiFor(account);
    },
  );
});

/// Opens the cache database of an account. Overridable in tests.
final accountDbOpenerProvider = Provider<AccountDb Function(String accountId)>((ref) => AccountDb.open);

/// The session of the current account, or null when no account is current.
/// Rebuilt only when the current account (or its server) changes.
final accountSessionProvider = Provider<AccountSession?>((ref) {
  final key = ref.watch(
    currentAccountProvider.select((value) {
      final account = value.value;
      return account == null ? null : '${account.id}|${account.serverUrl}';
    }),
  );
  if (key == null) return null;
  final account = ref.read(currentAccountProvider).value!;
  final store = ref.read(secureStoreProvider);
  final refresher = ref.read(tokenRefresherProvider);
  final client = AbsClient.create(
    accountId: account.id,
    baseUrl: account.baseUrl,
    store: store,
    refresher: refresher,
  );
  final socket = AbsSocket(
    baseUrl: account.baseUrl,
    accessToken: () async {
      try {
        await refresher.refreshIfNeeded(account.id);
      } on Object {
        // Offline or rate limited: try with what is stored.
      }
      return store.readAccess(account.id);
    },
  );
  final session = AccountSession(
    account: account,
    client: client,
    db: ref.read(accountDbOpenerProvider)(account.id),
    socket: socket,
  );
  // Custom reverse-proxy headers live in the secure store, so the socket
  // connects once they are read.
  unawaited(
    store.readCustomHeaders(account.id).then((headers) {
      if (!account.needsReauth) socket.connect(headers: headers);
    }),
  );
  ref.onDispose(session.dispose);
  return session;
});

/// The auth API for a server that is not an account yet (sign-in screens).
final authApiFactoryProvider = Provider<AbsAuthApi Function(Uri baseUrl, Map<String, String> headers)>(
  (ref) =>
      (url, headers) => AbsAuthApi(url, headers: headers),
);
