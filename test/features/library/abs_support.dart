// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/net/abs_client.dart';
import 'package:earloom/core/net/token_refresher.dart';
import 'package:earloom/core/socket/abs_socket.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

const testAccountId = 'acct-affluent';
const testLibraryId = '9c69912d-0de3-4102-a1ce-50b7967c8141';
const testSource = AbsSource(testAccountId);
final testBaseUrl = Uri.parse('https://abs.example.test');

/// A fixture from test/fixtures/abs, decoded.
Object? fixture(String name) => jsonDecode(File('test/fixtures/abs/$name.json').readAsStringSync());

/// A fake Audiobookshelf server: answers each path with a fixture or a
/// handler, records every request, and can go offline.
class FakeAbsServer {
  FakeAbsServer({Map<String, Object? Function(RequestOptions r)>? routes}) : routes = {...defaultRoutes, ...?routes};

  /// Path to answer. Values are fixture names (String), JSON (anything
  /// else), or a handler. A null answer is 404.
  static final Map<String, Object? Function(RequestOptions r)> defaultRoutes = {
    '/api/libraries': (_) => fixture('libraries_list'),
    '/api/me': (_) => fixture('me_user'),
    '/api/me/items-in-progress': (_) => fixture('me_items_in_progress'),
    '/api/libraries/$testLibraryId/items': (r) => r.uri.queryParameters['filter']?.startsWith('series.') ?? false
        ? fixture('library_items_series_filter')
        : fixture('library_items_page'),
    '/api/libraries/$testLibraryId/personalized': (_) => fixture('library_personalized_book'),
    '/api/libraries/$testLibraryId/series': (_) => fixture('library_series'),
    '/api/libraries/$testLibraryId/authors': (_) => fixture('library_authors'),
    '/api/libraries/$testLibraryId/collections': (_) => fixture('library_collections'),
    '/api/libraries/$testLibraryId/playlists': (_) => fixture('library_playlists'),
    '/api/libraries/$testLibraryId/filterdata': (_) => fixture('library_filterdata_book'),
    '/api/libraries/$testLibraryId/search': (_) => fixture('library_search_book'),
    '/api/series/d22d1a16-8a7a-4fef-b740-7d3e5b98f093': (_) => fixture('library_series_one'),
    '/api/items/695b9eb3-1a88-4320-b033-95089797f205': (_) => fixture('item_book_expanded'),
    '/api/authors/e271d8df-7aa6-43d5-8e62-5b661bf2aafa': (_) => fixture('author_expanded'),
  };

  final Map<String, Object? Function(RequestOptions r)> routes;
  final requests = <RequestOptions>[];
  bool offline = false;

  /// Delays answers to a path, to test what happens while a request runs.
  final delays = <String, Future<void>>{};

  Future<FakeResponse> handle(RequestOptions r) async {
    requests.add(r);
    final delay = delays[r.uri.path];
    if (delay != null) await delay;
    if (offline) throw connectionError(r);
    final route = routes[r.uri.path];
    if (route == null) return const FakeResponse(404, 'Not Found');
    final body = route(r);
    if (body == null) return const FakeResponse(404, 'Not Found');
    if (body is FakeResponse) return body;
    return FakeResponse.json(200, body);
  }

  List<RequestOptions> requestsTo(String path) => [
    for (final r in requests)
      if (r.uri.path == path) r,
  ];
}

class _NoEvents implements TokenEvents {
  @override
  void needsReauth(String accountId) {}

  @override
  void tokensRotated(String accountId) {}
}

/// An AbsClient that talks to [server], with a long-lived access token so it
/// never refreshes.
Future<AbsClient> fakeAbsClient(FakeAbsServer server) async {
  final store = MemorySecureStore();
  await store.writeTokens(
    testAccountId,
    access: fakeJwt(exp: DateTime.now().add(const Duration(days: 365))),
    refresh: 'refresh',
  );
  final (dio, _) = fakeDio(server.handle);
  return AbsClient.create(
    accountId: testAccountId,
    baseUrl: testBaseUrl,
    store: store,
    refresher: TokenRefresher(store: store, events: _NoEvents(), apiFor: (_) => throw StateError('no refresh')),
    dio: dio,
  );
}

/// An in-memory AccountDb for unit tests.
AccountDb memoryAccountDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AccountDb(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

/// An in-memory AccountDb for widget tests (streams close synchronously).
Future<AccountDb> openTestAccountDb(WidgetTester tester) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AccountDb(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  await tester.runAsync(() => db.catalogDao.allLibraries());
  addTearDown(() => tester.runAsync(db.close));
  return db;
}

Future<AbsLibraryRepository> fakeRepository(FakeAbsServer server, AccountDb db, {DateTime Function()? clock}) async =>
    AbsLibraryRepository(db: db, client: await fakeAbsClient(server), source: testSource, clock: clock);

/// A session for the current account that talks to [server]. The socket is
/// never connected; add events with [FakeSocket].
Future<AccountSession> fakeSession(FakeAbsServer server, AccountDb db) async {
  return AccountSession(
    account: AccountRow(
      id: testAccountId,
      serverUrl: testBaseUrl.toString(),
      displayName: 'Demo server',
      serverVersion: '2.37.2',
      userId: 'user-1',
      username: 'affluent',
      userType: 'user',
      authMethod: 'local',
      status: 'active',
      isCurrent: true,
      createdAt: 1,
      lastUsedAt: 1,
    ),
    client: await fakeAbsClient(server),
    db: db,
    socket: AbsSocket(baseUrl: testBaseUrl, accessToken: () async => null),
  );
}

/// Secure store with nothing in it, for session overrides.
SecureStore emptyStore() => MemorySecureStore();
