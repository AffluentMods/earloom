// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/native.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/abs_errors.dart';
import 'package:earloom/core/net/server_probe.dart';
import 'package:earloom/core/net/server_version.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/accounts/data/accounts_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

ProbeOk server(String url) => ProbeOk(
  baseUrl: Uri.parse(url),
  version: const ServerVersion(2, 37, 2),
  authMethods: const {AuthMethod.local},
);

Map<String, Object?> loginBody({String userId = 'u1', String username = 'affluent', String type = 'user'}) => {
  'user': {
    'id': userId,
    'username': username,
    'type': type,
    'token': 'legacy-should-be-dropped',
    'accessToken': 'access-$userId',
    'refreshToken': 'refresh-$userId',
  },
  'userDefaultLibraryId': 'lib1',
  'serverSettings': {'timeZone': 'Europe/Amsterdam'},
};

void main() {
  late GlobalDb db;
  late MemorySecureStore store;
  late List<String> logouts;
  var ids = 0;

  AccountsRepository repository({FakeResponse? loginAnswer}) => AccountsRepository(
    db: db,
    store: store,
    newId: () => 'acct${++ids}',
    clock: () => DateTime.utc(2026, 11, 14),
    authApi: (url, headers) {
      final (dio, _) = fakeDio((r) async {
        if (r.uri.path.endsWith('/logout')) {
          logouts.add(r.headers['x-refresh-token'] as String);
          return FakeResponse.json(200, {'redirect_url': null});
        }
        final body = r.data as Map;
        if (body['password'] != 'right') return const FakeResponse(401, 'Unauthorized');
        return loginAnswer ?? FakeResponse.json(200, loginBody(username: body['username'] as String));
      });
      return AbsAuthApi(url, dio: dio, headers: headers);
    },
  );

  setUp(() {
    db = GlobalDb(NativeDatabase.memory());
    store = MemorySecureStore();
    logouts = [];
    ids = 0;
  });
  tearDown(() => db.close());

  test('signing in stores the account as current, tokens only in the secure store', () async {
    final repo = repository();
    final account = await repo.signInWithPassword(
      server('https://books.example.com'),
      username: ' affluent ',
      password: 'right',
      headers: {'CF-Access-Client-Id': 'abc'},
    );
    expect(account.isCurrent, isTrue);
    expect(account.username, 'affluent');
    expect(account.displayName, 'books.example.com');
    expect(account.serverTimeZone, 'Europe/Amsterdam');
    expect(account.selectedLibraryId, 'lib1');
    expect(await store.readAccess(account.id), 'access-u1');
    expect(await store.readCustomHeaders(account.id), {'CF-Access-Client-Id': 'abc'});
    expect(await db.readSetting(SettingKeys.onboarded), 'true');
    // Nothing secret in SQLite.
    final row = (await db.allAccounts()).single;
    expect(row.toString(), isNot(contains('access-u1')));
    expect(row.toString(), isNot(contains('legacy')));
  });

  test('wrong password is a typed failure and stores nothing', () async {
    final repo = repository();
    await expectLater(
      repo.signInWithPassword(server('https://books.example.com'), username: 'affluent', password: 'wrong'),
      throwsA(isA<AbsUnauthorized>()),
    );
    expect(await db.allAccounts(), isEmpty);
    expect(store.values, isEmpty);
  });

  test('only one account is current; switching moves it', () async {
    final repo = repository();
    final a = await repo.signInWithPassword(server('https://one.example.com'), username: 'affluent', password: 'right');
    final b = await repo.signInWithPassword(server('https://two.example.com'), username: 'affluent', password: 'right');
    expect((await db.allAccounts()).where((r) => r.isCurrent).map((r) => r.id), [b.id]);
    await repo.switchTo(a.id);
    expect((await db.allAccounts()).where((r) => r.isCurrent).map((r) => r.id), [a.id]);
  });

  test('signing in again as the same user reuses the account', () async {
    final repo = repository();
    final first = await repo.signInWithPassword(
      server('https://one.example.com'),
      username: 'affluent',
      password: 'right',
    );
    await repo.signOut(first.id);
    final again = await repo.signInWithPassword(
      server('https://one.example.com'),
      username: 'affluent',
      password: 'right',
    );
    expect(again.id, first.id);
    expect(again.needsReauth, isFalse);
    expect(await db.allAccounts(), hasLength(1));
  });

  test('sign out ends the server session, forgets tokens, keeps the account', () async {
    final repo = repository();
    final a = await repo.signInWithPassword(server('https://one.example.com'), username: 'affluent', password: 'right');
    await repo.signOut(a.id);
    expect(logouts, ['refresh-u1']);
    expect(await store.readAccess(a.id), isNull);
    expect(await store.readRefresh(a.id), isNull);
    final row = (await db.accountById(a.id))!;
    expect(row.needsReauth, isTrue);
  });

  test('removing the current account forgets everything and makes the latest other one current', () async {
    final repo = repository();
    final a = await repo.signInWithPassword(server('https://one.example.com'), username: 'affluent', password: 'right');
    final b = await repo.signInWithPassword(server('https://two.example.com'), username: 'affluent', password: 'right');
    await store.writeCustomHeaders(b.id, {'x': 'y'});
    await repo.remove(b.id);
    expect(await db.accountById(b.id), isNull);
    expect(store.values.keys.where((k) => k.contains(b.id)), isEmpty);
    expect((await db.currentAccount())?.id, a.id);
  });

  test('migrating a version 1 database keeps settings and adds accounts', () async {
    // Version 1 had only app_settings.
    final v1 = NativeDatabase.memory(
      setup: (raw) {
        raw.execute('CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)');
        raw.execute("INSERT INTO app_settings VALUES ('theme_mode', 'dark')");
        raw.execute('PRAGMA user_version = 1');
      },
    );
    final migrated = GlobalDb(v1);
    addTearDown(migrated.close);
    expect(await migrated.readSetting(SettingKeys.themeMode), 'dark');
    expect(await migrated.allAccounts(), isEmpty);
  });
}
